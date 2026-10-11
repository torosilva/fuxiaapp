-- Rollback of 20261024000100_f360_fx_daily (I0). Monthly rates already proposed/approved in f360.fx_rates are KEPT (they are
-- documented and auditable on their own); the daily history is dropped only if empty unless F360_FX_DROP_HISTORY is set.
-- Run inside one transaction with psql (no BEGIN/COMMIT here).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.fx_observations) AND coalesce(current_setting('f360.fx_drop_history', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'ABORT: f360.fx_observations tiene historial. Respáldalo y corre con SET f360.fx_drop_history = ''yes''.';
  END IF;
END $$;
SELECT cron.unschedule('f360-fx-rates') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-fx-rates');
DROP FUNCTION f360.fx_daily_tick();
DROP FUNCTION public.f360_fx_status();
DROP FUNCTION f360.fx_rate_for_report(text, date);
DROP FUNCTION public.f360_fx_month_propose(date);
DROP FUNCTION public.f360_fx_observation_manual(date, text, numeric, text, text, text);
DROP FUNCTION public.f360_fx_observations_record(date, date, jsonb);
DROP FUNCTION f360.fx_system_proposer();
DROP VIEW f360.fx_daily;
DROP TABLE f360.fx_observations;
DROP FUNCTION f360.fx_observations_immutable();
DROP FUNCTION f360.can_approve(text, uuid);
DROP TABLE f360.approval_scopes;

CREATE OR REPLACE FUNCTION public.f360_measurement_run_failed(p_source_key text, p_from date, p_to date, p_error text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_source_key NOT IN ('meta_ads', 'google_ads', 'ga4') THEN RAISE EXCEPTION 'Fuente no válida.'; END IF;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, error)
    VALUES (p_source_key, clock_timestamp(), false, p_from, p_to, left(coalesce(nullif(btrim(p_error), ''), 'error sin detalle'), 500));
END $$;

CREATE OR REPLACE FUNCTION public.f360_fx_rate_approve(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE id = p_id AND status = 'proposed'
               AND (source_reference IS NULL OR source_retrieved_on IS NULL OR rate_method IS NULL)) THEN
    RAISE EXCEPTION 'Este tipo de cambio no tiene la fuente documentada (referencia, fecha de consulta, método): anúlalo y propón uno documentado.';
  END IF;
  UPDATE f360.fx_rates SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = clock_timestamp()
    WHERE id = p_id AND status = 'proposed';
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o no está propuesto.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved');
END $$;

DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000100';
