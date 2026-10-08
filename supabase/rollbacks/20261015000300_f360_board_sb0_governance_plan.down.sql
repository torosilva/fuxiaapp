-- Rollback of 20261015000300_f360_board_sb0_governance_plan.sql. f360.growth_* are untouched by the up migration, so the
-- B4 Plan 2027 stays exactly as it is. WARNING: drops the decision log and plan revisions — only if they hold no real
-- governance records (check: SELECT count(*) FROM f360_board.decisions) or with both owners' explicit OK.
DROP FUNCTION IF EXISTS public.f360_board_plans();
DROP FUNCTION IF EXISTS public.f360_board_decisions(int);
DROP FUNCTION IF EXISTS public.f360_board_decision_act(uuid, text, text);
DROP FUNCTION IF EXISTS public.f360_board_decision_revise(uuid, text, text, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.f360_board_decision_propose(uuid, text, text, text, text, uuid[], jsonb, jsonb, uuid, jsonb);
DROP TABLE IF EXISTS f360_board.plan_revisions, f360_board.plan_years, f360_board.plan_versions;
DROP FUNCTION IF EXISTS f360_board.on_plan_change();
ALTER TABLE f360_board.budget_versions DROP CONSTRAINT IF EXISTS budget_versions_decision_fk;
DROP FUNCTION IF EXISTS f360_board.decision_json(f360_board.decisions, uuid);
DROP TABLE IF EXISTS f360_board.decision_recusals, f360_board.decision_events, f360_board.decision_revisions, f360_board.decisions;
DROP FUNCTION IF EXISTS f360_board.decision_event(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS f360_board.on_decision_change();
DROP SEQUENCE IF EXISTS f360_board.decision_number_seq;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000300';
