-- S-G0 Measurement Truth · D1 history import + D2 reconciliation + measurement health — database tests (STAGING ONLY).
-- One transaction, ALWAYS rolled back (ends with RAISE 'ENSAYO OK' = every check passed). Synthetic orders 9920xxxxxx
-- (dates in 2025-01, a month without staging data). Needs 20261014000100..600 applied.
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=0 -f supabase/staging/test_sg0_reconciliation.sql
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text DEFAULT '') RETURNS void LANGUAGE sql AS
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
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.o(p_id bigint, p_status text, p_mod text, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', p_id, 'status', p_status, 'created_via', 'store-api', 'currency', 'MXN', 'prices_include_tax', false,
    'date_created_gmt', '2025-01-02T16:00:00',
    'date_paid_gmt', CASE WHEN p_status IN ('processing', 'completed', 'refunded') THEN '2025-01-02T16:05:00' END,
    'date_completed_gmt', NULL, 'date_modified_gmt', p_mod,
    'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0', 'cart_tax', '0', 'total', '2800', 'total_tax', '0',
    'fees_total', 0, 'fees_tax', 0, 'coupon_count', 0, 'payment_method', 'woo-mercado-pago-custom', 'woo_customer_id', NULL, 'billing_country', 'MX',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 100, 'variation_id', 101, 'sku', 'ZZ-SG0', 'quantity', 1,
      'subtotal', '2800', 'subtotal_tax', '0', 'total', '2800', 'total_tax', '0')),
    'refunds', '[]'::jsonb, 'attribution', NULL) || p_extra $$;
CREATE FUNCTION pg_temp.cap(p jsonb, p_via text) RETURNS jsonb LANGUAGE sql AS
$$ SELECT public.f360_capture_order_economics('woo_staging4', p, p_via) $$;
CREATE FUNCTION pg_temp.src(p_key text) RETURNS jsonb LANGUAGE sql AS
$$ SELECT s FROM jsonb_array_elements(f360.sg0_source_health()) s WHERE s->>'key' = p_key $$;

