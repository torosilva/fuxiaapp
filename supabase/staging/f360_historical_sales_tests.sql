-- Fuxia 360 · Ventas históricas (resumen) — database tests (STAGING). One transaction, ROLLED BACK.
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
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.s1', :'s1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; s1 uuid := current_setting('t.s1')::uuid; r jsonb; st uuid; st2 uuid; bz uuid; id1 uuid; n int;
  m0 date := date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City'))::date;       -- current month
  m1 date := (date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City')) - interval '1 month')::date;   -- last month
  m2 date := (date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City')) - interval '2 month')::date;
BEGIN
  st := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Hist Tienda', 'store')$q$)->>'id')::uuid;
  st2 := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Hist Tienda Nueva', 'store')$q$)->>'id')::uuid;
  UPDATE f360.locations SET starts_on = m1 WHERE id = st2;
  bz := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Hist Bazar', 'bazaar')$q$)->>'id')::uuid;
  PERFORM pg_temp.ok(st IS NOT NULL AND bz IS NOT NULL, 'fixture: a store and a bazaar', 'ok');

  -- ── store month ──
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 120000, 48, true, 'Abrió en septiembre')$q$, st, m1 + 14));
  id1 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(r->>'ok' = 'true', 'store month: Carolina loads "last month $120,000 · ~48 pares"', left(r::text, 80));
  PERFORM pg_temp.ok((SELECT period_start = m1 AND period_end = (m1 + interval '1 month - 1 day')::date AND amount = 120000 AND pairs = 48 AND pairs_estimated AND currency = 'MXN'
                      FROM f360.historical_sales WHERE id = id1), 'store month: any day → the whole month; MXN; pairs marked estimated', 'ok');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 99000, 40)$q$, st, m1));
  PERFORM pg_temp.ok(r->>'code' = 'duplicate', 'store month: the same month twice is refused', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 50000, 20)$q$, st, m0));
  PERFORM pg_temp.ok(r->>'code' = 'future', 'store month: the current month is refused (still being sold)', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 50000, 20)$q$, st2, m2));
  PERFORM pg_temp.ok(r->>'code' = 'before_opening', 'store month: before the store opened is refused', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 50000, 20)$q$, bz, m1));
  PERFORM pg_temp.ok(r->>'code' = 'bad_location', 'store month: a bazaar is not a store', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, '2024-06-01', NULL, 50000, 20)$q$, st));
  PERFORM pg_temp.ok(r->>'code' = 'too_old', 'store month: before 2025 refused', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 0, 20)$q$, st, m2));
  PERFORM pg_temp.ok(r->>'code' = 'bad_amount', 'store month: amount required', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 1000, -1)$q$, st, m2));
  PERFORM pg_temp.ok(r->>'code' = 'bad_pairs', 'store month: negative pairs refused', r->>'code');

  -- ── no double counting with Fuxia 360 sales ──
  INSERT INTO public.offline_sales (code, location_id, total, items, created_by_rpc, created_at, payment_method)
    VALUES ('ZZHIST', st, 2800, '[]', true, (m2 + 3)::timestamp AT TIME ZONE 'America/Mexico_City', 'cash');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 80000, 30)$q$, st, m2));
  PERFORM pg_temp.ok(r->>'code' = 'already_recorded', 'no double count: a month with Fuxia 360 store sales is refused', r->>'code');

  -- ── bazaar ──
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', NULL, '  Bazar   Las Lomas ', %L, %L, 86000, 31)$q$, m2 + 13, m2 + 14));
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND (SELECT bazaar_name = 'Bazar Las Lomas' AND location_id IS NULL FROM f360.historical_sales WHERE id = (r->>'id')::uuid),
    'bazaar: a past bazaar by name + dates + amount + pairs (no location created)', left(r::text, 60));
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', NULL, 'bazar las lomas', %L, %L, 1000, 1)$q$, m2 + 13, m2 + 14));
  PERFORM pg_temp.ok(r->>'code' = 'duplicate', 'bazaar: the same bazaar (any case/spaces) on the same start date is refused', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', %L, NULL, %L, %L, 40000, 15)$q$, bz, m1 + 2, m1 + 3));
  PERFORM pg_temp.ok(r->>'ok' = 'true', 'bazaar: or an existing bazaar location', left(r::text, 60));
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', NULL, 'Bazar Largo', %L, %L, 1000, 1)$q$, m2, m2 + 40));
  PERFORM pg_temp.ok(r->>'code' = 'bad_dates', 'bazaar: more than 31 days refused', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', NULL, '', %L, %L, 1000, 1)$q$, m2, m2));
  PERFORM pg_temp.ok(r->>'code' = 'bad_bazaar', 'bazaar: name required', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('bazaar', %L, NULL, %L, %L, 1000, 1)$q$, st, m2, m2));
  PERFORM pg_temp.ok(r->>'code' = 'bad_bazaar', 'bazaar: a store is not a bazaar', r->>'code');

  -- ── list + totals ──
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_list(%s)$q$, extract(year FROM m1)::int));
  PERFORM pg_temp.ok(r->'items' @> jsonb_build_array(jsonb_build_object('place', 'ZZ Hist Tienda', 'amount', 120000))
      AND r->'stores' @> jsonb_build_array(jsonb_build_object('name', 'ZZ Hist Tienda')) AND r->'bazaars' @> jsonb_build_array(jsonb_build_object('name', 'ZZ Hist Bazar'))
      AND r->'total'->>'currency' = 'MXN', 'list: loads + places to choose + MXN totals', left((r->'total')::text, 80));

  -- ── void + correct ──
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_void(%L, '')$q$, id1));
  PERFORM pg_temp.ok(r->>'code' = 'bad_reason', 'void: a reason is required', r->>'code');
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_void(%L, 'el monto era 125 mil')$q$, id1));
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND NOT EXISTS (SELECT 1 FROM f360.historical_sales_active WHERE id = id1), 'void: it leaves the totals', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 125000, 50)$q$, st, m1));
  PERFORM pg_temp.ok(r->>'ok' = 'true', 'correct: after voiding, the month can be loaded again', left(r::text, 60));
  SELECT count(*) INTO n FROM f360.historical_sales_log WHERE summary_id = id1;
  PERFORM pg_temp.ok(n = 2, 'audit: created + voided logged with a snapshot', n::text);
  BEGIN
    DELETE FROM f360.historical_sales_log WHERE summary_id = id1;
    PERFORM pg_temp.ok(false, 'audit: the log is append-only', 'deleted!');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'audit: the log is append-only', SQLERRM);
  END;

  -- ── permissions + no side effects ──
  r := pg_temp.as(s1, format($q$SELECT public.f360_hist_sales_save('store_month', %L, NULL, %L, NULL, 1000, 1)$q$, st, m2));
  PERFORM pg_temp.ok(r ? 'error', 'permission: a seller cannot load history', r->>'error');
  r := pg_temp.as(NULL, $q$SELECT public.f360_hist_sales_list()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'permission: anon cannot read it', r->>'error');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.inventory_balances WHERE location_id IN (st, bz) AND on_hand <> 0),
    'no side effects: no inventory at the loaded locations', 'ok');
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
