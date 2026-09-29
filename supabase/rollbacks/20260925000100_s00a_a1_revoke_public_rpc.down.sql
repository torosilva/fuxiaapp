-- ROLLBACK for S0.0A · A1 (20260925000100_s00a_a1_revoke_public_rpc.sql)
-- ⚠ Re-opens P0-9 (public fx_add_points) and P0-11. Apply ONLY on a proven regression,
--   with explicit approval. Apply by hand (psql / SQL Editor) to the affected project, then
--   mark the version reverted in that project's migration history:
--     supabase migration repair --status reverted 20260925000100 --db-url "$STAGING_DB_URL"   (staging)
-- Restores exactly the pre-A1 state captured in docs/fuxia360/audit/live/schema.sql:
--   explicit EXECUTE for anon/authenticated/service_role + Postgres' implicit PUBLIC EXECUTE,
--   and the default privileges for role postgres.

GRANT EXECUTE ON FUNCTION public.fx_add_points(uuid, integer)        TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_birthday_points(uuid)         TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.award_referral_points(uuid)         TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_free_pair_reward(uuid, uuid)  TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_annual_tier_review()            TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.delete_expired_otps()               TO PUBLIC, anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres GRANT EXECUTE ON FUNCTIONS TO PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;
