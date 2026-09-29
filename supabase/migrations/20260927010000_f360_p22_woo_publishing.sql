-- Fuxia 360 P2.2 — WooCommerce publishing infrastructure (Migration B of WOO_PUBLISHING_V1_PLAN).
-- Additive only. The inventory ledger is untouched. No Woo credentials are stored in the database.
--
--   f360.sales_targets        one row per Woo environment (local docker / staging / production — never mixed)
--   f360.woo_category_links   F360 category → STABLE Woo category ID per target (never by name; never auto-created)
--   f360.woo_product_links    F360 model   ↔ Woo variable product per target (+ published content hash)
--   f360.woo_variant_links    F360 variant ↔ Woo variation per target (+ last pushed stock)
--   f360.woo_media_links      F360 photo   ↔ Woo media id per target (upload once)
--   f360.sync_jobs            one publish attempt (who, when, status, error) — status transitions only via RPC
--   f360.sync_job_steps       every step of every attempt — append-only
--
-- Publishing is owner-only (DW8), created in a non-public state (DW3), idempotent (links → SKU lookup → create).
-- The legacy single-target columns products.wc_product_id / product_variants.wc_variation_id stay UNUSED.
-- Rollback: supabase/rollbacks/20260927010000_f360_p22_woo_publishing.down.sql

-- ── Targets ─────────────────────────────────────────────────────────────────
CREATE TABLE f360.sales_targets (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key                      text NOT NULL UNIQUE CHECK (key ~ '^[a-z0-9_]+$'),
  name                     text NOT NULL,
  kind                     text NOT NULL DEFAULT 'woocommerce' CHECK (kind = 'woocommerce'),
  base_url                 text NOT NULL,
  is_production            boolean NOT NULL DEFAULT false,
  fulfillment_location_id  uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  active                   boolean NOT NULL DEFAULT true,
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE f360.woo_category_links (
  target_id     uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  category_key  text NOT NULL REFERENCES f360.categories(key) ON DELETE RESTRICT,
  woo_term_id   integer NOT NULL CHECK (woo_term_id > 0),
  woo_slug      text NOT NULL,                      -- recorded for verification only; the ID is the identity
  verified_at   timestamptz,
  PRIMARY KEY (target_id, category_key),
  UNIQUE (target_id, woo_term_id)
);

-- ── Links (one source of truth per target) ──────────────────────────────────
CREATE TABLE f360.woo_product_links (
  target_id        uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  product_id       uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  woo_product_id   integer NOT NULL CHECK (woo_product_id > 0),
  woo_status       text,
  published_hash   text,
  last_success_at  timestamptz,
  last_job_id      uuid,
  linked_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, product_id),
  UNIQUE (target_id, woo_product_id)
);

CREATE TABLE f360.woo_variant_links (
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  variant_id         uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  woo_variation_id   integer NOT NULL CHECK (woo_variation_id > 0),
  last_pushed_stock  integer CHECK (last_pushed_stock >= 0),
  last_pushed_at     timestamptz,
  linked_at          timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, variant_id),
  UNIQUE (target_id, woo_variation_id)
);

CREATE TABLE f360.woo_media_links (
  target_id     uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  media_id      uuid NOT NULL REFERENCES f360.product_media(id) ON DELETE CASCADE,   -- Woo keeps its attachment
  woo_media_id  integer NOT NULL CHECK (woo_media_id > 0),
  linked_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, media_id)
);

-- ── Jobs + append-only steps ────────────────────────────────────────────────
CREATE TABLE f360.sync_jobs (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  product_id         uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  kind               text NOT NULL DEFAULT 'publish' CHECK (kind = 'publish'),
  status             text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'succeeded', 'partial', 'failed')),
  idempotency_key    uuid NOT NULL UNIQUE,
  requested_by       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  requested_by_name  text NOT NULL,
  content_hash       text,
  attempt            integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now(),
  started_at         timestamptz,
  heartbeat_at       timestamptz,
  finished_at        timestamptz,
  error_message      text,
  summary            jsonb
);
CREATE UNIQUE INDEX sync_jobs_one_active ON f360.sync_jobs (target_id, product_id) WHERE status IN ('queued', 'running');
CREATE INDEX sync_jobs_product_idx ON f360.sync_jobs (product_id, created_at DESC);

