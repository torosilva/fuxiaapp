-- Fuxia 360 G1-B Commerce Facts — database tests (STAGING). One transaction, ROLLED BACK. Synthetic fixtures only
-- (order ids 99100xxxxx, dates in 2099 so the summary can isolate them from the backfilled staging4 orders).
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
-- base Woo order (economics payload as built by commerce.ts), MXN 2800, one line, paid when the status says so
CREATE FUNCTION pg_temp.o(p_id bigint, p_status text, p_cur text, p_mod text, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', p_id, 'status', p_status, 'created_via', 'store-api', 'currency', p_cur, 'prices_include_tax', false,
    'date_created_gmt', '2099-01-05T10:00:00',
    'date_paid_gmt', CASE WHEN p_status IN ('processing', 'completed', 'refunded') THEN '2099-01-05T10:05:00' END,
    'date_completed_gmt', NULL, 'date_modified_gmt', p_mod,
    'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0', 'cart_tax', '0', 'total', '2800', 'total_tax', '0',
    'fees_total', 0, 'fees_tax', 0, 'coupon_count', 0, 'payment_method', 'woo-mercado-pago-custom', 'woo_customer_id', NULL, 'billing_country', 'MX',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 100, 'variation_id', 101, 'sku', 'ZZ-G1', 'quantity', 1,
      'subtotal', '2800', 'subtotal_tax', '0', 'total', '2800', 'total_tax', '0')),
    'refunds', '[]'::jsonb, 'attribution', NULL) || p_extra $$;
