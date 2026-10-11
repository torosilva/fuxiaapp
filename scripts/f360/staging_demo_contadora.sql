-- STAGING ONLY · demo "Contadora" for the I2 Cierre contable E2E (Mario 2026-10-11 via coordinator).
-- Prerequisite: the auth user contadora.demo@staging.invalid exists (created with the staging Auth admin API, email_confirm
-- true; its password lives only in ~/.fuxia-staging.env as STAGING_DEMO_CONTADORA_PASSWORD). This script only gives that
-- account its Fuxia 360 role (viewer) and the limited finance-preparer capability, in one transaction. Idempotent: re-run it
-- after a production → staging copy. Refuses to run anywhere that is not the staging project.
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f scripts/f360/staging_demo_contadora.sql
-- Undo: DELETE FROM f360_board.finance_preparers WHERE auth_user_id = (SELECT id FROM auth.users WHERE email = 'contadora.demo@staging.invalid');
--       DELETE FROM f360.user_roles WHERE auth_user_id = (same); then delete the auth user with the admin API.
BEGIN;
DO $$
DECLARE uid uuid;
BEGIN
  IF current_database() <> 'postgres' OR NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'mario.demo@staging.invalid') THEN
    RAISE EXCEPTION 'Not the staging database (no staging demo users): refusing.';
  END IF;
  SELECT id INTO uid FROM auth.users WHERE email = 'contadora.demo@staging.invalid';
  IF uid IS NULL THEN RAISE EXCEPTION 'Create the auth user contadora.demo@staging.invalid first (Auth admin API).'; END IF;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by)
    VALUES (uid, 'viewer', 'Contadora (demo)', 'Claude (demo staging, Mario 2026-10-11)')
    ON CONFLICT (auth_user_id) DO NOTHING;
  IF (SELECT role FROM f360.user_roles WHERE auth_user_id = uid) <> 'viewer' THEN RAISE EXCEPTION 'contadora.demo has a role other than viewer: check by hand.'; END IF;
  INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, can_close, can_budget, active, granted_by_name, evidence, note)
    VALUES (uid, 'Contadora (demo)', true, false, true, 'Claude (demo staging, Mario 2026-10-11)', 'usuario demo de staging', 'E2E de Cierre contable (I2)')
    ON CONFLICT (auth_user_id) DO NOTHING;
END $$;
SELECT r.display_name, r.role, p.can_close, p.can_budget, p.active
  FROM f360.user_roles r JOIN f360_board.finance_preparers p USING (auth_user_id)
  JOIN auth.users u ON u.id = r.auth_user_id WHERE u.email = 'contadora.demo@staging.invalid';
COMMIT;
