-- Rollback of 20261015000200_f360_board_sb0_finance_foundation.sql (roll back 20261015000300 first).
-- WARNING: drops fiscal periods, manual close captures and close snapshots — only if empty of real closes
-- (SELECT count(*) FROM f360_board.monthly_close_entries; … close_actual_snapshots) or with both owners' explicit OK.
DROP FUNCTION IF EXISTS public.f360_board_metric_catalog();
DROP FUNCTION IF EXISTS public.f360_board_period_transition(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.f360_board_close_entries_approve(uuid);
DROP FUNCTION IF EXISTS public.f360_board_close_entry_void(uuid, text);
DROP FUNCTION IF EXISTS public.f360_board_close_entry_add(uuid, uuid, text, numeric, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.f360_board_close_get(uuid);
DROP FUNCTION IF EXISTS public.f360_board_periods(int);
DROP FUNCTION IF EXISTS f360_board.close_readiness(uuid);
DROP TABLE IF EXISTS f360_board.forecast_snapshots, f360_board.forecast_lines, f360_board.forecast_versions,
  f360_board.budget_lines, f360_board.budget_versions;
DROP FUNCTION IF EXISTS f360_board.on_version_line_change();
DROP FUNCTION IF EXISTS f360_board.on_version_change();
DROP TABLE IF EXISTS f360_board.metric_catalog, f360_board.close_actual_snapshots, f360_board.monthly_close_log,
  f360_board.monthly_close_entries, f360_board.close_accounts, f360_board.fiscal_period_events, f360_board.fiscal_periods,
  f360_board.reporting_entities;
DROP FUNCTION IF EXISTS f360_board.on_close_entry();
DROP FUNCTION IF EXISTS f360_board.ensure_fiscal_year(text, int);
DROP FUNCTION IF EXISTS f360_board.on_period_change();
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000200';
