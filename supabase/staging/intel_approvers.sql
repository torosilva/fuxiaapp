-- STAGING data · who approves what (Mario 2026-10-11, Centro de Inteligencia decisions):
--   fx_rate = Mario ("la tasa mensual … requiere aprobación de Mario"); budget = Mario ("Mario define y aprueba los presupuestos");
--   close = Mario or Carolina ("Mario o Carolina deben aprobar el cierre").
-- Plus Mario's starting figure of 2026-10-11 (1 COP = 0.0057 MXN, read on Google) as a MANUAL observation: kept for traceability,
-- never averaged into a monthly rate. Idempotent. Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/staging/intel_approvers.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE display_name = 'Mario' AND role = 'owner');
  caro uuid := (SELECT auth_user_id FROM f360.user_roles WHERE display_name = 'Carolina' AND role = 'owner');
BEGIN
  IF mario IS NULL OR caro IS NULL THEN RAISE EXCEPTION 'ABORT: Mario o Carolina no existen como dueños en este ambiente'; END IF;
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name, note) VALUES
    ('fx_rate', mario, 'Mario', 'Mario (decisión 2026-10-11)', 'Aprueba la tasa mensual propuesta automáticamente'),
    ('budget',  mario, 'Mario', 'Mario (decisión 2026-10-11)', 'Define y aprueba presupuestos y metas'),
    ('close',   mario, 'Mario', 'Mario (decisión 2026-10-11)', 'Aprueba el cierre mensual'),
    ('close',   caro,  'Carolina', 'Mario (decisión 2026-10-11)', 'Aprueba el cierre mensual')
  ON CONFLICT DO NOTHING;
  IF NOT EXISTS (SELECT 1 FROM f360.fx_observations WHERE role = 'manual' AND currency = 'COP' AND obs_date = '2026-10-11') THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
    PERFORM public.f360_fx_observation_manual('2026-10-11', 'COP', 0.0057, 'Mario (consulta en Google)',
      'Chat con Claude 2026-10-11: "1 Peso colombiano es igual a 0.0057 Peso mexicano"', 'Cifra de arranque; no se promedia.');
  END IF;
END $$;
COMMIT;
