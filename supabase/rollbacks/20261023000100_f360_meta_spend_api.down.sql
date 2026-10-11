-- Rollback of 20261023000100_f360_meta_spend_api.sql. Stops the daily read and removes the API entry points.
-- Spend already imported stays (append-only history); to hide it, void its imports with public.f360_marketing_spend_void (owner, with reason).
-- meta_ads back to NOT_CONFIGURED so the cockpit says "sin fuente" instead of STALE.
SELECT cron.unschedule('f360-meta-spend') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-meta-spend');
DROP FUNCTION IF EXISTS f360.meta_spend_tick();
DROP FUNCTION IF EXISTS public.f360_measurement_run_failed(text, date, date, text);
DROP FUNCTION IF EXISTS public.f360_marketing_spend_api_import(text, text, text, date, date, jsonb);
UPDATE f360.measurement_sources SET config_status = 'NOT_CONFIGURED', updated_by_name = 'rollback 20261023000100', updated_at = now() WHERE key = 'meta_ads';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261023000100';
