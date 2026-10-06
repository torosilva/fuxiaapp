-- Fuxia 360 · publishing queue that does not depend on the browser (Mario 2026-10-06: "me salí de la pantalla y se perdió").
-- The publisher Edge Function processes the queue itself: one job per invocation, then it calls itself for the next one,
-- until the queue is empty. These two functions give it the next job and give the admin an honest progress count.
--   · f360_pub_next_job(target): service_role only. Oldest QUEUED job of that store's catalog, or a RUNNING one whose worker
--     stopped reporting for 10 minutes (it is resumed; the publisher converges, never duplicates). Returns the requester, who
--     pub_claim re-checks as owner.
--   · f360_pub_queue_status(target): anyone with Fuxia 360 access; counts per status (+ the model being published now).
-- Rollback: supabase/rollbacks/20261012000500_f360_publish_queue_worker.down.sql
CREATE FUNCTION public.f360_pub_next_job(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; j f360.sync_jobs;
BEGIN
  t := f360.catalog_target(p_target_key);
  SELECT * INTO j FROM f360.sync_jobs
  WHERE target_id = t.id AND (status = 'queued' OR (status = 'running' AND coalesce(heartbeat_at, started_at, created_at) < now() - interval '10 minutes'))
  ORDER BY created_at, seq LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF j.id IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('job_id', j.id, 'requested_by', j.requested_by, 'product_id', j.product_id);
END $$;

CREATE FUNCTION public.f360_pub_queue_status(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer'); t f360.sales_targets;
BEGIN
  t := f360.catalog_target(p_target_key);
  RETURN jsonb_build_object(
    'queued', (SELECT count(*) FROM f360.sync_jobs WHERE target_id = t.id AND status = 'queued'),
    'running', (SELECT count(*) FROM f360.sync_jobs WHERE target_id = t.id AND status = 'running'),
    'succeeded_today', (SELECT count(*) FROM f360.sync_jobs WHERE target_id = t.id AND status = 'succeeded' AND finished_at > now() - interval '24 hours'),
    'failed_today', (SELECT count(*) FROM f360.sync_jobs WHERE target_id = t.id AND status IN ('failed', 'partial') AND finished_at > now() - interval '24 hours'),
    'now', (SELECT string_agg(p.name, ', ') FROM f360.sync_jobs j JOIN f360.products p ON p.id = j.product_id WHERE j.target_id = t.id AND j.status = 'running'),
    'published', (SELECT count(*) FROM f360.woo_product_links WHERE target_id = t.id),
    'live', (SELECT count(*) FROM f360.woo_product_links WHERE target_id = t.id AND woo_status = 'publish'));
END $$;

REVOKE ALL ON FUNCTION public.f360_pub_next_job(text), public.f360_pub_queue_status(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pub_next_job(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_pub_queue_status(text) TO authenticated;
