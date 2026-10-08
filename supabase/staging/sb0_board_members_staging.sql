-- Strategy & Board · SB0 — STAGING board membership (faltxpkaicwpnlqaxrdu ONLY). Inserted BY AUTH ID, never by name.
-- Evidence (staging, 2026-10-08, read before writing — see docs/fuxia360/strategy-board/SB0_DELIVERY.md §3):
--   aa375921-4cef-4004-9127-b8e80bd0a933 · f360.user_roles owner "Carolina" · f360.customer_pii_viewers (migration 20261010000100,
--     "Decisión Mario 2026-10-05") · auth.users car***@staging.invalid (staging demo login, created 2026-09-25)
--   c50849b9-6dbe-4822-a75c-fd48066612c3 · f360.user_roles owner "Mario" · f360.customer_pii_viewers (same) ·
--     auth.users mar***@staging.invalid (staging demo login, created 2026-09-25)
--   NOT a member: bc6bc0e2-d733-4e6d-a85a-6b1a18eaafdf (owner "Adrián", technical; excluded from PII by 20261010000100:90).
-- These ids do not exist in production: the guard aborts anywhere else. Production membership = separate approved pase.
DO $$
DECLARE car uuid := 'aa375921-4cef-4004-9127-b8e80bd0a933'; mar uuid := 'c50849b9-6dbe-4822-a75c-fd48066612c3'; x uuid;
BEGIN
  FOREACH x IN ARRAY ARRAY[car, mar] LOOP
    IF NOT EXISTS (SELECT 1 FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id JOIN f360.customer_pii_viewers v ON v.auth_user_id = u.id
                   WHERE u.id = x AND r.role = 'owner' AND u.email LIKE '%@staging.invalid') THEN
      RAISE EXCEPTION 'ABORT: % is not the verified staging owner+PII viewer — wrong database?', x;
    END IF;
  END LOOP;
  INSERT INTO f360_board.board_members (auth_user_id, person_key, display_name, scopes, granted_by_name, evidence, note) VALUES
    (car, 'CAROLINA', 'Carolina', f360_board.valid_scopes(), 'Mario 2026-10-08 (autorización SB0, staging)',
     'staging auth.users id; f360.user_roles owner; f360.customer_pii_viewers (migration 20261010000100)', 'D10 allowlist inicial'),
    (mar, 'MARIO', 'Mario', f360_board.valid_scopes(), 'Mario 2026-10-08 (autorización SB0, staging)',
     'staging auth.users id; f360.user_roles owner; f360.customer_pii_viewers (migration 20261010000100)', 'D10 allowlist inicial')
  ON CONFLICT (auth_user_id) DO NOTHING;
END $$;
