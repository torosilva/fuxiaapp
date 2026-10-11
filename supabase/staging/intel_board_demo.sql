-- STAGING data · after a prod → staging copy, f360_board.board_members holds the REAL members (from production). The staging DEMO
-- owners (mario.demo / carolina.demo @staging.invalid) must also be board members so the Centro de Inteligencia (cockpit, analyst,
-- budget, goals) can be tested with them. Real members are never touched. person_key stays NULL for the demos (it belongs to
-- the real people: conflict-of-interest rules). Aborts outside staging. Idempotent; audited by the board_members trigger.
BEGIN;
DO $$
DECLARE r record;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'f360_sync_url' AND decrypted_secret LIKE '%faltxpkaicwpnlqaxrdu%') THEN
    RAISE EXCEPTION 'ABORT: esto no es staging';
  END IF;
  FOR r IN SELECT u.id, CASE u.email WHEN 'mario.demo@staging.invalid' THEN 'Mario (demo)' ELSE 'Carolina (demo)' END AS name
           FROM auth.users u JOIN f360.user_roles ur ON ur.auth_user_id = u.id AND ur.role = 'owner'
           WHERE u.email IN ('mario.demo@staging.invalid', 'carolina.demo@staging.invalid') LOOP
    INSERT INTO f360_board.board_members (auth_user_id, person_key, display_name, scopes, granted_by_name, evidence, note)
      VALUES (r.id, NULL, r.name, f360_board.valid_scopes(), 'Claude (staging, Mario 2026-10-11)', 'usuario demo de staging (@staging.invalid)',
              'Solo staging: pruebas del Centro de Inteligencia')
      ON CONFLICT (auth_user_id) DO NOTHING;
  END LOOP;
  IF (SELECT count(*) FROM f360_board.board_members m JOIN auth.users u ON u.id = m.auth_user_id WHERE u.email LIKE '%.demo@staging.invalid' AND m.active) < 2 THEN
    RAISE EXCEPTION 'ABORT: faltan los usuarios demo (mario.demo / carolina.demo) como dueños';
  END IF;
END $$;
COMMIT;