CREATE TABLE f360.sync_job_steps (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id      uuid NOT NULL REFERENCES f360.sync_jobs(id) ON DELETE RESTRICT,
  step        text NOT NULL,        -- preflight | terms | media | product | variations | stock | verify
  object_ref  text,                 -- e.g. SKU, color code, media id
  action      text NOT NULL,        -- create | update | link | relink | reuse | check | skip | hide | error
  woo_id      integer,
  ok          boolean NOT NULL,
  message     text,
  detail      jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sync_job_steps_job_idx ON f360.sync_job_steps (job_id, id);

CREATE FUNCTION f360.reject_audit_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial de publicación no se puede modificar (%.%)', TG_TABLE_SCHEMA, TG_TABLE_NAME;
END $$;
CREATE TRIGGER sync_job_steps_append_only BEFORE UPDATE OR DELETE ON f360.sync_job_steps
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ── Helpers ─────────────────────────────────────────────────────────────────
-- Content that, when changed after a successful publish, means "Cambios pendientes". Stock is NOT content.
CREATE FUNCTION f360.publish_hash(p_product_id uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT md5(jsonb_build_object(
    'name', p.name, 'code', p.code, 'description', p.description, 'short', p.short_description,
    'regular', p.regular_price, 'sale', p.sale_price, 'category', p.category_key,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name,
                 'media', (SELECT coalesce(jsonb_agg(m.storage_path ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(v.sku || ':' || v.status ORDER BY v.sku), '[]') FROM f360.product_variants v WHERE v.product_id = p.id)
  )::text) FROM f360.products p WHERE p.id = p_product_id
$$;

-- Online available-to-sell for a variant at the target's fulfillment location (P-STOCK: actual sellable stock,
-- no reserve). Isolated so P2.3 reservation/commitment semantics change exactly one place.
CREATE FUNCTION f360.online_ats(p_variant_id uuid, p_location_id uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = p_variant_id AND location_id = p_location_id), 0)
$$;

-- The single active target of this environment (V1). Explicit key when more than one is active.
CREATE FUNCTION f360.resolve_target(p_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $$
DECLARE t f360.sales_targets; n int;
BEGIN
  IF p_key IS NOT NULL THEN
    SELECT * INTO t FROM f360.sales_targets WHERE key = p_key AND active;
  ELSE
    SELECT count(*) INTO n FROM f360.sales_targets WHERE active;
    IF n > 1 THEN RAISE EXCEPTION 'Hay más de una tienda en línea configurada; elige una.'; END IF;
    SELECT * INTO t FROM f360.sales_targets WHERE active;
  END IF;
  IF t.id IS NULL THEN RAISE EXCEPTION 'No hay una tienda en línea configurada para publicar.'; END IF;
  RETURN t;
END $$;

-- A running job whose worker stopped reporting is considered interrupted after 10 minutes.
CREATE FUNCTION f360.expire_stale_jobs(p_product_id uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE f360.sync_jobs SET status = 'failed', finished_at = now(),
    error_message = coalesce(error_message, 'La publicación se interrumpió. Puedes reintentar.')
  WHERE product_id = p_product_id AND status IN ('queued', 'running')
    AND coalesce(heartbeat_at, created_at) < now() - interval '10 minutes'
$$;

CREATE FUNCTION f360.job_json(p_job_id uuid, p_with_steps boolean) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('id', j.id, 'status', j.status, 'requested_by_name', j.requested_by_name,
    'created_at', j.created_at, 'started_at', j.started_at, 'finished_at', j.finished_at, 'attempt', j.attempt,
    'error_message', j.error_message, 'summary', j.summary,
    'steps', CASE WHEN p_with_steps THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('step', s.step, 'object_ref', s.object_ref,
               'action', s.action, 'woo_id', s.woo_id, 'ok', s.ok, 'message', s.message, 'at', s.created_at) ORDER BY s.id), '[]')
             FROM f360.sync_job_steps s WHERE s.job_id = j.id) END)
  FROM f360.sync_jobs j WHERE j.id = p_job_id
$$;

