-- Fuxia 360 · pase C2 — "Publicar en vivo" / "Ocultar de la tienda" (Mario 2026-10-06). Same as migration 20261012000300. Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · "Publicar en vivo" / "Ocultar de la tienda" (Mario 2026-10-06): the owner makes a Fuxia 360 product visible or
-- hidden in its store from the product page. Only products Fuxia 360 published (woo_product_links); only status publish/draft;
-- owner only (checked here from the caller id the publisher verified with Supabase Auth); every change audited.
-- f360_publication_status also reports how many OLD (legacy) store products of the model exist, so the admin warns before going live.
-- Rollback: supabase/rollbacks/20261012000300_f360_store_visibility.down.sql

CREATE TABLE f360.product_visibility_changes (
  id              bigserial PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  product_id      uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  woo_product_id  integer NOT NULL,
  from_status     text,
  to_status       text NOT NULL CHECK (to_status IN ('publish', 'draft')),
  ok              boolean NOT NULL,
  message         text,
  by_user         uuid NOT NULL,
  by_name         text NOT NULL,
  at              timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER product_visibility_changes_append_only BEFORE UPDATE OR DELETE ON f360.product_visibility_changes FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
ALTER TABLE f360.product_visibility_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.product_visibility_changes FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_pub_visibility_begin(p_product_id uuid, p_target_key text, p_status text, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; l f360.woo_product_links;
BEGIN
  IF p_status NOT IN ('publish', 'draft') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede mostrar u ocultar productos en la tienda.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  t := f360.catalog_target(p_target_key);
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  IF l.woo_product_id IS NULL THEN RAISE EXCEPTION 'Primero publícalo como borrador.'; END IF;
  RETURN jsonb_build_object('woo_product_id', l.woo_product_id, 'woo_status', l.woo_status, 'target', jsonb_build_object('key', t.key, 'base_url', t.base_url));
END $$;

CREATE FUNCTION public.f360_pub_visibility_finish(p_product_id uuid, p_target_key text, p_status text, p_caller uuid, p_ok boolean,
  p_woo_status text, p_message text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; l f360.woo_product_links; who text;
BEGIN
  SELECT display_name INTO who FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner';
  IF who IS NULL THEN RAISE EXCEPTION 'Solo una dueña puede mostrar u ocultar productos en la tienda.' USING ERRCODE = 'insufficient_privilege'; END IF;
  t := f360.catalog_target(p_target_key);
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id FOR UPDATE;
  IF l.woo_product_id IS NULL THEN RAISE EXCEPTION 'Producto no publicado.'; END IF;
  INSERT INTO f360.product_visibility_changes (target_id, product_id, woo_product_id, from_status, to_status, ok, message, by_user, by_name)
  VALUES (t.id, p_product_id, l.woo_product_id, l.woo_status, p_status, coalesce(p_ok, false), left(p_message, 500), p_caller, who);
  IF p_ok AND p_woo_status IN ('publish', 'draft', 'private', 'pending') THEN
    UPDATE f360.woo_product_links SET woo_status = p_woo_status WHERE target_id = t.id AND product_id = p_product_id;
  END IF;
  RETURN jsonb_build_object('ok', coalesce(p_ok, false), 'woo_status', CASE WHEN p_ok THEN p_woo_status ELSE l.woo_status END);
END $$;

REVOKE ALL ON FUNCTION public.f360_pub_visibility_begin(uuid, text, text, uuid), public.f360_pub_visibility_finish(uuid, text, text, uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pub_visibility_begin(uuid, text, text, uuid), public.f360_pub_visibility_finish(uuid, text, text, uuid, boolean, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.f360_publication_status(p_product_id uuid, p_target_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
    ORDER BY seq DESC LIMIT 1;
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
    'legacy_products', (SELECT count(DISTINCT m.woo_product_id) FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
                        WHERE v.product_id = p_product_id AND m.status = 'confirmado' AND m.woo_product_id IS DISTINCT FROM l.woo_product_id),
    'variations_linked', (SELECT count(*) FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                          WHERE vl.target_id = t.id AND v.product_id = p_product_id),
    'active_job', CASE WHEN active_job IS NULL THEN NULL ELSE f360.job_json(active_job, true) END,
    'jobs', (SELECT coalesce(jsonb_agg(f360.job_json(j.id, j.id = last_job.id) ORDER BY j.seq DESC), '[]')
             FROM (SELECT id, seq FROM f360.sync_jobs WHERE target_id = t.id AND product_id = p_product_id
                   ORDER BY seq DESC LIMIT 10) j));
END $function$;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012000300', 'f360_store_visibility', '{}');
COMMIT;
