-- Fuxia 360 P2.3A (stock authority + Woo orders + reconciliation) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon, service_role;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon, service_role;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon, service_role;
CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon, service_role;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon, service_role;
-- Woo order payload builder (minimized shape the webhook handler sends)
CREATE FUNCTION pg_temp.order_json(p_id bigint, p_status text, p_mod text, p_lines jsonb, p_refunds jsonb DEFAULT '[]') RETURNS jsonb LANGUAGE sql AS
$$ SELECT jsonb_build_object('id', p_id, 'status', p_status, 'date_modified_gmt', p_mod, 'currency', 'MXN', 'refunds', p_refunds, 'line_items', p_lines) $$;
GRANT EXECUTE ON FUNCTION pg_temp.order_json(bigint, text, text, jsonb, jsonb) TO service_role;
CREATE FUNCTION pg_temp.bal(p_sku text) RETURNS int LANGUAGE sql AS $$
  SELECT coalesce((SELECT b.on_hand FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
    JOIN f360.sales_targets t ON t.key = 'woo_tx' AND t.fulfillment_location_id = b.location_id WHERE v.sku = p_sku), 0) $$;
GRANT EXECUTE ON FUNCTION pg_temp.bal(text) TO service_role;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true) \gset t_
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c1', 'viewer', 'Viewer de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'viewer', display_name = 'Viewer de prueba', granted_by = 'test (rolled back)';
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c2', 'operator', 'Operadora de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator', display_name = 'Operadora de prueba', granted_by = 'test (rolled back)';

-- Fixture: target woo_tx (Bodega CDMX), product ZZ Venta Prueba (Negro 36/37), linked to fake Woo ids, Negro 37 = 2
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; p jsonb; loc uuid; tid uuid; v36 uuid; v37 uuid;
BEGIN
  SELECT id INTO loc FROM f360.locations WHERE name = 'Bodega CDMX';
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('woo_tx', 'Prueba', 'http://localhost:9', loc, true) RETURNING id INTO tid;
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Venta Prueba', ARRAY['36','37'], '[{"name":"Negro"}]'::jsonb);
  RESET ROLE;
  v36 := (SELECT (x->>'id')::uuid FROM jsonb_array_elements(p->'colors'->0->'variants') x WHERE x->>'size' = '36');
  v37 := (SELECT (x->>'id')::uuid FROM jsonb_array_elements(p->'colors'->0->'variants') x WHERE x->>'size' = '37');
  INSERT INTO t_ids VALUES ('p', (p->>'id')::uuid), ('v36', v36), ('v37', v37), ('t', tid);
  -- this model is NOT sobre pedido (20261007001500): an order without stock must stay an oversell alert here
  UPDATE f360.products SET make_to_order = false WHERE id = (p->>'id')::uuid;
  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id) VALUES (tid, (p->>'id')::uuid, 9000);
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, last_pushed_stock) VALUES (tid, v36, 9036, 0), (tid, v37, 9037, 2);
  PERFORM pg_temp.as_user(u, 'authenticated');
  PERFORM public.f360_receive_inventory(gen_random_uuid(), loc, jsonb_build_array(jsonb_build_object('variant_id', v37, 'quantity', 2)), 'fixture');
  RESET ROLE;
END $$;

-- 1. Receipt at the fulfillment location of a linked variant → queued for push (trigger)
SELECT pg_temp.ok(EXISTS (SELECT 1 FROM f360.stock_sync_queue q JOIN t_ids i ON i.k = 'v37' AND q.variant_id = i.v), 'receipt queues a Woo stock push', '');

