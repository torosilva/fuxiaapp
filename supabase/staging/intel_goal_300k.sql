-- STAGING data · Mario 2026-10-11: "Registrar explícitamente la meta de $300,000 MXN mensuales de ecommerce México."
-- Through the audited RPC as Mario (scope budget). Effective from October 2026. Idempotent.
BEGIN;
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid'); r jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM f360_board.goals WHERE goal_key = 'ecommerce_mx_mensual') THEN RETURN; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_board_goal_set('ecommerce_mx_mensual', 'Ecommerce México (tienda en línea)', 'MX', 'online', 300000, '2026-10-01',
         'Mario 2026-10-11: meta de $300,000 MXN mensuales de ecommerce México (Centro de Inteligencia, decisión 2).');
  IF r->>'ok' <> 'true' THEN RAISE EXCEPTION 'ABORT: %', r; END IF;
END $$;
COMMIT;
