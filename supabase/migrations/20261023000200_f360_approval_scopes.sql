-- Fuxia 360 · f360.approval_scopes ("quién aprueba qué"), extracted from 20261024000100_f360_fx_daily so the store discounts
-- (20261025000100) can go to production before the daily-FX work (Mario 2026-10-11: "si mejor separa"). IDEMPOTENT and
-- identical to the definition in 20261024000100 (which now also uses IF NOT EXISTS / OR REPLACE), so either order works.
-- Loaded per environment; empty = nobody approves anything.
-- Rollback: supabase/rollbacks/20261023000200_f360_approval_scopes.down.sql
CREATE TABLE IF NOT EXISTS f360.approval_scopes (
  scope         text NOT NULL CHECK (scope IN ('fx_rate', 'budget', 'close')),
  auth_user_id  uuid NOT NULL,
  display_name  text NOT NULL,
  added_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  added_by_name text NOT NULL,
  note          text CHECK (note IS NULL OR length(note) <= 300),
  PRIMARY KEY (scope, auth_user_id)
);
COMMENT ON TABLE f360.approval_scopes IS 'Who approves what (Mario 2026-10-11): fx_rate = Mario; budget = Mario; close = Mario or Carolina. Loaded per environment; empty = nobody.';
CREATE OR REPLACE FUNCTION f360.can_approve(p_scope text, p_user uuid) RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM f360.approval_scopes WHERE scope = p_scope AND auth_user_id = p_user) $$;
ALTER TABLE f360.approval_scopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.approval_scopes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.approval_scopes TO service_role;
REVOKE ALL ON FUNCTION f360.can_approve(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.can_approve(text, uuid) TO service_role;
