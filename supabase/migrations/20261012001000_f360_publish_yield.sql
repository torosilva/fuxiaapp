-- Fuxia 360 · a publish job can hand its turn back to the queue (Mario 2026-10-07: "si ajústalo").
-- The Edge runtime stops every invocation at 150 s; a model with many colours and photos (Cucarron, Paula, Sueco cucarrón) needs
-- more than that, so its job died mid-way and sat "running" for 10 minutes before anyone could resume it. Now the publisher stops
-- starting store calls before the limit, calls f360_pub_yield (job back to QUEUED, same job, nothing reset) and calls itself again;
-- the next invocation claims the same job first (oldest in the queue) and continues where it stopped: what the store already has is
-- found by link / SKU / photo name, never duplicated.
-- Rollback: supabase/rollbacks/20261012001000_f360_publish_yield.down.sql
CREATE FUNCTION public.f360_pub_yield(p_job_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE j f360.sync_jobs;
BEGIN
  j := f360.running_job(p_job_id);
  UPDATE f360.sync_jobs SET status = 'queued', heartbeat_at = NULL WHERE id = j.id;
END $$;
REVOKE ALL ON FUNCTION public.f360_pub_yield(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pub_yield(uuid) TO service_role;