-- ── User RPCs ───────────────────────────────────────────────────────────────
-- Owner asks to publish/sync. Readiness + category mapping are checked here; the worker re-checks everything.
CREATE FUNCTION public.f360_request_publish(p_product_id uuid, p_idempotency_key uuid, p_target_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; j f360.sync_jobs; ready jsonb; cat text;
BEGIN
  r := f360.require_role('owner');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la clave de la solicitud.'; END IF;
  SELECT * INTO j FROM f360.sync_jobs WHERE idempotency_key = p_idempotency_key;
  IF j.id IS NOT NULL THEN
    IF j.product_id <> p_product_id THEN RAISE EXCEPTION 'Clave de solicitud repetida.'; END IF;
    RETURN f360.job_json(j.id, false) || jsonb_build_object('replayed', true);
  END IF;
  t := f360.resolve_target(p_target_key);
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  ready := f360.product_readiness(p_product_id);
  IF NOT (ready->>'ready')::boolean THEN RAISE EXCEPTION 'El producto todavía no está listo para publicar.'; END IF;
  SELECT p.category_key INTO cat FROM f360.products p WHERE p.id = p_product_id;
  IF NOT EXISTS (SELECT 1 FROM f360.woo_category_links WHERE target_id = t.id AND category_key = cat) THEN
    RAISE EXCEPTION 'La categoría de este producto todavía no está vinculada con la tienda en línea. Pídele a Mario que la vincule.';
  END IF;
  PERFORM f360.expire_stale_jobs(p_product_id);
  SELECT * INTO j FROM f360.sync_jobs WHERE product_id = p_product_id AND target_id = t.id AND status IN ('queued', 'running');
  IF j.id IS NOT NULL THEN RETURN f360.job_json(j.id, false) || jsonb_build_object('already_active', true); END IF;
  INSERT INTO f360.sync_jobs (target_id, product_id, idempotency_key, requested_by, requested_by_name, content_hash)
    VALUES (t.id, p_product_id, p_idempotency_key, r.auth_user_id, r.display_name, f360.publish_hash(p_product_id))
    RETURNING * INTO j;
  RETURN f360.job_json(j.id, false);
END $$;

-- What Carolina sees: Borrador / Listo / Publicando / Publicado / Cambios pendientes / Error.
CREATE FUNCTION public.f360_publication_status(p_product_id uuid, p_target_key text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; l f360.woo_product_links; active_job uuid; last_job f360.sync_jobs;
  ready boolean; state text; cur_hash text;
BEGIN
  r := f360.require_role('viewer');
  BEGIN t := f360.resolve_target(p_target_key); EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('state', 'sin_tienda', 'message', SQLERRM, 'can_publish', false, 'jobs', '[]'::jsonb);
  END;
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  ready := (f360.product_readiness(p_product_id)->>'ready')::boolean;
  cur_hash := f360.publish_hash(p_product_id);
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  SELECT id INTO active_job FROM f360.sync_jobs WHERE target_id = t.id AND product_id = p_product_id AND status IN ('queued', 'running')
    AND coalesce(heartbeat_at, created_at) >= now() - interval '10 minutes';
  SELECT * INTO last_job FROM f360.sync_jobs WHERE target_id = t.id AND product_id = p_product_id AND status NOT IN ('queued', 'running')
    ORDER BY created_at DESC LIMIT 1;
  state := CASE
    WHEN active_job IS NOT NULL THEN 'publicando'
    WHEN last_job.status IN ('failed', 'partial') THEN 'error'
    WHEN l.last_success_at IS NOT NULL AND l.published_hash = cur_hash THEN 'publicado'
    WHEN l.last_success_at IS NOT NULL THEN 'cambios'
    WHEN ready THEN 'listo'
    ELSE 'borrador' END;
  RETURN jsonb_build_object(
    'state', state, 'ready', ready,
    'can_publish', r.role = 'owner' AND ready AND active_job IS NULL,
    'target', jsonb_build_object('key', t.key, 'name', t.name, 'base_url', t.base_url, 'is_production', t.is_production),
    'woo_product_id', l.woo_product_id, 'woo_status', l.woo_status, 'last_success_at', l.last_success_at,
    'variations_linked', (SELECT count(*) FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                          WHERE vl.target_id = t.id AND v.product_id = p_product_id),
    'active_job', CASE WHEN active_job IS NULL THEN NULL ELSE f360.job_json(active_job, true) END,
    'jobs', (SELECT coalesce(jsonb_agg(f360.job_json(j.id, j.id = last_job.id) ORDER BY j.created_at DESC), '[]')
             FROM (SELECT id, created_at FROM f360.sync_jobs WHERE target_id = t.id AND product_id = p_product_id
                   ORDER BY created_at DESC LIMIT 10) j));
END $$;

-- ── Worker RPCs (service_role only; called by the f360-woo-publish function) ─
-- Claims a job for execution after re-verifying the requester is still an owner. Locks the codes (DW9):
-- from here on SKUs are sent to Woo, so they must never change. Returns the full publish snapshot.
CREATE FUNCTION public.f360_pub_claim(p_job_id uuid, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE j f360.sync_jobs; t f360.sales_targets; p f360.products; cat f360.woo_category_links;
BEGIN
  SELECT * INTO j FROM f360.sync_jobs WHERE id = p_job_id FOR UPDATE;
  IF j.id IS NULL THEN RAISE EXCEPTION 'Publicación no encontrada.'; END IF;
  IF j.requested_by IS DISTINCT FROM p_caller THEN RAISE EXCEPTION 'Esta publicación la pidió otra persona.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede publicar.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF j.status = 'running' AND coalesce(j.heartbeat_at, j.started_at) >= now() - interval '10 minutes' THEN
    RAISE EXCEPTION 'Esta publicación ya está en curso.';
  END IF;
  IF j.status NOT IN ('queued', 'running') THEN RAISE EXCEPTION 'Esta publicación ya terminó.'; END IF;
  IF NOT (f360.product_readiness(j.product_id)->>'ready')::boolean THEN RAISE EXCEPTION 'El producto todavía no está listo para publicar.'; END IF;

  UPDATE f360.products SET codes_locked_at = now() WHERE id = j.product_id AND codes_locked_at IS NULL;
  UPDATE f360.sync_jobs SET status = 'running', started_at = coalesce(started_at, now()), heartbeat_at = now(),
    attempt = attempt + 1, content_hash = f360.publish_hash(j.product_id) WHERE id = j.id RETURNING * INTO j;
  SELECT * INTO t FROM f360.sales_targets WHERE id = j.target_id;
  SELECT * INTO p FROM f360.products WHERE id = j.product_id;
  SELECT * INTO cat FROM f360.woo_category_links WHERE target_id = t.id AND category_key = p.category_key;

  RETURN jsonb_build_object(
    'job', jsonb_build_object('id', j.id, 'attempt', j.attempt, 'requested_by_name', j.requested_by_name, 'content_hash', j.content_hash),
    'target', jsonb_build_object('id', t.id, 'key', t.key, 'base_url', t.base_url, 'is_production', t.is_production,
               'fulfillment_location_id', t.fulfillment_location_id),
    'product', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'slug', p.slug, 'description', p.description,
               'short_description', p.short_description, 'regular_price', p.regular_price, 'sale_price', p.sale_price,
               'category_key', p.category_key,
               'woo_category', CASE WHEN cat.woo_term_id IS NULL THEN NULL ELSE jsonb_build_object('id', cat.woo_term_id, 'slug', cat.woo_slug) END,
               'woo_product_id', (SELECT woo_product_id FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p.id)),
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'hex', c.hex,
                 'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path, 'alt', m.alt,
                             'woo_media_id', (SELECT woo_media_id FROM f360.woo_media_links ml WHERE ml.target_id = t.id AND ml.media_id = m.id))
                           ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'color_id', v.color_id, 'size', v.size_label, 'sku', v.sku,
                   'status', v.status, 'ats', f360.online_ats(v.id, t.fulfillment_location_id),
                   'woo_variation_id', vl.woo_variation_id, 'last_pushed_stock', vl.last_pushed_stock)
                 ORDER BY c.sort, c.created_at, s.sort), '[]')
                 FROM f360.product_variants v JOIN f360.product_colors c ON c.id = v.color_id
                 JOIN f360.product_sizes s ON s.product_id = v.product_id AND s.label = v.size_label
                 LEFT JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = v.id
                 WHERE v.product_id = p.id));
