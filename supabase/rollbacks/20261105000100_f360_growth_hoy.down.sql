-- Rollback of 20261105000100_f360_growth_hoy: removes the f360-ga4 schedule, the GA4 funnel table and the Hoy / recuperar functions,
-- and restores growth_source_tick as in 20261104000100. Loses the captured GA4 funnel history (it can be re-read from GA4).
BEGIN;
SELECT cron.unschedule('f360-ga4') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-ga4');
DROP FUNCTION public.f360_growth_recuperar(text);
DROP FUNCTION public.f360_growth_outreach_mark(text, text, text, text);
DROP TABLE f360.growth_outreach;
DROP FUNCTION public.f360_growth_hoy();
DROP FUNCTION public.f360_ga4_import(date, jsonb);
DROP TABLE f360.ga4_funnel;
CREATE OR REPLACE FUNCTION f360.growth_source_tick(p_function text, p_body jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_function NOT IN ('f360-instagram', 'f360-clarity') THEN RETURN; END IF;
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/' || p_function) INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ ('/functions/v1/' || p_function || '$') THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := p_body, timeout_milliseconds := 55000);
END $$;
UPDATE f360.measurement_sources SET config_status = 'NOT_CONFIGURED', notes = NULL WHERE key = 'ga4';
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261105000100';
COMMIT;