-- 2–7. Paid order → exactly one SALE; replays / duplicates / stale / unpaid do nothing more
DO $$
DECLARE r jsonb; line jsonb := '[{"id":501,"product_id":9000,"variation_id":9037,"sku":"F360-ZZ-VENTA-PRUEBA-NEGRO-37","quantity":1}]';
  ev int; ev2 int; lp int; ref text;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d1","topic":"order.updated"}', pg_temp.order_json(7001, 'processing', '2026-09-26T10:00:00', line));
  RESET ROLE;
  SELECT count(*) INTO ev FROM f360.inventory_events WHERE business_reference_id = 'woo_tx:7001' AND event_type = 'SALE';
  SELECT last_pushed_stock INTO lp FROM f360.woo_variant_links WHERE variant_id = (SELECT t_ids.v FROM t_ids WHERE k = 'v37');
  PERFORM pg_temp.ok(r->>'result' = 'applied' AND ev = 1 AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1, 'paid order → 1 SALE, Bodega 2 → 1', r::text);
  PERFORM pg_temp.ok(lp = 1, 'expected Woo stock follows the sale Woo already made (2 → 1)', lp::text);
  SELECT f360.event_json(id)->>'reference_id' INTO ref FROM f360.inventory_events WHERE business_reference_id = 'woo_tx:7001';
  PERFORM pg_temp.ok(ref = 'woo_tx:7001', 'history event carries the order reference', ref);

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d1","topic":"order.updated"}', pg_temp.order_json(7001, 'processing', '2026-09-26T10:00:00', line));
  RESET ROLE;
  PERFORM pg_temp.ok(r->>'result' = 'duplicate_delivery' AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1, 'exact same webhook again → no change', r->>'result');

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d2","topic":"order.updated"}', pg_temp.order_json(7001, 'processing', '2026-09-26T10:00:00', line));
  RESET ROLE;
  PERFORM pg_temp.ok(r->>'result' = 'duplicate' AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1, 'same order version, new delivery id → no change', r->>'result');

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d3","topic":"order.updated"}', pg_temp.order_json(7001, 'completed', '2026-09-26T11:00:00', line));
  RESET ROLE;
  SELECT count(*) INTO ev2 FROM f360.inventory_events WHERE business_reference_id = 'woo_tx:7001';
  PERFORM pg_temp.ok(r->>'result' = 'applied' AND ev2 = 1 AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1, 'processing → completed: the line is never sold twice', (r->'lines')::text);

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d0","topic":"order.updated"}', pg_temp.order_json(7001, 'pending', '2026-09-26T09:00:00', line));
  RESET ROLE;
  PERFORM pg_temp.ok(r->>'result' = 'stale' AND (SELECT woo_status FROM f360.woo_orders WHERE woo_order_id = 7001) = 'completed', 'older webhook arriving late (out of order) is ignored', r->>'result');

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"e1","topic":"order.created"}', pg_temp.order_json(7002, 'pending', '2026-09-26T10:00:00', line));
  RESET ROLE;
  PERFORM pg_temp.ok(r->>'result' = 'not_paid' AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1, 'unpaid (pending) order does not touch stock', r->>'result');
END $$;

-- 7b. Same delivery id for a DIFFERENT order (Woo reuses delivery ids within one second) → still processed
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d1","topic":"order.updated"}', pg_temp.order_json(7005, 'processing', '2026-09-26T10:00:00',
    '[{"id":801,"product_id":9000,"variation_id":9036,"sku":"F360-ZZ-VENTA-PRUEBA-NEGRO-36","quantity":1}]'));
  RESET ROLE;
  PERFORM pg_temp.ok(r->>'result' = 'applied', 'reused Woo delivery id on another order is NOT treated as a replay', r->>'result');
END $$;

-- 8–9. Cancellation / refund after sale → alert (DW4 pending), NO automatic restock
DO $$
DECLARE r jsonb; line jsonb := '[{"id":501,"product_id":9000,"variation_id":9037,"sku":"F360-ZZ-VENTA-PRUEBA-NEGRO-37","quantity":1}]';
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d4"}', pg_temp.order_json(7001, 'completed', '2026-09-26T12:00:00', line, '[{"id":88,"total":"-1400"}]'));
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"d5"}', pg_temp.order_json(7001, 'cancelled', '2026-09-26T13:00:00', line, '[{"id":88,"total":"-1400"}]'));
  RESET ROLE;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'refund_after_sale' AND woo_order_id = 7001 AND status = 'open'), 'refund after sale → alert "decisión pendiente"', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'cancel_after_sale' AND woo_order_id = 7001) AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1,
    'cancellation after sale → alert, stock NOT returned automatically', pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37')::text);
