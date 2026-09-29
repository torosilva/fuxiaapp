-- Rollback of B4 (revenue planning). Drops only B4 objects. Planning assumptions and reported figures are lost —
-- export them first if they matter. STAGING / approved targets only.
BEGIN;
DROP FUNCTION IF EXISTS public.f360_set_reported_figure_status(uuid, text, text);
DROP FUNCTION IF EXISTS public.f360_add_reported_figure(text, numeric, text, text, text);
DROP FUNCTION IF EXISTS public.f360_save_growth_scenario(integer, text, jsonb);
DROP FUNCTION IF EXISTS public.f360_save_growth_plan(integer, numeric, text);
DROP FUNCTION IF EXISTS public.f360_growth_plan(integer);
DROP FUNCTION IF EXISTS f360.validate_growth_inputs(jsonb);
DROP TABLE IF EXISTS f360.reported_figures;
DROP TABLE IF EXISTS f360.growth_plan_changes;
DROP TABLE IF EXISTS f360.growth_scenarios;
DROP TABLE IF EXISTS f360.growth_plans;
COMMIT;
