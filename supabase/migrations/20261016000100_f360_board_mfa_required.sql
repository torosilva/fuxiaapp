-- Fuxia 360 · Strategy & Board · MFA MANDATORY FOR THE BOARD ONLY (Mario 2026-10-08, pre-production gate decision 1).
-- Spec: docs/fuxia360/strategy-board/01_ACCESS_MODEL.md §3.4 (D2), 14_SECURITY_MODEL.md F12; report:
-- docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md §MFA.
--
-- What changes:
--   · f360_board.settings.require_aal2 = true (the switch SB0 already built; the change is written to settings_changes by the
--     existing audit trigger). From now on every public.f360_board_* RPC answers {ok:false,"No disponible."} — and logs
--     'denied' / reason 'mfa_required' — unless the caller's verified Supabase JWT carries aal = 'aal2' (a TOTP factor was
--     verified in THIS session). Identity still comes only from the JWT (auth.uid(), auth.jwt()->>'aal').
--   · public.f360_board_nav_visible(): a member who is only missing the second factor still SEES the menu entry, so she can
--     reach /estrategia and complete the challenge (before: the entry disappeared and the member could not get to MFA).
--   · public.f360_board_access_state(): 'ok' | 'mfa_required' | 'none' about the CALLER only (no data, no other person;
--     a non-member always gets 'none', exactly like nav_visible=false). The admin uses it to show the enroll / challenge screen.
-- What does NOT change: every other Fuxia 360 RPC (sales, inventory, CRM, Growth, Medición…) keeps working at aal1 —
-- nothing outside f360_board reads the aal claim. A member who has not enrolled MFA keeps the rest of the admin and the app.
-- Membership, scopes, owner requirement, approval rules and logging are untouched.
-- Rollback: supabase/rollbacks/20261016000100_f360_board_mfa_required.down.sql

UPDATE f360_board.settings SET require_aal2 = true, updated_at = now() WHERE id AND NOT require_aal2;

-- Navigation hint ONLY (never a security decision): active member, possibly still without the second factor.
CREATE OR REPLACE FUNCTION public.f360_board_nav_visible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce(f360_board.member_denial(auth.uid(), 'ANY'), 'ok') IN ('ok', 'mfa_required')
$$;

-- The caller's own Board access state. member_denial checks MFA LAST, so 'mfa_required' implies: session, active member,
-- owner role — only the second factor is missing. Not logged (like nav_visible); the real gate logs every Board call.
CREATE FUNCTION public.f360_board_access_state() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE coalesce(f360_board.member_denial(auth.uid(), 'ANY'), 'ok')
           WHEN 'ok' THEN 'ok' WHEN 'mfa_required' THEN 'mfa_required' ELSE 'none' END
$$;

REVOKE ALL ON FUNCTION public.f360_board_access_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_board_access_state() TO authenticated;