END $$;

-- 10–13. Unknown F360 SKU, legacy, SKU mismatch, oversell (never negative)
DO $$
DECLARE r jsonb;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"f1"}', pg_temp.order_json(7003, 'processing', '2026-09-26T10:00:00',
    '[{"id":601,"product_id":555,"variation_id":556,"sku":"F360-NO-EXISTE-NEGRO-37","quantity":1},
      {"id":602,"product_id":129,"variation_id":130,"sku":"SUE-CUCARRON-TPE-1","quantity":1},
      {"id":603,"product_id":9000,"variation_id":9037,"sku":"OTRO-SKU","quantity":1}]'));
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT outcome FROM f360.woo_order_lines WHERE woo_line_id = 601) = 'unknown_sku'
    AND EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'unknown_sku' AND woo_order_id = 7003), 'unknown F360 SKU → alert, no stock change', '');
  PERFORM pg_temp.ok((SELECT outcome FROM f360.woo_order_lines WHERE woo_line_id = 602) = 'legacy'
    AND NOT EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE detail->>'sku' = 'SUE-CUCARRON-TPE-1'), 'legacy (non-F360) product line → ignored, no alert', '');
  PERFORM pg_temp.ok((SELECT outcome FROM f360.woo_order_lines WHERE woo_line_id = 603) = 'sku_mismatch' AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1,
    'variation id with a different SKU → alert, no stock change', '');

  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_ingest_woo_order('woo_tx', '{"delivery_id":"g1"}', pg_temp.order_json(7004, 'processing', '2026-09-26T10:00:00',
    '[{"id":701,"product_id":9000,"variation_id":9037,"sku":"F360-ZZ-VENTA-PRUEBA-NEGRO-37","quantity":3}]'));
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT outcome FROM f360.woo_order_lines WHERE woo_line_id = 701) = 'oversold' AND pg_temp.bal('F360-ZZ-VENTA-PRUEBA-NEGRO-37') = 1
    AND EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'oversell' AND woo_order_id = 7004 AND message LIKE '%sin existencia%'),
    'oversell (asks 3, has 1) → alert, stock stays 1 (never negative)', '');
END $$;

-- 14–17. Stock push worker: claim, success removes, failure backs off, 3 failures → alert, success auto-resolves
DO $$
DECLARE c jsonb; r jsonb; v uuid := (SELECT t_ids.v FROM t_ids WHERE k = 'v37'); cl text; att int;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  c := public.f360_sync_claim_stock('woo_tx', 50);
  RESET ROLE;
  cl := (SELECT x->>'claimed_at' FROM jsonb_array_elements(c) x WHERE (x->>'variant_id')::uuid = v);
  PERFORM pg_temp.ok(cl IS NOT NULL AND (SELECT (x->>'ats')::int FROM jsonb_array_elements(c) x WHERE (x->>'variant_id')::uuid = v) = 1,
    'worker claims the queued variant with ATS = Bodega (1)', c::text);
  FOR att IN 1..3 LOOP
    UPDATE f360.stock_sync_queue SET next_attempt_at = now(), claimed_at = NULL WHERE variant_id = v;
    PERFORM pg_temp.as_user(NULL, 'service_role');
    PERFORM public.f360_sync_stock_result('woo_tx', jsonb_build_array(jsonb_build_object('variant_id', v, 'claimed_at', now(), 'ok', false, 'error', 'timeout')));
    RESET ROLE;
  END LOOP;
  PERFORM pg_temp.ok((SELECT attempts FROM f360.stock_sync_queue WHERE variant_id = v) = 3 AND (SELECT next_attempt_at > now() FROM f360.stock_sync_queue WHERE variant_id = v)
    AND EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'push_failed' AND variant_id = v AND status = 'open'), '3 failed pushes → backoff + alert', '');
  PERFORM pg_temp.as_user(NULL, 'service_role');
  PERFORM public.f360_sync_stock_result('woo_tx', jsonb_build_array(jsonb_build_object('variant_id', v, 'claimed_at', clock_timestamp(), 'ok', true, 'ats', 1, 'expected', 1, 'woo_before', 1, 'pushed', 1)));
  RESET ROLE;
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v)
    AND EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'push_failed' AND variant_id = v AND status = 'resolved' AND resolved_by_name = 'Automático'),
    'successful push empties the queue and auto-resolves the alert', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.stock_sync_log WHERE variant_id = v) = 4, 'every push attempt is logged', '');