END $$;

CREATE FUNCTION f360.running_job(p_job_id uuid) RETURNS f360.sync_jobs LANGUAGE plpgsql AS $$
DECLARE j f360.sync_jobs;
BEGIN
  SELECT * INTO j FROM f360.sync_jobs WHERE id = p_job_id;
  IF j.id IS NULL OR j.status <> 'running' THEN RAISE EXCEPTION 'La publicación no está en curso.'; END IF;
  UPDATE f360.sync_jobs SET heartbeat_at = now() WHERE id = p_job_id;
  RETURN j;
END $$;

CREATE FUNCTION public.f360_pub_step(p_job_id uuid, p_step text, p_object_ref text, p_action text, p_woo_id integer,
  p_ok boolean, p_message text, p_detail jsonb DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.running_job(p_job_id);
  INSERT INTO f360.sync_job_steps (job_id, step, object_ref, action, woo_id, ok, message, detail)
    VALUES (p_job_id, p_step, p_object_ref, p_action, p_woo_id, p_ok, left(p_message, 1000), p_detail);
END $$;

-- Stores a Woo id for an F360 object of THIS job's product (kind: product | variant | media).
CREATE FUNCTION public.f360_pub_link(p_job_id uuid, p_kind text, p_f360_id uuid, p_woo_id integer, p_extra jsonb DEFAULT '{}') RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE j f360.sync_jobs;
BEGIN
  j := f360.running_job(p_job_id);
  IF p_woo_id IS NULL OR p_woo_id <= 0 THEN RAISE EXCEPTION 'Id de Woo no válido.'; END IF;
  IF p_kind = 'product' THEN
    IF p_f360_id <> j.product_id THEN RAISE EXCEPTION 'Producto ajeno a la publicación.'; END IF;
    INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id, woo_status, last_job_id)
      VALUES (j.target_id, j.product_id, p_woo_id, p_extra->>'status', j.id)
      ON CONFLICT (target_id, product_id) DO UPDATE SET woo_product_id = EXCLUDED.woo_product_id,
        woo_status = coalesce(EXCLUDED.woo_status, f360.woo_product_links.woo_status), last_job_id = j.id;
  ELSIF p_kind = 'variant' THEN
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = p_f360_id AND product_id = j.product_id) THEN
      RAISE EXCEPTION 'Variante ajena a la publicación.';
    END IF;
    INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, last_pushed_stock, last_pushed_at)
      VALUES (j.target_id, p_f360_id, p_woo_id, (p_extra->>'stock')::int, CASE WHEN p_extra ? 'stock' THEN now() END)
      ON CONFLICT (target_id, variant_id) DO UPDATE SET woo_variation_id = EXCLUDED.woo_variation_id,
        last_pushed_stock = coalesce(EXCLUDED.last_pushed_stock, f360.woo_variant_links.last_pushed_stock),
        last_pushed_at = coalesce(EXCLUDED.last_pushed_at, f360.woo_variant_links.last_pushed_at);
  ELSIF p_kind = 'media' THEN
    IF NOT EXISTS (SELECT 1 FROM f360.product_media WHERE id = p_f360_id AND product_id = j.product_id) THEN
      RAISE EXCEPTION 'Foto ajena a la publicación.';
    END IF;
    INSERT INTO f360.woo_media_links (target_id, media_id, woo_media_id) VALUES (j.target_id, p_f360_id, p_woo_id)
      ON CONFLICT (target_id, media_id) DO UPDATE SET woo_media_id = EXCLUDED.woo_media_id;
  ELSE
    RAISE EXCEPTION 'Tipo de vínculo no válido.';
  END IF;
