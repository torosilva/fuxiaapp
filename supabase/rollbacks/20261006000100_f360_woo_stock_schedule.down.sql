-- Rollback of 20261006000100_f360_woo_stock_schedule.sql. pg_net stays installed (harmless; other features may use it).
-- The Vault entries 'f360_sync_url' / 'f360_sync_secret' are environment config, removed separately if wanted.
SELECT cron.unschedule('f360-woo-stock-push') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-woo-stock-push');
DROP FUNCTION IF EXISTS f360.woo_sync_tick();