END $$;

-- 18–19. Reconciliation: drift → alert + push queued; in sync → auto-resolved
DO $$
DECLARE s jsonb; v uuid := (SELECT t_ids.v FROM t_ids WHERE k = 'v37'); v36 uuid := (SELECT t_ids.v FROM t_ids WHERE k = 'v36'); r jsonb;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  s := public.f360_reconcile_snapshot('woo_tx');
  r := public.f360_reconcile_finish('woo_tx', jsonb_build_object('requested_by_name', 'Prueba', 'items', jsonb_build_array(
    jsonb_build_object('variant_id', v, 'sku', 'x', 'label', 'ZZ Venta Prueba · Negro · 37', 'ats', 1, 'woo_stock', 3, 'state', 'drift'),
    jsonb_build_object('variant_id', v36, 'sku', 'y', 'label', 'ZZ · 36', 'ats', 0, 'woo_stock', 0, 'state', 'in_sync'))));
  RESET ROLE;
  PERFORM pg_temp.ok(jsonb_array_length(s) = 2 AND (r->>'drifted')::int = 1 AND (r->>'in_sync')::int = 1
    AND EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'stock_drift' AND variant_id = v AND status = 'open')
    AND EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v), 'reconciliation: drift → alert + correction queued', r::text);
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.f360_reconcile_finish('woo_tx', jsonb_build_object('items', jsonb_build_array(jsonb_build_object('variant_id', v, 'ats', 1, 'woo_stock', 1, 'state', 'in_sync'))));
  RESET ROLE;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.sync_exceptions WHERE kind = 'stock_drift' AND variant_id = v AND status = 'resolved'), 'next reconciliation in sync → alert auto-resolved', '');
END $$;

-- 20–24. Permissions + operator resolution
DO $$
DECLARE err text; l jsonb; ex uuid;
BEGIN
  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_ingest_woo_order('woo_tx', '{}', pg_temp.order_json(1, 'processing', '2026-09-26T10:00:00', '[]')); err := 'accepted';
  EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'a logged-in user (even owner) cannot inject orders', err);
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_list_sync_issues(); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot read alerts', err);
  SELECT id INTO ex FROM f360.sync_exceptions WHERE kind = 'oversell' AND woo_order_id = 7004;   -- as table owner
  PERFORM pg_temp.as_user(current_setting('t.c1')::uuid, 'authenticated');
  l := public.f360_list_sync_issues();
  BEGIN PERFORM public.f360_resolve_sync_issue(ex, 'ok'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok((l->>'open_count')::int >= 4 AND err <> 'accepted', 'viewer sees alerts but cannot resolve them', l->>'open_count');
  PERFORM pg_temp.as_user(current_setting('t.c2')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_resolve_sync_issue(ex, '  '); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM public.f360_resolve_sync_issue(ex, 'Se surtió desde producción');
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted' AND (SELECT status = 'resolved' AND resolved_by_name = 'Operadora de prueba' FROM f360.sync_exceptions WHERE id = ex),
    'operator resolves with a mandatory note; who/when recorded', '');
  BEGIN UPDATE f360.woo_webhook_deliveries SET result = 'x'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'webhook delivery log is append-only', err);
END $$;

-- 25. No customer data columns exist in the order tables
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'f360' AND table_name IN ('woo_orders', 'woo_order_lines', 'woo_webhook_deliveries')
  AND column_name ~ '(email|phone|name|address|billing|shipping|customer)'), 'order tables store no customer PII', '');

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