SELECT auth_user_id AS owner FROM f360.user_roles WHERE role = 'owner' ORDER BY created_at LIMIT 1 \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS c3 FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
  (:'c1', 'operator', 'ZZ Operadora', 'sg0 test (rolled back)'), (:'c2', 'seller', 'ZZ Vendedora', 'sg0 test (rolled back)'), (:'c3', 'viewer', 'ZZ Consulta', 'sg0 test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name, granted_by = EXCLUDED.granted_by;
SELECT set_config('t.owner', :'owner', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.c3', :'c3', true) \gset t_

DO $$
DECLARE r jsonb; d jsonb; n int; inv0 int; wo0 int; ship0 int; tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  own uuid := current_setting('t.owner')::uuid; op uuid := current_setting('t.c1')::uuid; sel uuid := current_setting('t.c2')::uuid; vw uuid := current_setting('t.c3')::uuid;
  run jsonb; ms f360.measurement_sales;
BEGIN
  SELECT count(*) INTO inv0 FROM f360.inventory_events; SELECT count(*) INTO wo0 FROM f360.woo_orders;
  SELECT count(*) INTO ship0 FROM information_schema.tables WHERE table_schema = 'f360' AND table_name = 'order_shipping';

  -- ── diff: missing / outdated / current ──
  PERFORM pg_temp.cap(pg_temp.o(9920000001, 'processing', '2025-01-02T16:06:00'), 'webhook');
  d := public.f360_commerce_reconcile_diff('woo_staging4', jsonb_build_array(
    jsonb_build_object('id', 9920000001, 'date_modified_gmt', '2025-01-02T16:06:00'),
    jsonb_build_object('id', 9920000002, 'date_modified_gmt', '2025-01-02T17:00:00'),
    jsonb_build_object('id', 9920000001, 'date_modified_gmt', '2025-01-02T16:06:00')));
  PERFORM pg_temp.ok(d->'missing' = '[9920000002]' AND d->'outdated' = '[]' AND (d->>'current')::int = 1, 'diff: known order is current, unknown order is missing (duplicates in the page collapse)', d::text);
  d := public.f360_commerce_reconcile_diff('woo_staging4', jsonb_build_array(jsonb_build_object('id', 9920000001, 'date_modified_gmt', '2025-01-03T10:00:00')));
  PERFORM pg_temp.ok(d->'outdated' = '[9920000001]', 'diff: Woo modified later than F360 → outdated', d::text);

  -- ── TEST 9 · reconciliation recovery is idempotent (SQL side): recover twice = one fact, second = unchanged ──
  r := pg_temp.cap(pg_temp.o(9920000002, 'completed', '2025-01-02T17:00:00'), 'poll');
  PERFORM pg_temp.ok(r->>'result' = 'inserted', 'TEST 9a · missing order recovered by the reconciliation (p_via=poll)', r::text);
  r := pg_temp.cap(pg_temp.o(9920000002, 'completed', '2025-01-02T17:00:00'), 'poll');
  SELECT count(*) INTO n FROM f360.commerce_woo_orders WHERE woo_order_id = 9920000002;
  PERFORM pg_temp.ok(r->>'result' = 'unchanged' AND n = 1, 'TEST 9 · reconciliation is idempotent (second capture unchanged, 1 row)', r::text);
  d := public.f360_commerce_reconcile_diff('woo_staging4', jsonb_build_array(jsonb_build_object('id', 9920000002, 'date_modified_gmt', '2025-01-02T17:00:00')));
  PERFORM pg_temp.ok(d->'missing' = '[]' AND (d->>'current')::int = 1, 'TEST 9b · after recovery the diff finds nothing missing', d::text);
  SELECT * INTO ms FROM f360.measurement_sales WHERE woo_order_id = 9920000002;
  PERFORM pg_temp.ok(ms.capture_source = 'woo_reconciliation_recovered' AND ms.timing_class = 'realtime' AND ms.imported_at IS NULL,
    'recovered order is labelled realtime / woo_reconciliation_recovered', ms.capture_source);

  -- ── TEST 11 · a duplicate Woo order cannot be created through webhook + reconciliation + history ──
  r := pg_temp.cap(pg_temp.o(9920000001, 'processing', '2025-01-02T16:06:00'), 'poll');
  r := pg_temp.cap(pg_temp.o(9920000001, 'processing', '2025-01-02T16:06:00'), 'backfill');
  SELECT count(*) INTO n FROM f360.commerce_woo_orders WHERE woo_order_id = 9920000001;
  PERFORM pg_temp.ok(n = 1 AND (SELECT first_captured_via FROM f360.commerce_woo_orders WHERE woo_order_id = 9920000001) = 'webhook'
    AND (SELECT count(*) FROM f360.measurement_sales WHERE woo_order_id = 9920000001) = 1,
    'TEST 11 · same order via webhook, poll and backfill = ONE fact; the first (realtime) source is kept', n::text);
  BEGIN
    INSERT INTO f360.commerce_woo_orders SELECT * FROM f360.commerce_woo_orders WHERE woo_order_id = 9920000001;
    PERFORM pg_temp.ok(false, 'TEST 11b · direct duplicate insert refused by the primary key');
  EXCEPTION WHEN unique_violation THEN PERFORM pg_temp.ok(true, 'TEST 11b · direct duplicate insert refused by the primary key (target, woo_order_id)');
  END;

  -- ── TEST 10 · history import is idempotent (SQL side) and labelled woo_history_import with imported_at ──
  r := pg_temp.cap(pg_temp.o(9920000003, 'completed', '2025-01-05T10:00:00'), 'backfill');
  r := pg_temp.cap(pg_temp.o(9920000003, 'completed', '2025-01-05T10:00:00'), 'backfill');
  SELECT * INTO ms FROM f360.measurement_sales WHERE woo_order_id = 9920000003;
  PERFORM pg_temp.ok(r->>'result' = 'unchanged' AND (SELECT count(*) FROM f360.commerce_woo_orders WHERE woo_order_id = 9920000003) = 1
    AND ms.capture_source = 'woo_history_import' AND ms.timing_class = 'historical_import' AND ms.imported_at IS NOT NULL AND ms.is_paid_sale,
    'TEST 10 · history import twice = one fact, unchanged, woo_history_import + imported_at', r::text || ' ' || ms.capture_source);
  r := pg_temp.cap(pg_temp.o(9920000003, 'completed', '2025-01-01T10:00:00'), 'backfill');
  PERFORM pg_temp.ok(r->>'result' = 'stale', 'history: an OLDER version never overwrites a newer one', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = inv0 AND (SELECT count(*) FROM f360.woo_orders) = wo0,
    'history / reconciliation captures never touch inventory (inventory_events, woo_orders unchanged)', '');

  -- ── run bookkeeping: reconcile run window and stats ──
  run := public.f360_commerce_reconcile_begin('woo_staging4', 48);
  PERFORM pg_temp.ok(run->>'mode' = 'deep' AND (run->>'modified_after')::timestamptz BETWEEN now() - interval '49 hours' AND now() - interval '47 hours', 'deep check: explicit lookback window', run::text);
  PERFORM public.f360_commerce_run_end((run->>'run_id')::bigint, true, '{"woo_seen":3,"current":1,"detected_missing":2,"recovered":2,"errors":0}', NULL, NULL);
  run := public.f360_commerce_reconcile_begin('woo_staging4', NULL);
  PERFORM pg_temp.ok(run->>'mode' = 'incremental', 'incremental run starts from the cursor', run::text);
  r := NULL; BEGIN r := public.f360_commerce_reconcile_begin('woo_staging4', 0); EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'lookback out of range refused', coalesce(r::text, ''));
  r := NULL; BEGIN r := public.f360_commerce_reconcile_diff('no_such_store', '[]'); EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'unknown channel refused by the order-path guard', coalesce(r::text, ''));
  PERFORM pg_temp.ok(pg_temp.as(own, $q$SELECT public.f360_commerce_reconcile_diff('woo_staging4', '[]')$q$) ? 'error'
    AND pg_temp.as(own, $q$SELECT public.f360_commerce_reconcile_begin('woo_staging4', NULL)$q$) ? 'error', 'reconciliation RPCs are service-role only (owner denied)', '');

  -- ── health: order reconciliation states (last run decides) ──
  PERFORM public.f360_commerce_run_end((run->>'run_id')::bigint, true, '{"woo_seen":1,"current":1,"detected_missing":0,"recovered":0,"errors":0}', NULL, NULL);
  PERFORM pg_temp.ok(pg_temp.src('order_reconciliation')->>'status' = 'HEALTHY', 'health: fresh successful reconciliation → HEALTHY', (pg_temp.src('order_reconciliation')->'reasons')::text);
  run := public.f360_commerce_reconcile_begin('woo_staging4', NULL);
  PERFORM public.f360_commerce_run_end((run->>'run_id')::bigint, true, '{"woo_seen":2,"current":0,"detected_missing":2,"recovered":1,"errors":1}', NULL, NULL);
  PERFORM pg_temp.ok(pg_temp.src('order_reconciliation')->>'status' = 'DEGRADED', 'health: a missing order not recovered → DEGRADED', (pg_temp.src('order_reconciliation')->'reasons')::text);
  PERFORM pg_temp.ok(pg_temp.src('woocommerce')->>'status' IN ('DEGRADED', 'ERROR') AND (pg_temp.src('woocommerce')->'reasons')::text LIKE '%recovered_last_24h%',
    'health: WooCommerce realtime capture DEGRADED when the reconciliation had to recover orders the webhook missed', (pg_temp.src('woocommerce')->'reasons')::text);
  run := public.f360_commerce_reconcile_begin('woo_staging4', NULL);
  PERFORM public.f360_commerce_run_end((run->>'run_id')::bigint, false, '{}', 'Woo HTTP 503', NULL);
  PERFORM pg_temp.ok(pg_temp.src('order_reconciliation')->>'status' = 'ERROR', 'health: last run failed → ERROR', (pg_temp.src('order_reconciliation')->'reasons')::text);
  UPDATE f360.commerce_sync_runs SET finished_at = now() - interval '3 hours', started_at = now() - interval '3 hours' WHERE target_id = tgt;
  run := public.f360_commerce_reconcile_begin('woo_staging4', NULL);       -- still running (not finished)
  PERFORM pg_temp.ok(pg_temp.src('order_reconciliation')->>'status' = 'STALE', 'health: no successful run in 60 min → STALE', (pg_temp.src('order_reconciliation')->'reasons')::text);
  PERFORM pg_temp.ok((pg_temp.src('ga4')->>'status') = 'NOT_CONFIGURED' AND (pg_temp.src('meta_ads')->>'status') = 'NOT_CONFIGURED'
    AND (pg_temp.src('google_ads')->>'status') = 'NOT_CONFIGURED', 'health: GA4 / Meta Ads / Google Ads without credentials → NOT_CONFIGURED', '');
  UPDATE f360.measurement_sources SET config_status = 'CONFIGURED' WHERE key = 'ga4';
  PERFORM pg_temp.ok(pg_temp.src('ga4')->'detail'->>'state' = 'CONFIGURED' AND pg_temp.src('ga4')->>'status' = 'DEGRADED', 'GA4 configured but never ran → state CONFIGURED (DEGRADED)', '');
  INSERT INTO f360.measurement_runs (source_key, started_at, finished_at, ok, rows) VALUES ('ga4', now() - interval '1 hour', now() - interval '59 minutes', true, 10);
  PERFORM pg_temp.ok(pg_temp.src('ga4')->>'status' = 'HEALTHY', 'GA4 successful run → HEALTHY', '');
  INSERT INTO f360.measurement_runs (source_key, started_at, finished_at, ok, error) VALUES ('ga4', now(), now(), false, 'quota');
  PERFORM pg_temp.ok(pg_temp.src('ga4')->>'status' = 'ERROR', 'GA4 failed run → ERROR', '');
  UPDATE f360.measurement_runs SET finished_at = now() - interval '3 days', started_at = now() - interval '3 days' WHERE source_key = 'ga4';
  DELETE FROM f360.measurement_runs WHERE source_key = 'ga4' AND NOT ok;
  PERFORM pg_temp.ok(pg_temp.src('ga4')->>'status' = 'STALE', 'GA4 last success > 36 h → STALE', '');

  -- ── production channel hidden unless its ORDER path is on ──
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_source_health h JOIN f360.sales_targets t ON t.key = h.target_key WHERE t.is_production AND coalesce(to_jsonb(t)->>'orders_mode', 'off') <> 'on'),
    'commerce_source_health shows a production channel only when orders_mode = on', '');

  -- ── permissions on the health / truth RPCs ──
  PERFORM pg_temp.ok(NOT (pg_temp.as(own, $q$SELECT public.f360_measurement_health()$q$) ? 'error') AND NOT (pg_temp.as(op, $q$SELECT public.f360_measurement_truth()$q$) ? 'error'),
    'owner / operator read measurement health and truth', '');
  PERFORM pg_temp.ok(pg_temp.as(sel, $q$SELECT public.f360_measurement_health()$q$) ? 'error' AND pg_temp.as(vw, $q$SELECT public.f360_measurement_truth()$q$) ? 'error'
    AND pg_temp.as(NULL, $q$SELECT public.f360_measurement_health()$q$, 'anon') ? 'error', 'seller / viewer / anon cannot read measurement health or truth', '');
  PERFORM pg_temp.ok(pg_temp.as(op, $q$SELECT to_jsonb(count(*)) FROM f360.measurement_sales$q$) ? 'error', 'no direct read of the measurement view', '');
  PERFORM pg_temp.ok(NOT (pg_temp.as(own, $q$SELECT public.f360_measurement_truth()$q$)::text ~* '(@fuxia|phone|email|street|\+52)'), 'truth payload carries no PII', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail, ''), 120) FROM t_results ORDER BY n;
DO $$ DECLARE f int := (SELECT count(*) FROM t_results WHERE status = 'FAIL'); p int := (SELECT count(*) FROM t_results WHERE status = 'PASS');
BEGIN IF f > 0 THEN RAISE EXCEPTION 'ENSAYO FALLÓ: % de % pruebas', f, f + p; END IF; RAISE EXCEPTION 'ENSAYO OK (% pruebas)', p; END $$;
ROLLBACK;
