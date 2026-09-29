-- S0.0A · A1 — Close public RPC / function execution (P0-9, P0-11)
-- Plan: docs/fuxia360/audit/SPRINT_0_IMPLEMENTATION_PLAN.md (S0.0A → A1)
-- Rollback: supabase/rollbacks/20260925000100_s00a_a1_revoke_public_rpc.down.sql
--
-- Access change only: no function body, table, policy, trigger or data changes;
-- no loyalty-economics change.
--
-- 1) Internal functions: remove EXECUTE from PUBLIC (Postgres' implicit default),
--    anon and authenticated. service_role (Edge Functions: loyalty-credit →
--    fx_add_points, birthday-push → award_birthday_points) keeps EXECUTE explicitly.
--    The owner (postgres) keeps EXECUTE implicitly, e.g. inside the SECURITY DEFINER
--    trigger fx_aplicar_creditos_pendientes → fx_add_points.
-- 2) NOT changed: RLS helper functions my_customer_id(), my_phone(), my_role().
--    RLS policies call them for anon/authenticated, so they must stay executable.
--    Trigger functions are not callable through PostgREST and are left as-is.
-- 3) Future functions: stop auto-granting EXECUTE to PUBLIC (global default for
--    role postgres) and to anon/authenticated (schema public). A future function
--    meant for clients must GRANT explicitly in its own migration.

REVOKE EXECUTE ON FUNCTION public.fx_add_points(uuid, integer)               FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_birthday_points(uuid)                FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.award_referral_points(uuid)                FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.check_free_pair_reward(uuid, uuid)         FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.run_annual_tier_review()                   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_expired_otps()                      FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.fx_add_points(uuid, integer)                TO service_role;
GRANT EXECUTE ON FUNCTION public.award_birthday_points(uuid)                 TO service_role;
GRANT EXECUTE ON FUNCTION public.award_referral_points(uuid)                 TO service_role;
GRANT EXECUTE ON FUNCTION public.check_free_pair_reward(uuid, uuid)          TO service_role;
GRANT EXECUTE ON FUNCTION public.run_annual_tier_review()                    TO service_role;
GRANT EXECUTE ON FUNCTION public.delete_expired_otps()                       TO service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon, authenticated;
