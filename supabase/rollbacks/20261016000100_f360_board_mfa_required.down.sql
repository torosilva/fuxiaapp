-- Rollback of 20261016000100_f360_board_mfa_required.sql. Turns the Board MFA requirement OFF again (audited in
-- f360_board.settings_changes), restores the SB0 nav hint and drops f360_board_access_state. Members' TOTP factors in
-- auth.mfa_factors are NOT touched (they simply stop being required). Only with Mario's explicit OK (it weakens access).
UPDATE f360_board.settings SET require_aal2 = false, updated_at = now() WHERE id AND require_aal2;
CREATE OR REPLACE FUNCTION public.f360_board_nav_visible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360_board.member_denial(auth.uid(), 'ANY') IS NULL
$$;
DROP FUNCTION IF EXISTS public.f360_board_access_state();
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261016000100';
