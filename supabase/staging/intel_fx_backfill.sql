-- STAGING data · reload the official FX history after a staging refresh (f360.fx_observations starts empty). Idempotent:
-- the function records with ON CONFLICT DO NOTHING. Asynchronous (pg_net): the POST runs right after COMMIT; give it ~30 s,
-- then run supabase/staging/intel_fx_propose.sql. Uses the same Vault secrets as the daily cron (f360_sync_url / f360_sync_secret).
BEGIN;
DO $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-fx-rates') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-fx-rates$' OR v_url !~ 'faltxpkaicwpnlqaxrdu' THEN
    RAISE EXCEPTION 'ABORT: no es staging o faltan los secretos de Vault';
  END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"backfill","from":"2026-05-01"}'::jsonb, timeout_milliseconds := 120000);
END $$;
COMMIT;
