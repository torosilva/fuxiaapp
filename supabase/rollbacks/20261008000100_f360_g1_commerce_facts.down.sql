-- Rollback of 20261008000100 (G1-B Commerce Facts). Inventory, woo_orders/woo_order_lines and store sales are untouched
-- by the forward migration, so nothing there needs restoring. Restores f360_growth_plan to its B4 definition (viewer).
SELECT cron.unschedule('f360-commerce-poll') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-commerce-poll');
DROP FUNCTION IF EXISTS f360.commerce_poll_tick();
DROP FUNCTION IF EXISTS public.f360_commerce_facts(int);
DROP FUNCTION IF EXISTS public.f360_commerce_summary(date, date);
DROP VIEW IF EXISTS f360.commerce_source_health;
DROP VIEW IF EXISTS f360.commerce_order_lines;
DROP VIEW IF EXISTS f360.commerce_orders;
DROP VIEW IF EXISTS f360.commerce_woo_refund_totals;
DROP FUNCTION IF EXISTS public.f360_commerce_run_end(bigint, boolean, jsonb, text, timestamptz);
DROP FUNCTION IF EXISTS public.f360_commerce_run_begin(text, text);
DROP FUNCTION IF EXISTS public.f360_capture_order_economics(text, jsonb, text);
DROP FUNCTION IF EXISTS f360.commerce_market(text);
DROP FUNCTION IF EXISTS f360.commerce_status_class(text, boolean);
DROP FUNCTION IF EXISTS f360.commerce_payment_category(text);
DROP FUNCTION IF EXISTS f360.commerce_business_origin(text);
DROP FUNCTION IF EXISTS f360.commerce_ts(text);
DROP FUNCTION IF EXISTS f360.commerce_amount(jsonb, text);
DROP TABLE IF EXISTS f360.commerce_sync_runs;
DROP TABLE IF EXISTS f360.commerce_sync_state;
DROP TABLE IF EXISTS f360.commerce_woo_status_log;
DROP TABLE IF EXISTS f360.commerce_woo_attribution;
DROP TABLE IF EXISTS f360.commerce_woo_refunds;
DROP TABLE IF EXISTS f360.commerce_woo_order_lines;
DROP TABLE IF EXISTS f360.commerce_woo_orders;

CREATE OR REPLACE FUNCTION public.f360_growth_plan(p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; gp f360.growth_plans;
BEGIN
  r := f360.require_role('viewer');
  SELECT * INTO gp FROM f360.growth_plans WHERE plan_year = p_year;
  RETURN jsonb_build_object(
    'year', p_year,
    'plan', CASE WHEN gp.plan_year IS NULL THEN NULL ELSE jsonb_build_object('north_star', gp.north_star, 'note', gp.note, 'updated_by_name', gp.updated_by_name, 'updated_at', gp.updated_at) END,
    'scenarios', (SELECT coalesce(jsonb_object_agg(kind, jsonb_build_object('inputs', inputs, 'updated_by_name', updated_by_name, 'updated_at', updated_at)), '{}')
                  FROM f360.growth_scenarios WHERE plan_year = p_year),
    'reported_figures', (SELECT coalesce(jsonb_agg(to_jsonb(f) - 'currency' ORDER BY f.period DESC, f.created_at DESC), '[]') FROM f360.reported_figures f),
    'changes', (SELECT coalesce(jsonb_agg(jsonb_build_object('what', what, 'by', by_name, 'at', at) ORDER BY id DESC), '[]')
                FROM (SELECT * FROM f360.growth_plan_changes WHERE plan_year = p_year ORDER BY id DESC LIMIT 10) c),
    'can_edit', r.role = 'owner');
END $$;
