-- Fuxia 360 · Canal de producción, unidad U1 — capacidades por canal (docs/fuxia360/ops/CANAL_PRODUCCION_CATALOGO.md). Mario 2026-10-06.
-- Separates "active" (storefront, stock, orders, counts) from "catalog on" (publish, merge, show/hide, content) so the
-- production channel can receive Carolina's catalog while it stays INACTIVE (not exposed to anon, not the online location,
-- no stock, no orders). Behaviour of every existing non-production channel (staging4, local, tests) is UNCHANGED.
--   · sales_targets: catalog_mode, stock_sync_mode, storefront_enabled, auto_propagate, stock_policy, allow_term_create.
--   · f360.catalog_target(key): the channel for catalog operations. Non-production: as before (active is enough, any new test
--     channel works at once). Production: catalog_mode='on' (the switch only gates production).
--   · 7 catalog functions use it instead of target_by_key / their is_production refusal. ONLY those lines change.
--   · Stock, orders, opening counts and homologation keep refusing production (target_by_key unchanged).
--   · f360_set_channel_capabilities: owner only; a production channel needs the typed domain; production stock cannot be turned
--     on here (separate approval); every change audited (append-only).
-- Rollback: supabase/rollbacks/20261012000100_f360_channel_capabilities.down.sql

ALTER TABLE f360.sales_targets
  ADD COLUMN catalog_mode       text    NOT NULL DEFAULT 'off' CHECK (catalog_mode IN ('off', 'on')),
  ADD COLUMN stock_sync_mode    text    NOT NULL DEFAULT 'off' CHECK (stock_sync_mode IN ('off', 'on')),
  ADD COLUMN storefront_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN auto_propagate     boolean NOT NULL DEFAULT false,
  ADD COLUMN stock_policy       text    NOT NULL DEFAULT 'woo_owned' CHECK (stock_policy IN ('f360_owned', 'woo_owned')),
  ADD COLUMN allow_term_create  boolean NOT NULL DEFAULT false;
-- Existing non-production channels keep doing exactly what they do today.
UPDATE f360.sales_targets SET catalog_mode = 'on', stock_sync_mode = 'on', storefront_enabled = true, stock_policy = 'f360_owned', allow_term_create = true
WHERE NOT is_production;
COMMENT ON COLUMN f360.sales_targets.catalog_mode IS 'U1: on = F360 may publish / merge / show-hide / push content to this store, even while the channel is inactive.';
COMMENT ON COLUMN f360.sales_targets.stock_sync_mode IS 'U1: on = F360 pushes stock and ingests orders. Production stays off until the inventory pase (separate approval).';

