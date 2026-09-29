-- Fuxia 360 P2.2b — deterministic job order. "Latest job" was chosen by created_at, which ties when two jobs are
-- created in the same transaction/timestamp. A monotonic identity column makes the order exact.
-- Rollback: supabase/rollbacks/20260927010100_f360_p22_job_order.down.sql

ALTER TABLE f360.sync_jobs ADD COLUMN seq bigint GENERATED ALWAYS AS IDENTITY;
CREATE INDEX sync_jobs_product_seq_idx ON f360.sync_jobs (product_id, seq DESC);

CREATE OR REPLACE FUNCTION public.f360_publication_status(p_product_id uuid, p_target_key text DEFAULT NULL) RETURNS jsonb
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
    'variations_linked', (SELECT count(*) FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                          WHERE vl.target_id = t.id AND v.product_id = p_product_id),
    'active_job', CASE WHEN active_job IS NULL THEN NULL ELSE f360.job_json(active_job, true) END,
    'jobs', (SELECT coalesce(jsonb_agg(f360.job_json(j.id, j.id = last_job.id) ORDER BY j.seq DESC), '[]')
             FROM (SELECT id, seq FROM f360.sync_jobs WHERE target_id = t.id AND product_id = p_product_id
                   ORDER BY seq DESC LIMIT 10) j));
END $$;