END $$;

-- Ends a job. Only 'succeeded' (read-back verified by the worker) records the published hash.
CREATE FUNCTION public.f360_pub_finish(p_job_id uuid, p_status text, p_error text, p_summary jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE j f360.sync_jobs;
BEGIN
  IF p_status NOT IN ('succeeded', 'partial', 'failed') THEN RAISE EXCEPTION 'Estado final no válido.'; END IF;
  j := f360.running_job(p_job_id);
  UPDATE f360.sync_jobs SET status = p_status, finished_at = now(), error_message = CASE WHEN p_status = 'succeeded' THEN NULL ELSE left(p_error, 1000) END,
    summary = p_summary WHERE id = j.id;
  IF p_status = 'succeeded' THEN
    UPDATE f360.woo_product_links SET published_hash = j.content_hash, last_success_at = now(), last_job_id = j.id,
      woo_status = coalesce(p_summary->>'woo_status', woo_status)
      WHERE target_id = j.target_id AND product_id = j.product_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'No se puede marcar como publicado sin producto en la tienda.'; END IF;
  END IF;
  RETURN f360.job_json(j.id, false);
END $$;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON f360.sales_targets, f360.woo_category_links, f360.woo_product_links, f360.woo_variant_links,
  f360.woo_media_links, f360.sync_jobs, f360.sync_job_steps FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.f360_request_publish(uuid, uuid, text), public.f360_publication_status(uuid, text),
  public.f360_pub_claim(uuid, uuid), public.f360_pub_step(uuid, text, text, text, integer, boolean, text, jsonb),
  public.f360_pub_link(uuid, text, uuid, integer, jsonb), public.f360_pub_finish(uuid, text, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_request_publish(uuid, uuid, text), public.f360_publication_status(uuid, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_pub_claim(uuid, uuid), public.f360_pub_step(uuid, text, text, text, integer, boolean, text, jsonb),
  public.f360_pub_link(uuid, text, uuid, integer, jsonb), public.f360_pub_finish(uuid, text, text, jsonb)
  TO service_role;
