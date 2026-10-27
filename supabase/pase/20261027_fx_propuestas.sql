-- Fuxia 360 · PRODUCCIÓN · I5 paso 1c: propone el promedio mensual oficial de cada mes CERRADO desde mayo 2026 (solo propuestas;
-- aprobar es de Mario, alcance fx_rate). Requiere que el relleno ya haya llegado. Idempotente.
BEGIN;
DO $$
DECLARE m date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.fx_observations WHERE role = 'primary' AND obs_date < '2026-06-01') THEN
    RAISE EXCEPTION 'ABORT: el historial todavía no llega; corre 20261027_fx_relleno.sql y espera'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  FOR m IN SELECT generate_series('2026-05-01'::date, date_trunc('month', now() AT TIME ZONE 'America/Mexico_City')::date - 1, interval '1 month')::date LOOP
    PERFORM public.f360_fx_month_propose(m);
  END LOOP;
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE status = 'approved') THEN RAISE EXCEPTION 'POST: nada debe quedar aprobado'; END IF;
END $$;
COMMIT;
