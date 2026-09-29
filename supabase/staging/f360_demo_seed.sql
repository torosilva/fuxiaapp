-- Fuxia 360 Admin V1 — STAGING demo configuration (never a migration; never production).
-- Locations are business configuration; demo owner accounts are staging-only identities.
-- psql variables: carolina, mario (auth user ids created by scripts/f360/demo_users.mjs)
BEGIN;
INSERT INTO f360.locations (name, type, is_authoritative, sales_sync_pending, sort)
VALUES ('Bodega CDMX', 'warehouse', true, false, 1)
ON CONFLICT (name) DO NOTHING;

INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
  (:'carolina', 'owner', 'Carolina', 'staging demo seed'),
  (:'mario',    'owner', 'Mario',    'staging demo seed')
ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name;
COMMIT;