CREATE TABLE f360.channel_capability_changes (
  id          bigserial PRIMARY KEY,
  target_id   uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  before      jsonb NOT NULL,
  after       jsonb NOT NULL,
  by_user     uuid,
  by_name     text NOT NULL,
  at          timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER channel_capability_changes_append_only BEFORE UPDATE OR DELETE ON f360.channel_capability_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.channel_capability_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.channel_capability_changes FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.catalog_target(p_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda % no configurada.', p_key; END IF;
  IF t.is_production THEN
    IF t.catalog_mode <> 'on' THEN RAISE EXCEPTION 'El catálogo de la tienda de producción no está encendido.'; END IF;
  ELSIF NOT t.active THEN                                    -- non-production: exactly as before U1 (active is enough)
    RAISE EXCEPTION 'Tienda % no configurada.', p_key;
  END IF;
  RETURN t;
END $$;

-- resolve_target (publishing): by key, a production channel is found through its catalog switch; without key, unchanged.
CREATE OR REPLACE FUNCTION f360.resolve_target(p_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $$
DECLARE t f360.sales_targets; n int;
BEGIN
  IF p_key IS NOT NULL THEN
    RETURN f360.catalog_target(p_key);
  ELSE
    SELECT count(*) INTO n FROM f360.sales_targets WHERE active;
    IF n > 1 THEN RAISE EXCEPTION 'Hay más de una tienda en línea configurada; elige una.'; END IF;
    SELECT * INTO t FROM f360.sales_targets WHERE active;
  END IF;
  IF t.id IS NULL THEN RAISE EXCEPTION 'No hay una tienda en línea configurada para publicar.'; END IF;
  RETURN t;
END $$;

CREATE OR REPLACE FUNCTION f360.content_target(p_target_key text)
 RETURNS f360.sales_targets
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN f360.catalog_target(p_target_key);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_consolidate_finish(p_target_key text, p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles; t f360.sales_targets; c f360.legacy_consolidations; l f360.woo_product_links; x jsonb; v_name text;
BEGIN
  r := f360.require_role('owner');
  t := f360.catalog_target(p_target_key);
  SELECT * INTO c FROM f360.legacy_consolidations WHERE target_id = t.id AND product_id = p_product_id FOR UPDATE;
  IF c.product_id IS NULL THEN RAISE EXCEPTION 'Ese modelo no se está uniendo.'; END IF;
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  IF l.woo_product_id IS NULL OR NOT EXISTS (SELECT 1 FROM f360.sync_jobs WHERE id = c.job_id AND status = 'succeeded') THEN
    RAISE EXCEPTION 'Todavía no se publica el producto nuevo.';
  END IF;
  SELECT name INTO v_name FROM f360.products WHERE id = p_product_id;
  IF c.status <> 'publicada' THEN
    INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
      VALUES (t.id, l.woo_product_id, v_name, 'mostrar', 'Producto único del modelo (unión de colores)', auth.uid(), r.display_name)
      ON CONFLICT DO NOTHING;
    FOR x IN SELECT * FROM jsonb_array_elements(c.legacy_products) LOOP
      INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
        VALUES (t.id, (x->>'woo_product_id')::int, x->>'name', 'ocultar', 'Unido en “' || v_name || '”', auth.uid(), r.display_name)
        ON CONFLICT DO NOTHING;
    END LOOP;
    INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
      SELECT t.id, vl.variant_id, 'Unión de colores' FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE vl.target_id = t.id AND v.product_id = p_product_id
    ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = EXCLUDED.reason;
    UPDATE f360.legacy_consolidations SET status = 'publicada', new_woo_product_id = l.woo_product_id, finished_by = r.display_name, finished_at = clock_timestamp()
      WHERE target_id = t.id AND product_id = p_product_id RETURNING * INTO c;
  END IF;
  RETURN jsonb_build_object('product_id', c.product_id, 'name', v_name, 'status', c.status, 'new_woo_product_id', c.new_woo_product_id,
    'new_path', '/producto/' || (SELECT slug FROM f360.products WHERE id = p_product_id) || '/', 'legacy_products', c.legacy_products);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_consolidate_start(p_target_key text, p_product_ids uuid[] DEFAULT NULL::uuid[], p_legacy_paths jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles; t f360.sales_targets; x record; ready jsonb; job jsonb; out jsonb := '[]'; skipped jsonb := '[]'; legacy jsonb;
BEGIN
  r := f360.require_role('owner');
  t := f360.catalog_target(p_target_key);
  FOR x IN SELECT v.product_id, p.name, count(DISTINCT m.woo_product_id) AS n
           FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id JOIN f360.products p ON p.id = v.product_id
           WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
             AND (p_product_ids IS NULL OR v.product_id = ANY (p_product_ids))
           GROUP BY v.product_id, p.name ORDER BY p.name LOOP
    IF p_product_ids IS NULL AND x.n < 2 THEN CONTINUE; END IF;
    IF f360.is_consolidated(t.id, x.product_id) THEN
      -- a publish that failed or stayed partial (e.g. the store timed out uploading photos) is retried with a new job;
      -- the publisher finds what the store already created by SKU / photo name, so nothing is duplicated
      IF EXISTS (SELECT 1 FROM f360.legacy_consolidations c JOIN f360.sync_jobs j ON j.id = c.job_id
                 WHERE c.target_id = t.id AND c.product_id = x.product_id AND c.status = 'publicando' AND j.status IN ('failed', 'partial')) THEN
        job := public.f360_request_publish(x.product_id, gen_random_uuid(), p_target_key);
        UPDATE f360.legacy_consolidations SET job_id = (job->>'id')::uuid WHERE target_id = t.id AND product_id = x.product_id;
      END IF;
      SELECT jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job_id, 'status', status) INTO job
        FROM f360.legacy_consolidations WHERE target_id = t.id AND product_id = x.product_id;
      out := out || job; CONTINUE;
    END IF;
    ready := f360.product_readiness(x.product_id);
    IF NOT (ready->>'ready')::boolean THEN
      skipped := skipped || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'missing', ready->'missing'); CONTINUE;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', w.woo_product_id, 'name', w.name, 'path', p_legacy_paths->>(w.woo_product_id::text)) ORDER BY w.woo_product_id), '[]')
      INTO legacy FROM (SELECT DISTINCT m.woo_product_id, min(m.woo_product_name) AS name FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
                        WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id GROUP BY m.woo_product_id) w;
    INSERT INTO f360.legacy_consolidations (target_id, product_id, legacy_products, requested_by) VALUES (t.id, x.product_id, legacy, r.display_name);
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT vl.target_id, vl.woo_variation_id, vl.woo_product_id, vl.variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    -- also every confirmed legacy variation that was never linked (orders can still name it)
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT m.target_id, m.woo_variation_id, m.woo_product_id, m.confirmed_variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    DELETE FROM f360.stock_sync_queue q USING f360.woo_variant_links vl, f360.product_variants v
      WHERE q.target_id = t.id AND q.variant_id = vl.variant_id AND vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    DELETE FROM f360.woo_variant_links vl USING f360.product_variants v
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    job := public.f360_request_publish(x.product_id, gen_random_uuid(), p_target_key);
    UPDATE f360.legacy_consolidations SET job_id = (job->>'id')::uuid WHERE target_id = t.id AND product_id = x.product_id;
    out := out || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job->>'id', 'status', 'publicando');
  END LOOP;
  RETURN jsonb_build_object('items', out, 'skipped', skipped);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_consolidations(p_target_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets;
BEGIN
  PERFORM f360.require_role('viewer');
  t := f360.catalog_target(p_target_key);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('product_id', c.product_id, 'name', p.name, 'status', c.status, 'job_status', j.status, 'job_error', j.error_message,
      'new_woo_product_id', c.new_woo_product_id, 'new_path', '/producto/' || p.slug || '/', 'legacy_products', c.legacy_products,
      'requested_at', c.requested_at, 'finished_at', c.finished_at) ORDER BY p.name), '[]')
    FROM f360.legacy_consolidations c JOIN f360.products p ON p.id = c.product_id LEFT JOIN f360.sync_jobs j ON j.id = c.job_id WHERE c.target_id = t.id);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_store_visibility_request(p_target_key text, p_woo_product_id integer, p_kind text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles; t f360.sales_targets; v_name text; v_last f360.woo_visibility_requests;
BEGIN
  r := f360.require_role('operator');
  t := f360.catalog_target(p_target_key);
  IF p_kind NOT IN ('ocultar', 'mostrar') THEN RAISE EXCEPTION 'Acción no válida.'; END IF;
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT min(woo_product_name) INTO v_name FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_product_id = p_woo_product_id;
  IF v_name IS NULL THEN RAISE EXCEPTION 'Ese producto no está en el catálogo leído de la tienda.'; END IF;
  IF p_kind = 'ocultar' AND EXISTS (SELECT 1 FROM f360.legacy_woo_map WHERE target_id = t.id AND woo_product_id = p_woo_product_id
       AND NOT (status = 'sin_correspondencia' AND human_locked)) THEN
    RAISE EXCEPTION 'Solo se ocultan productos que se marcaron “no existe” en todas sus tallas.';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.woo_visibility_requests WHERE target_id = t.id AND woo_product_id = p_woo_product_id AND status = 'pendiente') THEN
    RAISE EXCEPTION 'Ya hay una solicitud pendiente para “%”.', v_name;
  END IF;
  SELECT * INTO v_last FROM f360.woo_visibility_requests WHERE target_id = t.id AND woo_product_id = p_woo_product_id AND status = 'hecho' ORDER BY done_at DESC LIMIT 1;
  IF p_kind = 'mostrar' AND (v_last.id IS NULL OR v_last.kind <> 'ocultar') THEN RAISE EXCEPTION '“%” no se ocultó desde Fuxia 360.', v_name; END IF;
  IF p_kind = 'ocultar' AND v_last.kind = 'ocultar' THEN RAISE EXCEPTION '“%” ya está oculto.', v_name; END IF;
  INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
    VALUES (t.id, p_woo_product_id, v_name, p_kind, btrim(p_reason), auth.uid(), r.display_name);
  RETURN f360.woo_visibility(t.id, p_woo_product_id) || jsonb_build_object('woo_product_id', p_woo_product_id, 'name', v_name);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_visibility_claim(p_target_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets; out jsonb;
BEGIN
  t := f360.catalog_target(p_target_key);
  WITH c AS (
    UPDATE f360.woo_visibility_requests q SET claimed_at = clock_timestamp(), attempts = attempts + 1
    WHERE q.id IN (SELECT id FROM f360.woo_visibility_requests WHERE target_id = t.id AND status = 'pendiente'
                     AND (claimed_at IS NULL OR claimed_at < clock_timestamp() - interval '2 minutes') ORDER BY requested_at LIMIT 50 FOR UPDATE SKIP LOCKED)
    RETURNING q.id, q.woo_product_id, q.kind,
      (SELECT p.woo_status_before FROM f360.woo_visibility_requests p WHERE p.target_id = q.target_id AND p.woo_product_id = q.woo_product_id
         AND p.kind = 'ocultar' AND p.status = 'hecho' ORDER BY p.done_at DESC LIMIT 1) AS restore_status)
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'woo_product_id', woo_product_id, 'kind', kind, 'restore_status', restore_status)), '[]') INTO out FROM c;
  RETURN out;
