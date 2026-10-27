-- Rollback of 20261104000100_f360_growth_instagram_clarity: removes the 3 schedules, Instagram and Clarity tables / functions, the two
-- measurement sources (and their runs), and restores f360_measurement_run_failed and the sources CHECK as in 20261024000100.
-- Loses the captured Instagram / Clarity history (Clarity cannot be re-read: export ~/fuxia360-respaldos/clarity or the table first).
-- Teardown once applied: run only with Mario's OK. Roll back 20261104000200 first if it is applied.
BEGIN;
SELECT cron.unschedule(j) FROM unnest(ARRAY['f360-instagram', 'f360-instagram-stories', 'f360-clarity']) j WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = j);
DROP FUNCTION f360.growth_source_tick(text, jsonb);
DROP FUNCTION public.f360_clarity_import(date, int, text, jsonb);
DROP FUNCTION public.f360_growth_instagram(date, date);
DROP FUNCTION public.f360_instagram_import(text, date, date, jsonb, jsonb);
DROP FUNCTION f360.is_instagram_organic(text, text, text, text);
DROP FUNCTION f360.ig_int(jsonb, text);
DROP TABLE f360.clarity_snapshots, f360.ig_media_metrics, f360.ig_media, f360.ig_account_daily;
CREATE OR REPLACE FUNCTION public.f360_measurement_run_failed(p_source_key text, p_from date, p_to date, p_error text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_source_key NOT IN ('meta_ads', 'google_ads', 'ga4', 'fx_rates') THEN RAISE EXCEPTION 'Fuente no válida.'; END IF;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, error)
    VALUES (p_source_key, clock_timestamp(), false, p_from, p_to, left(coalesce(nullif(btrim(p_error), ''), 'error sin detalle'), 500));
END $$;
DELETE FROM f360.measurement_runs WHERE source_key IN ('instagram', 'clarity');
DELETE FROM f360.measurement_sources WHERE key IN ('instagram', 'clarity');
ALTER TABLE f360.measurement_sources DROP CONSTRAINT measurement_sources_key_check;
ALTER TABLE f360.measurement_sources ADD CONSTRAINT measurement_sources_key_check CHECK (key IN ('woocommerce', 'order_reconciliation', 'ga4',
  'meta_ads', 'google_ads', 'marketing_spend', 'store_sales', 'fx_rates'));
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261104000100';
COMMIT;
