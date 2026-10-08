-- Fuxia 360 · pase P0A2 — Strategy & Board members in PRODUCTION (Mario 2026-10-08: "súbelo"). By auth.users id, never by name.
-- Guard: each id must be an owner in f360.user_roles AND a customer_pii_viewer in production. Apply ONLY with prod_sql.sh after P0A.
BEGIN;
DO $$ DECLARE x uuid; BEGIN
  IF to_regnamespace('f360_board') IS NULL THEN RAISE EXCEPTION 'ABORT: P0A not applied'; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.board_members) THEN RAISE EXCEPTION 'ABORT: members already present'; END IF;
  FOREACH x IN ARRAY ARRAY['31da6b13-70eb-4d89-8019-6f04c3207300', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b']::uuid[] LOOP
    IF NOT EXISTS (SELECT 1 FROM f360.user_roles r JOIN f360.customer_pii_viewers v USING (auth_user_id) WHERE r.auth_user_id = x AND r.role = 'owner')
    THEN RAISE EXCEPTION 'ABORT: % is not owner + PII viewer', x; END IF;
  END LOOP;
  INSERT INTO f360_board.board_members (auth_user_id, person_key, display_name, scopes, granted_by_name, evidence, note) VALUES
    ('31da6b13-70eb-4d89-8019-6f04c3207300', 'CAROLINA', 'Carolina', f360_board.valid_scopes(), 'Mario 2026-10-08 (pase P0A2)',
     'prod auth id; f360.user_roles owner; customer_pii_viewers', 'D10'),
    ('d11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'MARIO', 'Mario', f360_board.valid_scopes(), 'Mario 2026-10-08 (pase P0A2)',
     'prod auth id; f360.user_roles owner; customer_pii_viewers', 'D10');
END $$;
SELECT jsonb_build_object('members', (SELECT jsonb_agg(person_key ORDER BY person_key) FROM f360_board.board_members),
  'mfa', (SELECT require_aal2 FROM f360_board.settings));
COMMIT;