END $function$;

CREATE OR REPLACE FUNCTION public.f360_visibility_result(p_target_key text, p_results jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets; n_ok int; n_err int;
BEGIN
  t := f360.catalog_target(p_target_key);
  UPDATE f360.woo_visibility_requests q SET status = CASE WHEN x.ok THEN 'hecho' WHEN q.attempts >= 3 THEN 'error' ELSE 'pendiente' END,
      done_at = CASE WHEN x.ok THEN clock_timestamp() END, woo_status_before = coalesce(x.before, q.woo_status_before), woo_status_after = x.after,
      error = x.error, claimed_at = NULL
    FROM jsonb_to_recordset(coalesce(p_results, '[]')) x(id uuid, ok boolean, before text, after text, error text)
    WHERE q.id = x.id AND q.target_id = t.id;
  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) FILTER (WHERE NOT (x->>'ok')::boolean) INTO n_ok, n_err FROM jsonb_array_elements(coalesce(p_results, '[]')) x;
  RETURN jsonb_build_object('ok', n_ok, 'failed', n_err);
END $function$;

CREATE FUNCTION public.f360_set_channel_capabilities(p_target_key text, p_changes jsonb, p_confirm_domain text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); t f360.sales_targets; j jsonb := coalesce(p_changes, '{}'); bad text; before jsonb; after jsonb;
  allowed text[] := ARRAY['catalog_mode', 'stock_sync_mode', 'storefront_enabled', 'auto_propagate', 'stock_policy', 'allow_term_create'];
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda no encontrada.'; END IF;
  SELECT string_agg(key, ', ') INTO bad FROM jsonb_object_keys(j) key WHERE key <> ALL (allowed);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'Campos no permitidos: %.', bad; END IF;
  IF t.is_production THEN
    IF lower(coalesce(p_confirm_domain, '')) <> lower(substring(t.base_url from '^https?://([^/]+)')) THEN
      RAISE EXCEPTION 'Para cambiar la tienda de producción escribe su dominio exacto para confirmar.';
    END IF;
    IF j ? 'stock_sync_mode' AND j->>'stock_sync_mode' = 'on' THEN
      RAISE EXCEPTION 'El stock de producción se enciende en el paso del inventario, con aprobación aparte.';
    END IF;
    IF j ? 'storefront_enabled' AND (j->>'storefront_enabled')::boolean THEN
      RAISE EXCEPTION 'La tienda pública de producción se enciende con el pase de la tienda, con aprobación aparte.';
    END IF;
  END IF;
  before := jsonb_build_object('catalog_mode', t.catalog_mode, 'stock_sync_mode', t.stock_sync_mode, 'storefront_enabled', t.storefront_enabled,
    'auto_propagate', t.auto_propagate, 'stock_policy', t.stock_policy, 'allow_term_create', t.allow_term_create);
  UPDATE f360.sales_targets SET
    catalog_mode       = coalesce(j->>'catalog_mode', catalog_mode),
    stock_sync_mode    = coalesce(j->>'stock_sync_mode', stock_sync_mode),
    storefront_enabled = coalesce((j->>'storefront_enabled')::boolean, storefront_enabled),
    auto_propagate     = coalesce((j->>'auto_propagate')::boolean, auto_propagate),
    stock_policy       = coalesce(j->>'stock_policy', stock_policy),
    allow_term_create  = coalesce((j->>'allow_term_create')::boolean, allow_term_create)
  WHERE id = t.id RETURNING jsonb_build_object('catalog_mode', catalog_mode, 'stock_sync_mode', stock_sync_mode, 'storefront_enabled', storefront_enabled,
    'auto_propagate', auto_propagate, 'stock_policy', stock_policy, 'allow_term_create', allow_term_create) INTO after;
  IF after IS DISTINCT FROM before THEN
    INSERT INTO f360.channel_capability_changes (target_id, before, after, by_user, by_name) VALUES (t.id, before, after, r.auth_user_id, r.display_name);
  END IF;
  RETURN jsonb_build_object('ok', true, 'target', t.key, 'capabilities', after);
END $$;

CREATE FUNCTION public.f360_channel_capabilities() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer');
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('key', key, 'name', name, 'base_url', base_url, 'active', active, 'is_production', is_production, 'is_test', is_test,
    'catalog_mode', catalog_mode, 'stock_sync_mode', stock_sync_mode, 'storefront_enabled', storefront_enabled, 'auto_propagate', auto_propagate,
    'stock_policy', stock_policy, 'allow_term_create', allow_term_create) ORDER BY is_production DESC, key) FROM f360.sales_targets), '[]');
END $$;

REVOKE ALL ON FUNCTION f360.catalog_target(text), public.f360_set_channel_capabilities(text, jsonb, text), public.f360_channel_capabilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_set_channel_capabilities(text, jsonb, text), public.f360_channel_capabilities() TO authenticated;
