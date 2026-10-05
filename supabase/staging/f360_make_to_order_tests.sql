-- "Sobre pedido" (Mario 2026-10-03) — database tests (STAGING). One transaction, ROLLED BACK.
-- Uses the staging4 target and an own model (fake Woo variation 308) with 0 pairs anywhere.
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
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; r jsonb; v uuid; pid uuid; bodega uuid; before_on int; n int; ord bigint := 990000001;
  order_json jsonb;
BEGIN
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Pedido', ARRAY['35'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pid;
  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id) SELECT id, pid, 991146 FROM f360.sales_targets WHERE key = 'woo_staging4';
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, last_pushed_stock) SELECT id, v, 308, 0 FROM f360.sales_targets WHERE key = 'woo_staging4';
  SELECT fulfillment_location_id INTO bodega FROM f360.sales_targets WHERE key = 'woo_staging4';
  PERFORM pg_temp.ok(v IS NOT NULL AND (SELECT make_to_order FROM f360.products WHERE id = pid), 'fixture: linked size at 0; models start as "sobre pedido"', '');

  -- the stock push tells Woo to keep it orderable
  DELETE FROM f360.stock_sync_queue; INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason) SELECT id, v, 'test' FROM f360.sales_targets WHERE key = 'woo_staging4';
  r := public.f360_sync_claim_stock('woo_staging4', 10);
  PERFORM pg_temp.ok(r->0->>'backorders' = 'notify' AND (r->0->>'ats')::int = 0, 'push: 0 pairs + backorders notify (orderable)', left(r::text, 120));

  -- a paid online order of that size: nothing moves, the line becomes "sobre pedido"
  order_json := jsonb_build_object('id', ord, 'status', 'processing', 'date_modified_gmt', '2026-10-03T18:00:00', 'currency', 'MXN',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 146, 'variation_id', 308, 'sku', (SELECT sku FROM f360.product_variants WHERE id = v), 'quantity', 1)), 'refunds', '[]'::jsonb);
  SELECT count(*) INTO n FROM f360.inventory_movements;
  r := public.f360_ingest_woo_order('woo_staging4', jsonb_build_object('delivery_id', 'test-mto-1', 'topic', 'order.updated'), order_json);
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sobre_pedido' AND (SELECT count(*) FROM f360.inventory_movements) = n
    AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = bodega) = 0, 'order at 0 → "sobre pedido", no inventory moved, never negative', r::text);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.made_to_order WHERE woo_order_id = ord AND variant_id = v AND status = 'pendiente' AND quantity = 1),
    'queued for the team as pending', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE woo_order_id = ord AND kind = 'oversell'), 'no oversell alert for a made-to-order line', '');
  r := public.f360_ingest_woo_order('woo_staging4', jsonb_build_object('delivery_id', 'test-mto-1b', 'topic', 'order.updated'),
    jsonb_set(order_json, '{date_modified_gmt}', '"2026-10-03T18:05:00"'));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.made_to_order WHERE woo_order_id = ord) = 1, 'the same order again does not queue twice', r::text);

  -- team list + status
  r := pg_temp.as(car, $q$SELECT public.f360_made_to_order_list()$q$);
  PERFORM pg_temp.ok(r->0->>'order' = ord::text AND r->0->>'size' IS NOT NULL
    AND (r->0->>'ship_by')::date = (SELECT d::date FROM generate_series(current_date + 1, current_date + 21, interval '1 day') d WHERE extract(isodow FROM d) < 6 OFFSET 9 LIMIT 1),
    'team sees it with its "ship by" date (10th business day, Mario 2026-10-04)', left(r::text, 160));
  r := pg_temp.as(car, format($q$SELECT public.f360_made_to_order_set(%L, 'en_proceso', 'Taller')$q$, (SELECT id FROM f360.made_to_order WHERE woo_order_id = ord)));
  PERFORM pg_temp.ok(r->>'status' = 'en_proceso', 'operator moves it to "en proceso"', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_made_to_order_list()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot read the list', r::text);

  -- turning it off: re-queues the model's sizes, push says 'no', a new order at 0 is an oversell alert again
  DELETE FROM f360.stock_sync_queue;
  r := pg_temp.as(car, format($q$SELECT public.f360_set_make_to_order(%L, false, 'Descontinuado')$q$, pid));
  PERFORM pg_temp.ok(r->>'make_to_order' = 'false' AND (SELECT count(*) FROM f360.stock_sync_queue WHERE variant_id IN (SELECT id FROM f360.product_variants WHERE product_id = pid)) > 0
    AND EXISTS (SELECT 1 FROM f360.catalog_changes WHERE product_id = pid AND what = 'make_to_order'), 'off → logged and every linked size re-sent to the store', r::text);
  r := public.f360_sync_claim_stock('woo_staging4', 50);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'backorders' <> 'no'), 'push: backorders no (blocked at 0)', left(r::text, 100));
  r := public.f360_ingest_woo_order('woo_staging4', jsonb_build_object('delivery_id', 'test-mto-2', 'topic', 'order.updated'),
    jsonb_set(jsonb_set(order_json, '{id}', to_jsonb(ord + 1)), '{line_items,0,id}', '2'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'oversold', 'off → an order at 0 is an oversell alert (as before)', r::text);
  r := pg_temp.as(NULL, format($q$SELECT public.f360_set_make_to_order(%L, true)$q$, pid), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot change it', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
