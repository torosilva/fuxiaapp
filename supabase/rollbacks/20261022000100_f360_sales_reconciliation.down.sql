-- Rollback of 20261022000100_f360_sales_reconciliation.sql. Drops the reconciliation layer only; Commerce Facts are untouched.
-- WARNING: drops the human decisions, evidence snapshots and exclusions recorded so far (export them first if they matter).
DROP FUNCTION IF EXISTS public.f360_rec_evidence_record(uuid, text, bigint, jsonb);
DROP FUNCTION IF EXISTS public.f360_rec_set_analytics(uuid, bigint, boolean, text);
DROP FUNCTION IF EXISTS public.f360_rec_decide(uuid, bigint, text, text, bigint, bigint);
DROP FUNCTION IF EXISTS public.f360_rec_case(uuid, bigint);
DROP FUNCTION IF EXISTS public.f360_rec_summary(date, date, text);
DROP FUNCTION IF EXISTS public.f360_rec_list(date, date, text, text, text, text, text, text, int, int);
DROP FUNCTION IF EXISTS public.f360_rec_can_view();
DROP FUNCTION IF EXISTS f360.sales_rec_row(f360.sales_rec_cases_state);
DROP FUNCTION IF EXISTS f360.sales_rec_actor_name(uuid);
DROP VIEW IF EXISTS f360.sales_rec_cases_state;
DROP VIEW IF EXISTS f360.sales_rec_cases;
DROP VIEW IF EXISTS f360.sales_rec_analytics_scope;
DROP TABLE IF EXISTS f360.sales_rec_exclusions;
DROP TABLE IF EXISTS f360.sales_rec_decisions;
DROP TABLE IF EXISTS f360.sales_rec_evidence;
