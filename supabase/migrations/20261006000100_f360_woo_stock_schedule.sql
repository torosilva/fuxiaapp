-- P2.3B · Automatic stock push Fuxia 360 → Woo: every minute, pg_cron calls the f360-woo-sync Edge Function (action "push").
-- No secret or URL lives in this file: the tick reads both from Supabase Vault ('f360_sync_url', 'f360_sync_secret').
-- An environment without those two Vault entries (e.g. production today) schedules a tick that does NOTHING.
-- The push itself is idempotent (the DB queue decides what to send; f360_sync_claim_stock / f360_sync_stock_result).
-- Rollback: supabase/rollbacks/20261006000100_f360_woo_stock_schedule.down.sql
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION f360.woo_sync_tick()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;   -- not configured in this environment
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"push"}'::jsonb, timeout_milliseconds := 55000);
END $$;
REVOKE ALL ON FUNCTION f360.woo_sync_tick() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION f360.woo_sync_tick() IS 'pg_cron tick (every minute): POST f360-woo-sync {action:push}. URL + Bearer from Vault; no-op without them.';

SELECT cron.schedule('f360-woo-stock-push', '* * * * *', 'SELECT f360.woo_sync_tick()');
