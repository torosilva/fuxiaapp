-- Rollback of 20261017000100_f360_board_earnin_tracker.sql (Strategy & Board · earn-in tracker).
-- Once applied with real proposals, EXPORT f360_board.earnin_terms / earnin_milestones first: this drops them.
-- The MARIO_OWNERSHIP decisions created by f360_board_earnin_propose stay in f360_board.decisions (their own history).
BEGIN;
DROP FUNCTION IF EXISTS public.f360_board_earnin();
DROP FUNCTION IF EXISTS public.f360_board_earnin_propose(uuid, jsonb);
DROP FUNCTION IF EXISTS f360_board.earnin_terms_json(f360_board.earnin_terms, uuid);
DROP FUNCTION IF EXISTS f360_board.earnin_forecast(int);
DROP FUNCTION IF EXISTS f360_board.earnin_mgmt_target(int);
DROP FUNCTION IF EXISTS f360_board.earnin_revenue(int, text[]);
DROP FUNCTION IF EXISTS f360_board.earnin_indicative(numeric, numeric, numeric, numeric);
DROP TABLE IF EXISTS f360_board.earnin_milestones;
DROP TABLE IF EXISTS f360_board.earnin_terms;
DROP FUNCTION IF EXISTS f360_board.earnin_milestone_guard();
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261017000100';
COMMIT;
