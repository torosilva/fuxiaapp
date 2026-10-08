-- Rollback of 20261015000400_f360_d13_intent_reports_operator.sql: give the four reports back to viewer+ (incl. sellers).
-- Only do this with Mario's explicit OK — it re-opens finding F1 (sellers can read aggregate demand/intent via PostgREST).
DO $$
DECLARE f text; def text; n int;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.f360_stock_demand(text)', 'public.f360_favorites_report(text,integer)', 'public.f360_review_summary(uuid)',
                           'public.f360_store_order(text)'] LOOP
    def := pg_get_functiondef(f::regprocedure);
    n := (length(def) - length(replace(def, 'require_role(''operator'')', ''))) / length('require_role(''operator'')');
    IF n <> 1 THEN RAISE EXCEPTION 'D13 rollback: % has % operator gates (expected exactly 1)', f, n; END IF;
    EXECUTE replace(def, 'require_role(''operator'')', 'require_role(''viewer'')');
  END LOOP;
END $$;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000400';
