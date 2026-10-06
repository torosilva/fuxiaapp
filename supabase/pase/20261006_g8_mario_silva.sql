-- Fuxia 360 · pase G8 — Mario asked (2026-10-06): give owner access to Mario Silva's production app account (+52 55…2939).
-- Owner role + "ver datos de clientas" (only Carolina and Mario). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by)
VALUES ('d11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'owner', 'Mario Silva', 'pase G8 (Mario 2026-10-06)')
ON CONFLICT (auth_user_id) DO UPDATE SET role = 'owner', display_name = 'Mario Silva';
INSERT INTO f360.customer_pii_viewers (auth_user_id, granted_by, note)
VALUES ('d11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'pase G8 (Mario 2026-10-06)', 'Mario Silva')
ON CONFLICT DO NOTHING;
COMMIT;
