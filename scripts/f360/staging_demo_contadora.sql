-- STAGING ONLY · demo "Contadora" for the I2 Cierre contable E2E (Mario 2026-10-11 via coordinator).
-- Prerequisite: the auth user contadora.demo@staging.invalid exists (created with the staging Auth admin API, email_confirm
-- true; its password lives only in ~/.fuxia-staging.env as STAGING_DEMO_CONTADORA_PASSWORD). This script only gives that
-- account the limited finance-preparer capability WITHOUT any Fuxia 360 role (0700, least privilege: no f360.user_roles row; an
-- earlier demo 'viewer' row is removed first), in one transaction. Idempotent: re-run it
-- after a production → staging copy. Refuses to run anywhere that is not the staging project.
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f scripts/f360/staging_demo_contadora.sql
-- Undo: DELETE FROM f360_board.finance_preparers WHERE auth_user_id = (SELECT id FROM auth.users WHERE email = 'contadora.demo@staging.invalid');
--       then delete the auth user with the admin API.
BEGIN;
DO $$
DECLARE uid uuid;
BEGIN
  IF current_database() <> 'postgres' OR NOT EXISTS (SELECT 1 FROM auth.users WHERE email = 'mario.demo@staging.invalid') THEN
    RAISE EXCEPTION 'Not the staging database (no staging demo users): refusing.';
  END IF;
  SELECT id INTO uid FROM auth.users WHERE email = 'contadora.demo@staging.invalid';
  IF uid IS NULL THEN RAISE EXCEPTION 'Create the auth user contadora.demo@staging.invalid first (Auth admin API).'; END IF;
  -- least privilege (0700): the contadora has NO Fuxia 360 role; only a 'viewer' row created by the earlier demo is removed
  IF EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = uid AND role <> 'viewer') THEN RAISE EXCEPTION 'contadora.demo has a role other than viewer: check by hand.'; END IF;
  DELETE FROM f360.user_roles WHERE auth_user_id = uid AND role = 'viewer';
  INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, can_close, can_budget, active, granted_by_name, evidence, note)
    VALUES (uid, 'Contadora (demo)', true, false, true, 'Claude (demo staging, Mario 2026-10-11)', 'usuario demo de staging', 'E2E de Cierre contable (I2)')
    ON CONFLICT (auth_user_id) DO NOTHING;
END $$;
SELECT p.display_name, p.can_close, p.can_budget, p.active, EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = p.auth_user_id) AS tiene_rol_f360
  FROM f360_board.finance_preparers p JOIN auth.users u ON u.id = p.auth_user_id WHERE u.email = 'contadora.demo@staging.invalid';
COMMIT;
