-- Fuxia 360 · Panel ejecutivo RPC — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS adrian FROM f360.user_roles WHERE display_name = 'Adrián' \gset
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.adrian', :'adrian', true), set_config('t.s1', :'s1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; adr uuid := current_setting('t.adrian')::uuid; s1 uuid := current_setting('t.s1')::uuid;
  r jsonb; r2 jsonb; per text; expect numeric; y0 date := date_trunc('year', (now() AT TIME ZONE 'America/Mexico_City'))::date;
  m1 date := (date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City')) - interval '1 month')::date; st uuid; cop numeric;
BEGIN
  FOREACH per IN ARRAY ARRAY['hoy', 'semana', 'mes', 'anio'] LOOP
    r := pg_temp.as(car, format($q$SELECT public.f360_exec_dashboard(%L)$q$, per));
    PERFORM pg_temp.ok(r->>'period' = per AND r ? 'kpis' AND r ? 'daily' AND r ? 'pipeline' AND r ? 'crm' AND r ? 'heatmap' AND r ? 'feed' AND r ? 'trust',
      'shape: period ' || per || ' returns every section', coalesce(r->>'error', 'ok'));
  END LOOP;
  r := pg_temp.as(car, $q$SELECT public.f360_exec_dashboard('mes')$q$);
  PERFORM pg_temp.ok(jsonb_array_length(r->'daily') = 30, 'daily: 30 days', jsonb_array_length(r->'daily')::text);
  PERFORM pg_temp.ok((r->>'includes_test_data')::boolean = NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE is_production),
    'test data: included only in a database without a production target (staging), and flagged', r->>'includes_test_data');

  -- money: headline MXN = countable MXN net product of the year + historical; COP never mixed
  st := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Dash Tienda', 'store')$q$)->>'id')::uuid;
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 120000, 48, true)$q$, st, m1));
  r := pg_temp.as(car, $q$SELECT public.f360_exec_dashboard('anio')$q$);
  SELECT coalesce(sum(net_product), 0) INTO expect FROM f360.commerce_orders o WHERE status_class = 'countable' AND currency_original = 'MXN'
    AND (paid_at AT TIME ZONE 'America/Mexico_City')::date >= y0;
  expect := expect + (SELECT coalesce(sum(amount), 0) FROM f360.historical_sales_active WHERE period_start >= y0);
  PERFORM pg_temp.ok((r->'kpis'->>'sales')::numeric = expect, 'money: year sales = MXN countable net product + historical summaries (to the peso)',
    (r->'kpis'->>'sales') || ' = ' || expect);
  PERFORM pg_temp.ok((r->'kpis'->>'historical_included')::numeric >= 120000 AND r->'by_location' @> jsonb_build_array(jsonb_build_object('name', 'ZZ Dash Tienda', 'historical', true)),
    'historical: Carolina''s summary appears in the year and by location (marked historical)', 'ok');
  SELECT coalesce(sum(net_product), 0) INTO cop FROM f360.commerce_orders WHERE status_class = 'countable' AND currency_original = 'COP'
    AND (paid_at AT TIME ZONE 'America/Mexico_City')::date >= y0;
  PERFORM pg_temp.ok(cop = 0 OR r->'other_currencies' @> jsonb_build_array(jsonb_build_object('currency', 'COP')), 'money: COP reported apart, never in the MXN headline',
    coalesce((r->'other_currencies')::text, '[]'));
  r2 := pg_temp.as(car, $q$SELECT public.f360_exec_dashboard('mes')$q$);
  PERFORM pg_temp.ok((r2->'kpis'->>'historical_included')::numeric = 0, 'historical: last month''s summary does not count in the current month', r2->'kpis'->>'historical_included');

  -- privacy
  PERFORM pg_temp.ok(jsonb_typeof(r->'crm'->'birthdays') = 'array', 'privacy: a PII viewer (Carolina) gets the birthday list (first name + initial)', jsonb_typeof(r->'crm'->'birthdays'));
  r := pg_temp.as(car, $q$SELECT public.f360_exec_dashboard('mes', true)$q$);
  PERFORM pg_temp.ok(r->'crm'->'birthdays' = 'null'::jsonb AND (r->>'presentation')::boolean, 'privacy: presentation view never carries names', coalesce((r->'crm'->'birthdays')::text, 'null'));
  r := pg_temp.as(adr, $q$SELECT public.f360_exec_dashboard('mes')$q$);
  PERFORM pg_temp.ok(r->'crm'->'birthdays' = 'null'::jsonb, 'privacy: an owner who is not a PII viewer gets counts only', coalesce((r->'crm'->'birthdays')::text, r->>'error'));
  PERFORM pg_temp.ok(position('@' IN r::text) = 0 AND position('+52' IN r::text) = 0, 'privacy: no email or phone anywhere in the aggregate', 'ok');
  r := pg_temp.as(s1, $q$SELECT public.f360_exec_dashboard('mes')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'permission: a seller cannot open the dashboard', r->>'error');
  r := pg_temp.as(NULL, $q$SELECT public.f360_exec_dashboard('mes')$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'permission: anon refused', r->>'error');
  r := pg_temp.as(car, $q$SELECT public.f360_exec_dashboard('cualquier cosa')$q$);
  PERFORM pg_temp.ok(r->>'period' = 'mes', 'input: an unknown period falls back to the month', r->>'period');
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
