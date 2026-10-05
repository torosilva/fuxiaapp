-- Test store (staging4) — its orders never touch real inventory. One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;

DO $$
DECLARE t f360.sales_targets; vl f360.woo_variant_links; r jsonb; bal_before int; bal_after int; ev_before int; ev_after int;
  ord jsonb;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = 'woo_staging4';
  PERFORM pg_temp.ok(t.is_test, 'staging4 is marked as a TEST store', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE is_production AND is_test), 'no production store is marked test', '');
  SELECT * INTO vl FROM f360.woo_variant_links WHERE target_id = t.id ORDER BY woo_variation_id LIMIT 1;
  INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) VALUES (vl.variant_id, t.fulfillment_location_id, 0) ON CONFLICT DO NOTHING;
  SELECT on_hand INTO bal_before FROM f360.inventory_balances WHERE variant_id = vl.variant_id AND location_id = t.fulfillment_location_id;
  SELECT count(*) INTO ev_before FROM f360.inventory_events;
  ord := jsonb_build_object('id', 990777, 'status', 'processing', 'date_modified_gmt', '2026-10-05T12:00:00', 'currency', 'MXN',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', vl.woo_product_id, 'variation_id', vl.woo_variation_id, 'sku', 'X', 'quantity', 1)));
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-test-1","topic":"order.updated"}', ord);
  SELECT on_hand INTO bal_after FROM f360.inventory_balances WHERE variant_id = vl.variant_id AND location_id = t.fulfillment_location_id;
  SELECT count(*) INTO ev_after FROM f360.inventory_events;
  PERFORM pg_temp.ok(r->>'result' = 'test_order' AND r->'lines'->0->>'outcome' = 'test', 'a paid order on the test store is recorded as test', r::text);
  PERFORM pg_temp.ok(bal_after = bal_before AND ev_after = ev_before, 'no inventory event, balance unchanged', bal_before || '→' || bal_after);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.woo_order_lines WHERE target_id = t.id AND woo_order_id = 990777 AND outcome = 'test' AND variant_id = vl.variant_id AND sale_event_id IS NULL),
    'the line keeps the variant (for testing) without a sale event', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.online_store_shipments WHERE woo_order_id = 990777) AND NOT EXISTS (SELECT 1 FROM f360.made_to_order WHERE woo_order_id = 990777),
    'no store shipment and no made-to-order task', '');
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-test-2","topic":"order.updated"}', ord);
  PERFORM pg_temp.ok(r->>'result' = 'duplicate', 'the same order again is a duplicate', r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.made_to_order m WHERE m.target_id = t.id AND m.status IN ('pendiente', 'en_proceso')),
    'test made-to-order tasks of staging4 are closed (#4114)', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
