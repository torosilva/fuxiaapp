-- STAGING data · after intel_fx_backfill.sql: propose the monthly average for every CLOSED month since May 2026 that has no live rate
-- (proposals only — approval stays with Mario). Waits up to ~60 s for the backfill to land. Idempotent.
BEGIN;
DO $$
DECLARE m date; i int := 0;
BEGIN
  WHILE NOT EXISTS (SELECT 1 FROM f360.fx_observations WHERE role = 'primary' AND obs_date < '2026-06-01') AND i < 12 LOOP PERFORM pg_sleep(5); i := i + 1; END LOOP;
  IF NOT EXISTS (SELECT 1 FROM f360.fx_observations WHERE role = 'primary') THEN RAISE EXCEPTION 'ABORT: el historial todavía no llega; corre intel_fx_backfill.sql y espera'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  FOR m IN SELECT generate_series('2026-05-01'::date, date_trunc('month', now() AT TIME ZONE 'America/Mexico_City')::date - 1, interval '1 month')::date LOOP
    PERFORM public.f360_fx_month_propose(m);
  END LOOP;
END $$;
COMMIT;