CREATE FUNCTION pg_temp.cap(p jsonb, p_via text DEFAULT 'test') RETURNS jsonb LANGUAGE sql AS
$$ SELECT public.f360_capture_order_economics('woo_staging4', p, p_via) $$;
CREATE FUNCTION pg_temp.fact(p_id bigint) RETURNS f360.commerce_orders LANGUAGE sql AS
$$ SELECT * FROM f360.commerce_orders WHERE source_system = 'woo' AND woo_order_id = p_id $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS c3 FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
  (:'c1', 'operator', 'ZZ Operadora', 'g1 test (rolled back)'), (:'c2', 'seller', 'ZZ Vendedora', 'g1 test (rolled back)'), (:'c3', 'viewer', 'ZZ Consulta', 'g1 test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name, granted_by = EXCLUDED.granted_by;
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.c3', :'c3', true) \gset t_

DO $$
DECLARE r jsonb; r2 jsonb; f f360.commerce_orders; n int; inv0 int; wo0 int; wl0 int; s jsonb; g jsonb;
  car uuid := current_setting('t.carolina')::uuid; op uuid := current_setting('t.c1')::uuid; sel uuid := current_setting('t.c2')::uuid; vw uuid := current_setting('t.c3')::uuid;
BEGIN
  SELECT count(*) INTO inv0 FROM f360.inventory_events; SELECT count(*) INTO wo0 FROM f360.woo_orders; SELECT count(*) INTO wl0 FROM f360.woo_order_lines;

  -- ── states ──
  r := pg_temp.cap(pg_temp.o(9910000001, 'processing', 'MXN', '2099-01-05T10:06:00'));
  f := pg_temp.fact(9910000001);
  PERFORM pg_temp.ok(r->>'result' = 'inserted' AND f.status_class = 'countable' AND f.payment_state = 'paid' AND f.paid_at IS NOT NULL AND f.data_quality = 'VERIFIED',
    'paid processing → countable, paid, VERIFIED', r::text);
  r := pg_temp.cap(pg_temp.o(9910000001, 'completed', 'MXN', '2099-01-06T10:00:00', '{"date_completed_gmt":"2099-01-06T10:00:00"}'));
  SELECT count(*) INTO n FROM f360.commerce_woo_orders WHERE woo_order_id = 9910000001;
  PERFORM pg_temp.ok(r->>'result' = 'updated' AND n = 1 AND (pg_temp.fact(9910000001)).status = 'completed'
    AND (SELECT count(*) FROM f360.commerce_woo_status_log WHERE woo_order_id = 9910000001) = 2,
    'processing → completed updates the SAME fact (1 row, 2 status log entries)', r::text);
  r := pg_temp.cap(pg_temp.o(9910000002, 'pending', 'MXN', '2099-01-05T10:06:00'));
  f := pg_temp.fact(9910000002);
  PERFORM pg_temp.ok(f.status_class = 'pending_payment' AND f.payment_state = 'never_paid', 'pending → pending_payment, never paid', f.status_class);
  r := pg_temp.cap(pg_temp.o(9910000003, 'on-hold', 'MXN', '2099-01-05T10:06:00'));
  PERFORM pg_temp.ok((pg_temp.fact(9910000003)).status_class = 'pending_payment', 'on-hold → pending_payment (not a sale)', '');
  r := pg_temp.cap(pg_temp.o(9910000004, 'failed', 'MXN', '2099-01-05T10:06:00'));
  f := pg_temp.fact(9910000004);
  PERFORM pg_temp.ok(f.status_class = 'not_paid' AND f.payment_state = 'never_paid', 'failed → not_paid, never paid', f.status_class);
  r := pg_temp.cap(pg_temp.o(9910000005, 'cancelled', 'MXN', '2099-01-05T10:06:00'));
  f := pg_temp.fact(9910000005);
  PERFORM pg_temp.ok(f.status_class = 'cancelled' AND f.payment_state = 'never_paid', 'cancelled unpaid → cancelled, never paid', f.status_class);

  -- paid → cancelled (total edited to 0, like DQ-02): never counted as current revenue, never deleted, sale kept
  r := pg_temp.cap(pg_temp.o(9910000006, 'completed', 'MXN', '2099-01-05T10:06:00'));
  r := pg_temp.cap(pg_temp.o(9910000006, 'cancelled', 'MXN', '2099-01-07T10:00:00', jsonb_build_object('total', '0', 'date_paid_gmt', '2099-01-05T10:05:00',
         'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 100, 'variation_id', 101, 'sku', 'ZZ-G1', 'quantity', 1, 'subtotal', '0', 'subtotal_tax', '0', 'total', '0', 'total_tax', '0')))));
  f := pg_temp.fact(9910000006);
  PERFORM pg_temp.ok(f.status_class = 'reversed' AND f.payment_state = 'paid_cancelled' AND f.paid_order_total = 2800 AND f.order_total = 0
    AND (SELECT string_agg(coalesce(from_status, '∅') || '→' || to_status, ',' ORDER BY id) FROM f360.commerce_woo_status_log WHERE woo_order_id = 9910000006) = '∅→completed,completed→cancelled',
    'paid → cancelled: reversed, paid_cancelled, keeps the paid snapshot 2800, history kept', format('%s %s %s', f.status_class, f.payment_state, f.paid_order_total));

  -- paid → cancelled first seen ALREADY cancelled (backfill of an order edited to 0): no paid value → PARTIAL, reason recorded
  r := pg_temp.cap(pg_temp.o(9910000007, 'cancelled', 'MXN', '2099-01-07T10:00:00', '{"total":"0","date_paid_gmt":"2099-01-05T10:05:00","line_items":[{"id":1,"quantity":1,"subtotal":"0","subtotal_tax":"0","total":"0","total_tax":"0"}]}'), 'backfill');
  f := pg_temp.fact(9910000007);
  PERFORM pg_temp.ok(f.payment_state = 'paid_cancelled' AND f.paid_order_total IS NULL AND f.data_quality = 'PARTIAL' AND 'paid_value_unknown' = ANY (f.data_quality_reasons),
    'paid → cancelled without a paid snapshot → PARTIAL (paid_value_unknown), never VERIFIED', f.data_quality);

  -- ── money semantics ──
  -- coupon 10% + implicit WDR price (3200 → 2800) + paid shipping 200 + fee 50 (+8 tax)
  r := pg_temp.cap(pg_temp.o(9910000010, 'completed', 'MXN', '2099-01-05T10:06:00', jsonb_build_object(
         'discount_total', '280', 'shipping_total', '200', 'fees_total', 50, 'fees_tax', 8, 'coupon_count', 1, 'total', '2778',
         'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 100, 'variation_id', 101, 'sku', 'ZZ-G1', 'quantity', 1,
           'subtotal', '2800', 'subtotal_tax', '0', 'total', '2520', 'total_tax', '0', 'list_price_hint', 3200, 'list_price_source', 'wdr_initial_price')))));
  f := pg_temp.fact(9910000010);
  PERFORM pg_temp.ok(f.product_gross = 2800 AND f.discount = 280 AND f.product_net = 2520, 'coupon: gross 2800 − discount 280 = product sales 2520', format('%s %s %s', f.product_gross, f.discount, f.product_net));
  PERFORM pg_temp.ok(f.shipping = 200 AND f.fees = 58 AND f.order_total = 2778 AND f.data_quality = 'VERIFIED', 'shipping + fees: total 2778 = 2520 + 200 + 50 + 8, VERIFIED', f.data_quality);
  PERFORM pg_temp.ok((SELECT list_price_hint = 3200 AND list_price_source = 'wdr_initial_price' FROM f360.commerce_woo_order_lines WHERE woo_order_id = 9910000010)
    AND f.product_gross = 2800, 'WDR implicit discount: kept only as a secondary hint (3200); revenue is NOT rebuilt from it', '');
  -- totals that do not reconcile → UNVERIFIED with the reason
  r := pg_temp.cap(pg_temp.o(9910000011, 'completed', 'MXN', '2099-01-05T10:06:00', '{"total":"9999"}'));
  f := pg_temp.fact(9910000011);
  PERFORM pg_temp.ok(f.data_quality = 'UNVERIFIED' AND 'total_does_not_reconcile' = ANY (f.data_quality_reasons), 'non-reconciling totals → UNVERIFIED (reason recorded)', f.data_quality);

  -- ── refunds ──
  r := pg_temp.cap(pg_temp.o(9910000020, 'completed', 'MXN', '2099-01-05T10:06:00', jsonb_build_object('refunds', jsonb_build_array(
         jsonb_build_object('id', 7001, 'amount', 500, 'created_at', '2099-01-08T10:00:00', 'detail', true, 'product_amount', 500, 'shipping_amount', 0, 'tax_amount', 0,
           'lines', jsonb_build_array(jsonb_build_object('woo_line_id', 1, 'quantity', 0, 'total', 500, 'total_tax', 0)))))));
  f := pg_temp.fact(9910000020);
  PERFORM pg_temp.ok(f.payment_state = 'paid_refunded_partial' AND f.refund_total = 500 AND f.net_product = 2300 AND f.status_class = 'countable' AND f.data_quality = 'VERIFIED',
    'refund partial: countable, 500 refunded, net product 2300', format('%s %s %s', f.payment_state, f.refund_total, f.net_product));
  r := pg_temp.cap(pg_temp.o(9910000020, 'completed', 'MXN', '2099-01-05T10:06:00', jsonb_build_object('refunds', jsonb_build_array(
         jsonb_build_object('id', 7001, 'amount', 500, 'detail', true, 'product_amount', 500, 'shipping_amount', 0, 'tax_amount', 0)))));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.commerce_woo_refunds WHERE woo_order_id = 9910000020) = 1 AND (pg_temp.fact(9910000020)).refund_total = 500,
    'same refund twice → 1 refund row (idempotent by refund id)', '');
  r := pg_temp.cap(pg_temp.o(9910000021, 'refunded', 'MXN', '2099-01-05T10:06:00', jsonb_build_object('refunds', jsonb_build_array(
         jsonb_build_object('id', 7002, 'amount', 2800, 'detail', true, 'product_amount', 2800, 'shipping_amount', 0, 'tax_amount', 0)))));
  f := pg_temp.fact(9910000021);
  PERFORM pg_temp.ok(f.payment_state = 'paid_refunded_full' AND f.status_class = 'countable' AND f.net_product = 0 AND f.product_net = 2800,
    'refund full: paid_refunded_full, gross kept, net 0', format('%s %s', f.payment_state, f.net_product));
  -- header-only refund → PARTIAL; detail later → VERIFIED; a later header-only payload never downgrades the detail
  r := pg_temp.cap(pg_temp.o(9910000022, 'completed', 'MXN', '2099-01-05T10:06:00', '{"refunds":[{"id":7003,"amount":300,"detail":false}]}'));
  f := pg_temp.fact(9910000022);
  PERFORM pg_temp.ok(f.data_quality = 'PARTIAL' AND 'refund_without_line_detail' = ANY (f.data_quality_reasons), 'header-only refund → PARTIAL', f.data_quality);
  r := pg_temp.cap(pg_temp.o(9910000022, 'completed', 'MXN', '2099-01-05T10:06:00', '{"refunds":[{"id":7003,"amount":300,"detail":true,"product_amount":300,"shipping_amount":0,"tax_amount":0}]}'));
  r := pg_temp.cap(pg_temp.o(9910000022, 'completed', 'MXN', '2099-01-05T10:06:00', '{"refunds":[{"id":7003,"amount":300,"detail":false}]}'));
  PERFORM pg_temp.ok((pg_temp.fact(9910000022)).data_quality = 'VERIFIED' AND (SELECT detail_status FROM f360.commerce_woo_refunds WHERE woo_refund_id = 7003) = 'detailed',
    'refund detail arrives → VERIFIED; header-only never downgrades it', '');
  -- a refund Woo no longer lists (deleted) is excluded, not deleted
  r := pg_temp.cap(pg_temp.o(9910000022, 'completed', 'MXN', '2099-01-09T10:00:00'));
  PERFORM pg_temp.ok((SELECT removed_at IS NOT NULL FROM f360.commerce_woo_refunds WHERE woo_refund_id = 7003) AND (pg_temp.fact(9910000022)).refund_total = 0,
    'refund removed in Woo → kept with removed_at, excluded from totals', '');

  -- ── currencies / markets ──
  r := pg_temp.cap(pg_temp.o(9910000030, 'completed', 'COP', '2099-01-05T10:06:00', '{"total":"425000","billing_country":"CO","line_items":[{"id":1,"quantity":1,"subtotal":"400000","subtotal_tax":"0","total":"400000","total_tax":"0"}],"shipping_total":"25000"}'));
  r := pg_temp.cap(pg_temp.o(9910000031, 'completed', 'USD', '2099-01-05T10:06:00', '{"total":"150","billing_country":"US","line_items":[{"id":1,"quantity":1,"subtotal":"150","subtotal_tax":"0","total":"150","total_tax":"0"}]}'));
  PERFORM pg_temp.ok((pg_temp.fact(9910000030)).market = 'CO' AND (pg_temp.fact(9910000030)).currency_original = 'COP'
    AND (pg_temp.fact(9910000031)).market = 'ROW' AND (pg_temp.fact(9910000001)).market = 'MX', 'MXN → MX, COP → CO, USD → ROW (original currency kept)', '');
  r := pg_temp.cap(pg_temp.o(9910000032, 'completed', 'COP', '2099-01-05T10:06:00', '{"total":"400000","line_items":[{"id":1,"quantity":1,"subtotal":"400000","subtotal_tax":"0","total":"400000","total_tax":"0"}],"attribution":{"source_type":"typein","session_entry_path":"/mx/tienda/"}}'));
  f := pg_temp.fact(9910000032);
  PERFORM pg_temp.ok(f.market = 'CO' AND f.data_quality = 'PARTIAL' AND 'market_conflict_currency_vs_path' = ANY (f.data_quality_reasons), 'currency vs landing path conflict → currency wins, PARTIAL', f.data_quality);

  -- ── attribution ──
  r := pg_temp.cap(pg_temp.o(9910000040, 'completed', 'MXN', '2099-01-05T10:06:00', '{"attribution":{"source_type":"utm","utm_source":"ig","utm_medium":"paid","utm_campaign":"120251089837130626","utm_id":"120251089837130626","utm_term":"120251089837100626","utm_content":"120251089837090626","referrer_host":"l.instagram.com","session_entry_path":"/mx/producto/paula/","session_start_at":"2099-01-05 09:55:00","session_pages":"7","session_count":"1","device_type":"Mobile","browser_class":"instagram_iab","os_class":"ios"}}'));
  PERFORM pg_temp.ok((SELECT provenance = 'first_party_observed' AND model = 'woo_order_attribution_last_click_session' AND utm_campaign = '120251089837130626'
      AND browser_class = 'instagram_iab' AND session_pages = 7 FROM f360.commerce_woo_attribution WHERE woo_order_id = 9910000040),
    'full attribution: first-party provenance, utm_campaign kept as an opaque value', '');
  r := pg_temp.cap(pg_temp.o(9910000040, 'completed', 'MXN', '2099-01-08T10:00:00', '{"attribution":{"source_type":"admin"}}'));
  PERFORM pg_temp.ok((SELECT source_type FROM f360.commerce_woo_attribution WHERE woo_order_id = 9910000040) = 'utm', 'attribution is immutable (a later wp-admin edit does not rewrite it)', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_woo_attribution WHERE woo_order_id = 9910000001) AND (pg_temp.fact(9910000001)).data_quality = 'VERIFIED',
    'missing attribution: no attribution row, the sale itself stays VERIFIED', '');

  -- ── origins ──
  r := pg_temp.cap(pg_temp.o(9910000050, 'processing', 'MXN', '2099-01-05T10:06:00', '{"created_via":"rest-api","payment_method":"f360_prueba"}'));
  r := pg_temp.cap(pg_temp.o(9910000051, 'processing', 'MXN', '2099-01-05T10:06:00', '{"created_via":"admin"}'));
  r := pg_temp.cap(pg_temp.o(9910000052, 'processing', 'MXN', '2099-01-05T10:06:00', '{"created_via":null}'));
  PERFORM pg_temp.ok((pg_temp.fact(9910000050)).business_origin = 'api_integration' AND (pg_temp.fact(9910000050)).payment_category = 'test'
    AND (pg_temp.fact(9910000051)).business_origin = 'manual_admin' AND (pg_temp.fact(9910000052)).business_origin = 'unknown'
    AND 'origin_unknown' = ANY ((pg_temp.fact(9910000052)).data_quality_reasons), 'API-created → api_integration; admin → manual_admin; unknown → PARTIAL', '');
  r := pg_temp.cap(pg_temp.o(9910000050, 'completed', 'MXN', '2099-01-06T10:06:00', '{"created_via":"admin"}'));
  PERFORM pg_temp.ok((pg_temp.fact(9910000050)).business_origin = 'api_integration' AND (pg_temp.fact(9910000050)).created_via = 'rest-api',
    'business origin and created_via are immutable after the first capture', '');

  -- ── idempotency ──
  r := pg_temp.cap(pg_temp.o(9910000060, 'completed', 'MXN', '2099-01-05T10:06:00'), 'webhook');
  r2 := pg_temp.cap(pg_temp.o(9910000060, 'completed', 'MXN', '2099-01-05T10:06:00'), 'webhook');
  PERFORM pg_temp.ok(r->>'result' = 'inserted' AND r2->>'result' = 'unchanged' AND (SELECT count(*) FROM f360.commerce_woo_orders WHERE woo_order_id = 9910000060) = 1
    AND (SELECT count(*) FROM f360.commerce_woo_order_lines WHERE woo_order_id = 9910000060) = 1, 'duplicate webhook → unchanged, one fact, one line', r2::text);
  r := pg_temp.cap(pg_temp.o(9910000061, 'completed', 'MXN', '2099-01-06T10:00:00'), 'webhook');
  r2 := pg_temp.cap(pg_temp.o(9910000061, 'processing', 'MXN', '2099-01-05T10:06:00'), 'webhook');
  PERFORM pg_temp.ok(r2->>'result' = 'stale' AND (pg_temp.fact(9910000061)).status = 'completed', 'out-of-order webhook (older version) → stale, newer state kept', r2::text);
  -- backfill twice over the same orders: same N facts, second pass all unchanged
  SELECT count(*) INTO n FROM f360.commerce_woo_orders;
  r := pg_temp.cap(pg_temp.o(9910000070, 'completed', 'MXN', '2099-01-05T10:06:00'), 'backfill');
  r := pg_temp.cap(pg_temp.o(9910000071, 'cancelled', 'COP', '2099-01-05T10:06:00'), 'backfill');
  r := pg_temp.cap(pg_temp.o(9910000072, 'completed', 'USD', '2099-01-05T10:06:00'), 'backfill');
  r := pg_temp.cap(pg_temp.o(9910000070, 'completed', 'MXN', '2099-01-05T10:06:00'), 'backfill');
  r2 := pg_temp.cap(pg_temp.o(9910000071, 'cancelled', 'COP', '2099-01-05T10:06:00'), 'backfill');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.commerce_woo_orders) = n + 3 AND r->>'result' = 'unchanged' AND r2->>'result' = 'unchanged',
    'backfill twice → first run N facts, second run the same N (unchanged)', '');

  -- ── inventory is never touched by commerce capture ──
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = inv0 AND (SELECT count(*) FROM f360.woo_orders) = wo0 AND (SELECT count(*) FROM f360.woo_order_lines) = wl0,
    'commerce capture never writes inventory_events, woo_orders or woo_order_lines', '');

  -- ── physical store sale: read from offline_sales, never copied ──
  INSERT INTO public.offline_sales (id, code, items, total, created_by_rpc, payment_method, created_at)
    VALUES ('00000000-0000-4000-a000-991000000001', 'ZZG1-1', '[]', 5600, true, 'cash', '2099-01-05 12:00:00-06');
  INSERT INTO public.offline_sale_items (sale_id, line_no, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
    VALUES ('00000000-0000-4000-a000-991000000001', 1, 'ZZ-G1', 'ZZ', '37', 'Negro', 2, 2800, 5600, 'product_master');
  SELECT * INTO f FROM f360.commerce_orders WHERE store_sale_id = '00000000-0000-4000-a000-991000000001';
  PERFORM pg_temp.ok(f.channel = 'store' AND f.business_origin = 'physical_store' AND f.currency_original = 'MXN' AND f.product_net = 5600 AND f.units = 2
    AND f.status_class = 'countable' AND f.data_quality = 'VERIFIED', 'store sale appears as a commerce fact (no copy), MXN, VERIFIED', format('%s %s', f.product_net, f.data_quality));

  -- ── summary: grouped by currency, never mixed; AOV_PRODUCT vs AVERAGE_ORDER_TOTAL ──
  s := pg_temp.as(op, $q$SELECT public.f360_commerce_summary('2099-01-01', '2099-12-31')$q$);
  PERFORM pg_temp.ok(NOT (s ? 'error') AND (SELECT count(DISTINCT x->>'currency') FROM jsonb_array_elements(s->'groups') x) = 3
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(s->'groups') x WHERE x->>'currency' IS NULL), 'summary groups by MXN / COP / USD separately (no mixed total)', left(s::text, 200));
  SELECT x INTO g FROM jsonb_array_elements(s->'groups') x WHERE x->>'currency' = 'MXN' AND x->>'origin' = 'storefront' AND x->>'channel' = 'online';
  PERFORM pg_temp.ok((g->>'aov_product')::numeric = round((g->>'product_sales')::numeric / (g->>'orders')::numeric, 2)
    AND (g->>'average_order_total')::numeric = round((g->>'order_total')::numeric / (g->>'orders')::numeric, 2)
    AND (g->>'aov_product')::numeric <> (g->>'average_order_total')::numeric, 'AOV_PRODUCT (no shipping) and AVERAGE_ORDER_TOTAL are separate', g::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(s->'groups') x WHERE (x->>'orders')::int > 0 AND x->>'currency' = 'MXN' AND x->>'origin' = 'storefront'
      AND (x->>'orders')::int <> (SELECT count(*) FROM f360.commerce_orders c WHERE c.currency_original = 'MXN' AND c.business_origin = 'storefront' AND c.status_class = 'countable'
                                   AND c.paid_at >= '2099-01-01' AND c.paid_at < '2100-01-01')),
    'summary counts only countable orders (pending / failed / cancelled / paid→cancelled excluded)', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(s->'not_counted') x WHERE x->>'payment_state' = 'paid_cancelled' AND (x->>'paid_order_total')::numeric >= 2800)
    AND s->>'kind' = 'ACTUAL' AND s->>'meta_purchase_signal' LIKE 'UNVERIFIED_CONFLICTED%', 'paid → cancelled visible as not counted with its paid value; ACTUAL; Meta signal flagged', '');

  -- ── freshness (STALE from the poll heartbeat, not from orders) ──
  DELETE FROM f360.commerce_sync_state WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  PERFORM pg_temp.ok((SELECT freshness FROM f360.commerce_source_health WHERE target_key = 'woo_staging4') = 'UNVERIFIED', 'never polled → UNVERIFIED', '');
  r := public.f360_commerce_run_begin('woo_staging4', 'poll');
  r2 := public.f360_commerce_run_end((r->>'run_id')::bigint, true, '{"fetched":0}', NULL, NULL);
  PERFORM pg_temp.ok((SELECT freshness FROM f360.commerce_source_health WHERE target_key = 'woo_staging4') = 'VERIFIED', 'successful poll with ZERO orders → fresh (VERIFIED)', '');
  UPDATE f360.commerce_sync_state SET last_success_at = now() - interval '2 hours' WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  r := public.f360_commerce_run_begin('woo_staging4', 'poll');
  r2 := public.f360_commerce_run_end((r->>'run_id')::bigint, false, '{}', 'Woo HTTP 503', NULL);
  PERFORM pg_temp.ok((SELECT freshness FROM f360.commerce_source_health WHERE target_key = 'woo_staging4') = 'STALE'
    AND (SELECT last_error FROM f360.commerce_sync_state WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4')) = 'Woo HTTP 503',
    'failed polls do not refresh: > 60 min without success → STALE', '');

  -- ── permissions ──
  PERFORM pg_temp.ok(NOT (pg_temp.as(car, $q$SELECT public.f360_commerce_summary()$q$) ? 'error'), 'owner reads the commerce summary', '');
  PERFORM pg_temp.ok(NOT (pg_temp.as(op, $q$SELECT public.f360_commerce_facts(5)$q$) ? 'error'), 'operator reads the technical facts list', '');
  PERFORM pg_temp.ok(pg_temp.as(sel, $q$SELECT public.f360_commerce_summary()$q$) ? 'error', 'seller cannot read commerce figures', '');
  PERFORM pg_temp.ok(pg_temp.as(vw, $q$SELECT public.f360_commerce_summary()$q$) ? 'error', 'viewer cannot read commerce figures', '');
  PERFORM pg_temp.ok(pg_temp.as(NULL, $q$SELECT public.f360_commerce_summary()$q$, 'anon') ? 'error', 'anon cannot read commerce figures', '');
  PERFORM pg_temp.ok(pg_temp.as(sel, $q$SELECT public.f360_growth_plan(2027)$q$) ? 'error' AND pg_temp.as(vw, $q$SELECT public.f360_growth_plan(2027)$q$) ? 'error'
    AND NOT (pg_temp.as(op, $q$SELECT public.f360_growth_plan(2027)$q$) ? 'error'), 'growth plan: seller / viewer denied, operator allowed (D-G1-05)', '');
  PERFORM pg_temp.ok(pg_temp.as(op, $q$SELECT to_jsonb(count(*)) FROM f360.commerce_orders$q$) ? 'error', 'no direct table/view access, even for an operator', '');
  PERFORM pg_temp.ok(pg_temp.as(car, $q$SELECT public.f360_capture_order_economics('woo_staging4', '{"id":1}', 'test')$q$) ? 'error', 'only the service can capture (owner denied)', '');
  r := NULL; BEGIN r := pg_temp.cap(pg_temp.o(9910000099, 'completed', 'MXN', '2099-01-05T10:06:00') - 'currency'); EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'incomplete order (no currency) refused', coalesce(r::text, ''));
  r := NULL; BEGIN r := public.f360_capture_order_economics('no_such_store', pg_temp.o(9910000098, 'completed', 'MXN', '2099-01-05T10:06:00'), 'test'); EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'unknown / production store refused (target_by_key guard)', coalesce(r::text, ''));
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
