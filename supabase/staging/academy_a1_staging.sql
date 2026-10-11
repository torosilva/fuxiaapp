-- STAGING data · Fuxia Academy A1 (Mario 2026-10-11: "cuentas de prueba autorizadas"; no real sellers).
--   · Carolina (demo)  = editor + approver of academy_content.publish_sales / publish_sales_policy / retire (product authority)
--   · Mario (demo)     = Academy admin + editor + approver of academy_content.publish_sales_policy / retire (never publish_sales:
--                        ordinary product content is Carolina's)
--   · Alumna Prueba 1  = test seller (+1 555 019 0901, fictitious) WITH the 'tester' grant → can study (access 'ok')
--   · Alumna Prueba 2  = test seller (+1 555 019 0902, fictitious) WITHOUT 'tester' → access 'bloqueado' (evidence of the P0-6 gate)
-- Requires the demo owners (demo_users.mjs) and the two test accounts (academy_a1_test_users.mjs). Idempotent; writes ONLY staging.
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/staging/academy_a1_staging.sql
BEGIN;
DO $$
DECLARE
  caro uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'carolina.demo@staging.invalid');
  mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  a1 uuid := (SELECT id FROM auth.users WHERE email = 'alumna.prueba1@staging.invalid');
  a2 uuid := (SELECT id FROM auth.users WHERE email = 'alumna.prueba2@staging.invalid');
  store uuid := (SELECT id FROM f360.locations WHERE type = 'store' AND status = 'active' ORDER BY sort, name LIMIT 1);
  s uuid; t record;
BEGIN
  -- Production guard: the @staging.invalid demo/test accounts exist only in staging, so the check below aborts anywhere else.
  IF caro IS NULL OR mario IS NULL OR a1 IS NULL OR a2 IS NULL OR store IS NULL THEN
    RAISE EXCEPTION 'ABORT: faltan cuentas demo, cuentas de prueba o una tienda activa';
  END IF;
  INSERT INTO f360_academy.grants (auth_user_id, role, display_name, granted_by_name, evidence) VALUES
    (caro,  'editor', 'Carolina', 'Mario (A1 2026-10-11)', 'Cuenta demo de staging carolina.demo@staging.invalid'),
    (mario, 'admin',  'Mario',    'Mario (A1 2026-10-11)', 'Cuenta demo de staging mario.demo@staging.invalid'),
    (mario, 'editor', 'Mario',    'Mario (A1 2026-10-11)', 'Cuenta demo de staging mario.demo@staging.invalid'),
    (a1,    'tester', 'Alumna Prueba 1', 'Mario (A1 2026-10-11)', 'Cuenta de prueba ficticia alumna.prueba1@staging.invalid')
  ON CONFLICT DO NOTHING;
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name, note) VALUES
    ('academy_content', caro,  'Carolina', 'Mario (A1 2026-10-11)', 'Autoridad de contenido de producto'),
    ('academy_content', mario, 'Mario',    'Mario (A1 2026-10-11)', 'Segunda persona para políticas y retiros')
  ON CONFLICT DO NOTHING;
  INSERT INTO f360.approval_scope_operations (scope, auth_user_id, operation, added_by_name) VALUES
    ('academy_content', caro,  'publish_sales',        'Mario (A1 2026-10-11)'),
    ('academy_content', caro,  'publish_sales_policy', 'Mario (A1 2026-10-11)'),
    ('academy_content', caro,  'retire',               'Mario (A1 2026-10-11)'),
    ('academy_content', mario, 'publish_sales_policy', 'Mario (A1 2026-10-11)'),
    ('academy_content', mario, 'retire',               'Mario (A1 2026-10-11)')
  ON CONFLICT DO NOTHING;
  -- the two fictitious test sellers, through the normal activation (role seller + her store; PIN random and never shown)
  FOR t IN SELECT * FROM (VALUES (a1, '+15550190901', 'Alumna Prueba 1'), (a2, '+15550190902', 'Alumna Prueba 2')) x(uid, phone, name) LOOP
    IF NOT EXISTS (SELECT 1 FROM f360.sellers WHERE phone = t.phone) THEN
      INSERT INTO f360.sellers (phone, name, location_id, pin_hash, status, created_by_name)
      VALUES (t.phone, t.name, store, extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf', 10)), 'pendiente', 'Academy A1 (staging)')
      RETURNING id INTO s;
      PERFORM f360.activate_seller(s, t.uid, 'Academy A1 (staging)', NULL);
    END IF;
  END LOOP;
END $$;
COMMIT;
