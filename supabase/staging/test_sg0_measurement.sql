-- S-G0 Measurement Truth · revenue definitions (D6), currency / FX (D7), marketing spend (D3), efficiency KPIs, legacy store
-- sales (D8) and product cost versions (D5) — database tests (STAGING ONLY). One transaction, ALWAYS rolled back (ends with
-- RAISE 'ENSAYO OK'). Synthetic data only, all in 2025-01 (a month without staging data). Needs 20261014000100..600.
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=0 -f supabase/staging/test_sg0_measurement.sql
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
-- Woo economics payload (as commerce.ts builds it), paid on 2025-01-02 (CDMX)
CREATE FUNCTION pg_temp.o(p_id bigint, p_status text, p_cur text, p_total numeric, p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', p_id, 'status', p_status, 'created_via', 'store-api', 'currency', p_cur, 'prices_include_tax', false,
    'date_created_gmt', '2025-01-02T16:00:00',
    'date_paid_gmt', CASE WHEN p_status IN ('processing', 'completed', 'refunded') THEN '2025-01-02T16:05:00' END,
    'date_completed_gmt', NULL, 'date_modified_gmt', '2025-01-02T16:06:00',
    'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0', 'cart_tax', '0', 'total', p_total::text, 'total_tax', '0',
    'fees_total', 0, 'fees_tax', 0, 'coupon_count', 0, 'payment_method', 'woo-mercado-pago-custom', 'woo_customer_id', NULL, 'billing_country', 'MX',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 100, 'variation_id', 101, 'sku', 'ZZ-SG0', 'quantity', 1,
      'subtotal', p_total::text, 'subtotal_tax', '0', 'total', p_total::text, 'total_tax', '0')),
    'refunds', '[]'::jsonb, 'attribution', NULL) || p_extra $$;
CREATE FUNCTION pg_temp.cap(p jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT public.f360_capture_order_economics('woo_staging4', p, 'webhook') $$;
CREATE FUNCTION pg_temp.ms(p_id bigint) RETURNS f360.measurement_sales LANGUAGE sql AS $$ SELECT * FROM f360.measurement_sales WHERE woo_order_id = p_id $$;
CREATE FUNCTION pg_temp.truth() RETURNS jsonb LANGUAGE plpgsql AS $$          -- read as the owner (the RPC requires operator+)
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', current_setting('t.owner'), 'role', 'authenticated')::text, true);
  RETURN public.f360_measurement_truth('2025-01-01', '2025-01-03');
END $$;
CREATE FUNCTION pg_temp.spend_row(p_date text, p_spend text, p_cur text DEFAULT 'MXN', p_extra jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('date', p_date, 'market', 'MX', 'platform', 'meta', 'account_id', 'act_123', 'campaign_id', '120001', 'campaign_name', 'Lanzamiento Paula',
    'adset_id', '220001', 'adset_name', 'MX mujeres', 'ad_id', '320001', 'ad_name', 'Video 1', 'creative_id', '420001', 'currency', p_cur,
    'spend', p_spend, 'impressions', '1000', 'clicks', '20') || p_extra $$;

SELECT auth_user_id AS owner FROM f360.user_roles WHERE role = 'owner' ORDER BY created_at LIMIT 1 \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
  (:'c1', 'operator', 'ZZ Operadora', 'sg0 test (rolled back)'), (:'c2', 'seller', 'ZZ Vendedora', 'sg0 test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = EXCLUDED.role, display_name = EXCLUDED.display_name, granted_by = EXCLUDED.granted_by;
SELECT set_config('t.owner', :'owner', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true) \gset t_

DO $$
DECLARE r jsonb; t jsonb; k jsonb; m f360.measurement_sales; n int; co0 int; id1 uuid; id2 uuid; id3 uuid; v_prod uuid; v_var uuid; s1 uuid; s2 uuid;
  own uuid := current_setting('t.owner')::uuid; op uuid := current_setting('t.c1')::uuid; sel uuid := current_setting('t.c2')::uuid;
BEGIN
  -- ═════ D6 revenue + TEST 12 / 13 ═════
  PERFORM pg_temp.cap(pg_temp.o(9930000001, 'completed', 'MXN', 2800, '{"discount_total":"280","shipping_total":"150","total":"2670","line_items":[{"id":1,"product_id":100,"variation_id":101,"sku":"ZZ","quantity":1,"subtotal":"2800","subtotal_tax":"0","total":"2520","total_tax":"0"}]}'));
  m := pg_temp.ms(9930000001);
  PERFORM pg_temp.ok(m.is_paid_sale AND m.gross_merchandise_value = 2800 AND m.discounts = 280 AND m.product_net = 2520 AND m.shipping_charged = 150
    AND m.net_product_revenue = 2520 AND m.total_collected = 2670 AND m.tax_iva = 0 AND m.iva_treatment = 'included_not_separated' AND m.product_net_before_tax IS NULL,
    'D6 · GMV 2800 − coupon 280 = product net 2520; shipping 150 apart; total collected 2670; IVA not separated → product_net_before_tax NULL',
    format('%s %s %s %s %s', m.gross_merchandise_value, m.discounts, m.net_product_revenue, m.total_collected, m.iva_treatment));
  PERFORM pg_temp.cap(pg_temp.o(9930000002, 'cancelled', 'MXN', 5000));                                    -- never paid
  PERFORM pg_temp.cap(pg_temp.o(9930000003, 'processing', 'MXN', 4000));                                   -- paid …
  PERFORM pg_temp.cap(pg_temp.o(9930000003, 'cancelled', 'MXN', 4000, '{"date_modified_gmt":"2025-01-02T18:00:00"}'));   -- … then cancelled
  PERFORM pg_temp.cap(pg_temp.o(9930000004, 'pending', 'MXN', 3000));
  PERFORM pg_temp.ok(NOT (pg_temp.ms(9930000002)).is_paid_sale AND (pg_temp.ms(9930000002)).status_class = 'cancelled'
    AND NOT (pg_temp.ms(9930000003)).is_paid_sale AND (pg_temp.ms(9930000003)).status_class = 'reversed' AND NOT (pg_temp.ms(9930000004)).is_paid_sale,
    'TEST 12 · cancelled (never paid / paid→cancelled) and pending orders are NOT paid sales', '');
  -- full refund (detailed) and partial refund
  PERFORM pg_temp.cap(pg_temp.o(9930000005, 'refunded', 'MXN', 2800, '{"refunds":[{"id":7001,"amount":2800,"created_at":"2025-01-03T10:00:00","detail":true,"product_amount":2800,"shipping_amount":0,"tax_amount":0,"lines":[]}]}'));
  PERFORM pg_temp.cap(pg_temp.o(9930000006, 'completed', 'MXN', 3000, '{"refunds":[{"id":7002,"amount":1000,"created_at":"2025-01-03T10:00:00","detail":true,"product_amount":1000,"shipping_amount":0,"tax_amount":0,"lines":[]}]}'));
  PERFORM pg_temp.cap(pg_temp.o(9930000007, 'completed', 'MXN', 3000, '{"refunds":[{"id":7003,"amount":500,"detail":false}]}'));
  PERFORM pg_temp.ok((pg_temp.ms(9930000005)).payment_state = 'paid_refunded_full' AND (pg_temp.ms(9930000005)).net_product_revenue = 0 AND (pg_temp.ms(9930000005)).total_collected = 0,
    'TEST 13a · fully refunded order: counted as an order but net product revenue 0 and total collected 0', (pg_temp.ms(9930000005)).net_product_revenue::text);
  PERFORM pg_temp.ok((pg_temp.ms(9930000006)).payment_state = 'paid_refunded_partial' AND (pg_temp.ms(9930000006)).net_product_revenue = 2000
    AND (pg_temp.ms(9930000006)).refunds = 1000 AND (pg_temp.ms(9930000006)).total_collected = 2000,
    'TEST 13b · partial refund: 3000 − 1000 = 2000 net product revenue / total collected', (pg_temp.ms(9930000006)).net_product_revenue::text);
  PERFORM pg_temp.ok((pg_temp.ms(9930000007)).net_product_revenue = 2500 AND (pg_temp.ms(9930000007)).data_quality = 'PARTIAL'
    AND 'refund_without_line_detail' = ANY ((pg_temp.ms(9930000007)).data_quality_reasons),
    'TEST 13c · refund without line detail: assumed product (2500) and flagged PARTIAL', '');

  -- ═════ TEST 14 / 15 · currency ═════
  PERFORM pg_temp.cap(pg_temp.o(9930000010, 'completed', 'COP', 200000) || '{"billing_country":"CO"}');
  PERFORM pg_temp.cap(pg_temp.o(9930000011, 'completed', 'USD', 150) || '{"billing_country":"US"}');
  t := pg_temp.truth();
  PERFORM pg_temp.ok((SELECT (x->>'net_product_revenue')::numeric FROM jsonb_array_elements(t->'q8_net_product_revenue'->'by_currency') x WHERE x->>'currency' = 'MXN') = 2520 + 2000 + 2500
    AND (SELECT (x->>'net_product_revenue')::numeric FROM jsonb_array_elements(t->'q8_net_product_revenue'->'by_currency') x WHERE x->>'currency' = 'COP') = 200000
    AND (SELECT (x->>'net_product_revenue')::numeric FROM jsonb_array_elements(t->'q8_net_product_revenue'->'by_currency') x WHERE x->>'currency' = 'USD') = 150
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(t->'q1_paid_orders'->'groups') g WHERE g->>'currency' IS NULL),
    'TEST 14 · MXN 7020, COP 200000, USD 150 reported apart; COP/USD never summed into MXN', (t->'q8_net_product_revenue'->'by_currency')::text);
  PERFORM pg_temp.ok(t->'q8_net_product_revenue'->'consolidated_mxn'->>'status' = 'DATA_INCOMPLETE' AND t->'q8_net_product_revenue'->'consolidated_mxn'->'value' = 'null'::jsonb
    AND jsonb_array_length(t->'q8_net_product_revenue'->'consolidated_mxn'->'fx_missing') = 2,
    'TEST 15a · no approved FX → consolidated MXN = DATA_INCOMPLETE, value null, lists COP/USD 2025-01', (t->'q8_net_product_revenue'->'consolidated_mxn')::text);
  r := pg_temp.as(op, $q$SELECT public.f360_fx_rate_propose('COP', '2025-01-01', 0.0045, 'Banxico FIX promedio mensual (prueba)')$q$); id1 := (r->>'id')::uuid;
  r := pg_temp.as(op, $q$SELECT public.f360_fx_rate_propose('USD', '2025-01-15', 20.50, 'Banxico FIX promedio mensual (prueba)')$q$); id2 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(pg_temp.truth()->'q8_net_product_revenue'->'consolidated_mxn'->>'status' = 'DATA_INCOMPLETE', 'TEST 15b · a PROPOSED (not approved) rate is never used', '');
  PERFORM pg_temp.ok(pg_temp.as(op, format('SELECT public.f360_fx_rate_approve(%L)', id1)) ? 'error', 'FX: an operator cannot approve a rate', '');
  PERFORM pg_temp.as(own, format('SELECT public.f360_fx_rate_approve(%L)', id1));
  PERFORM pg_temp.ok(pg_temp.truth()->'q8_net_product_revenue'->'consolidated_mxn'->>'status' = 'DATA_INCOMPLETE', 'TEST 15c · one currency still without rate → still DATA_INCOMPLETE', '');
  PERFORM pg_temp.as(own, format('SELECT public.f360_fx_rate_approve(%L)', id2));
  t := pg_temp.truth();
  PERFORM pg_temp.ok(t->'q8_net_product_revenue'->'consolidated_mxn'->>'status' = 'OK' AND (t->'q8_net_product_revenue'->'consolidated_mxn'->>'value')::numeric = round(7020 + 200000 * 0.0045 + 150 * 20.50, 2)
    AND t->'q8_net_product_revenue'->'consolidated_mxn'->>'kind' = 'CONVERTED'
    AND (SELECT (x->>'net_product_revenue')::numeric FROM jsonb_array_elements(t->'q8_net_product_revenue'->'by_currency') x WHERE x->>'currency' = 'COP') = 200000,
    'TEST 15d · approved monthly FX → consolidated MXN = 7020 + 900 + 3075 = 10995 (CONVERTED), originals unchanged', (t->'q8_net_product_revenue'->'consolidated_mxn')::text);
  BEGIN UPDATE f360.fx_rates SET rate = 1 WHERE id = id1; PERFORM pg_temp.ok(false, 'FX: approved rate cannot be edited');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'FX: approved rate cannot be edited (void + new)', SQLERRM); END;
  r := pg_temp.as(op, $q$SELECT public.f360_fx_rate_propose('COP', '2025-01-01', 0.005, 'otra')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'FX: one live rate per currency-month', coalesce(r->>'error', ''));
  PERFORM pg_temp.ok(pg_temp.as(op, $q$SELECT public.f360_fx_rate_propose('COP', '2099-01-01', 0.005, 'futuro')$q$) ? 'error'
    AND pg_temp.as(sel, $q$SELECT public.f360_fx_rate_propose('COP', '2024-12-01', 0.005, 'x')$q$) ? 'error', 'FX: future month refused; seller cannot propose', '');

  -- ═════ D3 spend upload: validation, audit, idempotency ═════
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'mal.csv',
        jsonb_build_array(pg_temp.spend_row('2025-01-01', '-5'), pg_temp.spend_row('2025-13-01', '10'), pg_temp.spend_row('2025-01-02', '1,200.50'))));
  PERFORM pg_temp.ok(r->>'result' = 'rejected' AND jsonb_array_length(r->'errors') = 3
    AND (SELECT status FROM f360.marketing_spend_imports WHERE id = (r->>'import_id')::uuid) = 'rejected'
    AND (SELECT uploaded_by_name FROM f360.marketing_spend_imports WHERE id = (r->>'import_id')::uuid) IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM f360.marketing_spend_rows WHERE import_id = (r->>'import_id')::uuid),
    'spend: invalid file rejected WHOLE (negative, bad date, formatted number), attempt audited with uploader, no rows loaded', (r->'errors')::text);
  PERFORM pg_temp.ok(pg_temp.as(op, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'x.csv', jsonb_build_array(pg_temp.spend_row('2025-01-01', '10')))) ? 'error'
    AND pg_temp.as(sel, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'x.csv', jsonb_build_array(pg_temp.spend_row('2025-01-01', '10')))) ? 'error',
    'spend: only an owner can upload (operator / seller denied)', '');
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'dup.csv',
        jsonb_build_array(pg_temp.spend_row('2025-01-01', '100'), pg_temp.spend_row('2025-01-01', '100'))));
  PERFORM pg_temp.ok(r->>'result' = 'rejected', 'spend: the same account/day/campaign/ad twice in a file is rejected', (r->'errors')::text);

  -- ═════ TEST 16 · without (complete) spend: CAC / ROAS / MER are DATA_INCOMPLETE with value null, never 0 ═════
  k := pg_temp.truth()->'q10_efficiency';
  PERFORM pg_temp.ok(k->'mer'->>'status' = 'DATA_INCOMPLETE' AND k->'mer'->'value' = 'null'::jsonb AND k->'roas'->'value' = 'null'::jsonb AND k->'cac'->'value' = 'null'::jsonb
    AND (k->'mer'->'missing')::text LIKE '%marketing_spend_missing%', 'TEST 16a · no spend → MER / ROAS / CAC = DATA_INCOMPLETE, value null (not 0)', k::text);
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'meta_ene.csv',
        jsonb_build_array(pg_temp.spend_row('2025-01-01', '1000'), pg_temp.spend_row('2025-01-02', '1500.50'))));
  s1 := (r->>'import_id')::uuid;
  PERFORM pg_temp.ok(r->>'result' = 'accepted' AND (SELECT count(*) FROM f360.marketing_spend_daily WHERE import_id = s1) = 2, 'spend: valid file accepted (2 rows)', r::text);
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'meta_ene_otra_vez.csv',
        jsonb_build_array(pg_temp.spend_row('2025-01-01', '1000'), pg_temp.spend_row('2025-01-02', '1500.50'))));
  PERFORM pg_temp.ok(r->>'result' = 'duplicate' AND (r->>'import_id')::uuid = s1 AND (SELECT count(*) FROM f360.marketing_spend_imports WHERE status = 'accepted') = 1,
    'spend: same content again = the first import (idempotent, no double spend)', r::text);
  k := pg_temp.truth()->'q10_efficiency';
  PERFORM pg_temp.ok(k->'mer'->>'status' = 'DATA_INCOMPLETE' AND k->'mer'->'value' = 'null'::jsonb AND (k->'mer'->'missing')::text LIKE '%unknown_if_%_has_spend%',
    'TEST 16b · spend loaded but unknown whether Google Ads also spends → still DATA_INCOMPLETE (never a partial MER)', (k->'mer'->'missing')::text);
  PERFORM pg_temp.as(own, $q$SELECT public.f360_measurement_source_set('meta_ads', NULL, true)$q$);
  PERFORM pg_temp.as(own, $q$SELECT public.f360_measurement_source_set('google_ads', NULL, false)$q$);
  k := pg_temp.truth()->'q10_efficiency';
  PERFORM pg_temp.ok(k->'mer'->>'status' = 'DATA_INCOMPLETE' AND (k->'mer'->'missing')::text LIKE '%meta_ads_spend_days_missing:1%',
    'TEST 16c · a day without a spend row (2025-01-03) = unknown, not 0 → DATA_INCOMPLETE', (k->'mer'->'missing')::text);
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'meta_ene_restatement.csv',
        jsonb_build_array(pg_temp.spend_row('2025-01-02', '1400'), pg_temp.spend_row('2025-01-03', '0'))));
  s2 := (r->>'import_id')::uuid;
  PERFORM pg_temp.ok((SELECT sum(spend) FROM f360.marketing_spend_daily WHERE date BETWEEN '2025-01-01' AND '2025-01-03') = 1000 + 1400 + 0,
    'spend: a newer import restates a day (1500.50 → 1400) and a 0-spend day is explicit; older rows kept as history',
    (SELECT sum(spend) FROM f360.marketing_spend_daily WHERE date BETWEEN '2025-01-01' AND '2025-01-03')::text);
  k := pg_temp.truth()->'q10_efficiency';
  PERFORM pg_temp.ok(k->'mer'->>'status' = 'OK' AND (k->'mer'->>'value')::numeric = round((7020 + 900 + 3075)::numeric / 2400, 2)
    AND k->'roas'->'value' = 'null'::jsonb AND k->'cac'->'value' = 'null'::jsonb,
    'TEST 16d · complete spend + approved FX → MER = 10995 / 2400 = 4.58; ROAS / CAC stay DATA_INCOMPLETE until attribution / new-customer rules exist', k::text);
  PERFORM pg_temp.as(own, format('SELECT public.f360_marketing_spend_void(%L, %L)', s2, 'archivo equivocado'));
  PERFORM pg_temp.ok((SELECT sum(spend) FROM f360.marketing_spend_daily WHERE date BETWEEN '2025-01-01' AND '2025-01-03') = 2500.50
    AND (SELECT voided_by_name FROM f360.marketing_spend_imports WHERE id = s2) IS NOT NULL,
    'spend: voiding the newer import brings the previous one back (audited)', '');
  BEGIN UPDATE f360.marketing_spend_rows SET spend = 1 WHERE import_id = s1; PERFORM pg_temp.ok(false, 'spend rows are append-only');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'spend rows are append-only', SQLERRM); END;
  BEGIN DELETE FROM f360.marketing_spend_imports WHERE id = s1; PERFORM pg_temp.ok(false, 'spend imports cannot be deleted');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'spend imports cannot be deleted', SQLERRM); END;
  r := pg_temp.as(own, format('SELECT public.f360_marketing_spend_upload(%L, %L, %L, %L)', 'meta', 'csv', 'usd.csv', jsonb_build_array(pg_temp.spend_row('2025-01-04', '10', 'USD'))));
  PERFORM pg_temp.ok(r->>'result' = 'rejected', 'spend: an ad account keeps one currency (MXN account cannot receive USD rows)', (r->'errors')::text);

  -- ═════ TEST 17 · legacy store sales stay LEGACY_IMPORT ═════
  SELECT count(*) INTO co0 FROM f360.commerce_orders;
  INSERT INTO public.offline_sales (id, code, items, total, created_at, created_by_rpc) VALUES
    ('00000000-0000-4000-a000-0000000c0001', 'ZZSG0L1', '[{"product_name":"Paula","color":"Negro","size":"37","quantity":2,"unit_price":"1400"}]', 2800, '2025-01-02T18:00:00Z', false),
    ('00000000-0000-4000-a000-0000000c0002', 'ZZSG0L2', '[{"product_name":"Paula","color":"Negro","size":"38","quantity":1,"unit_price":"1400"}]', 2000, '2025-01-02T19:00:00Z', false);
  r := pg_temp.as(own, $q$SELECT public.f360_legacy_store_sales_import(true)$q$);
  PERFORM pg_temp.ok((r->>'dry_run')::boolean AND (r->>'imported')::int >= 1 AND NOT EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports),
    'TEST 17a · dry run reports and registers nothing', r::text);
  PERFORM pg_temp.ok(pg_temp.as(op, $q$SELECT public.f360_legacy_store_sales_import(false)$q$) ? 'error', 'legacy import: owner only', '');
  r := pg_temp.as(own, $q$SELECT public.f360_legacy_store_sales_import(false)$q$);
  SELECT * INTO m FROM f360.measurement_sales WHERE store_sale_id = '00000000-0000-4000-a000-0000000c0001';
  PERFORM pg_temp.ok(m.capture_source = 'LEGACY_IMPORT' AND m.sales_channel = 'legacy_store' AND m.timing_class = 'legacy_import' AND m.is_paid_sale
    AND m.data_quality = 'PARTIAL' AND 'legacy_import' = ANY (m.data_quality_reasons) AND m.net_product_revenue = 2800 AND m.currency = 'MXN',
    'TEST 17 · a valid legacy sale enters as LEGACY_IMPORT / legacy_store, PARTIAL, never as an F360 RPC sale', m.capture_source || ' ' || m.sales_channel);
  SELECT * INTO m FROM f360.measurement_sales WHERE store_sale_id = '00000000-0000-4000-a000-0000000c0002';
  PERFORM pg_temp.ok(NOT m.is_paid_sale AND m.status_class = 'needs_review' AND 'total_does_not_match_items' = ANY (m.data_quality_reasons),
    'TEST 17b · a legacy sale whose total ≠ items is registered as needs_review and does NOT count', m.status_class);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.commerce_orders) = co0 AND NOT EXISTS (SELECT 1 FROM f360.commerce_orders WHERE store_sale_id = '00000000-0000-4000-a000-0000000c0001'),
    'TEST 17c · commerce_orders / exec dashboard numbers unchanged (legacy only in the S-G0 layer)', '');
  r := pg_temp.as(own, $q$SELECT public.f360_legacy_store_sales_import(false)$q$);
  PERFORM pg_temp.ok((r->>'candidates')::int = 0, 'TEST 17d · re-running the legacy import registers nothing new (idempotent)', r::text);
  BEGIN UPDATE f360.legacy_store_sale_imports SET status = 'imported' WHERE sale_id = '00000000-0000-4000-a000-0000000c0002'; PERFORM pg_temp.ok(false, 'legacy registry immutable');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'TEST 17e · the legacy registry is append-only (a needs_review cannot be silently flipped)', SQLERRM); END;
  t := pg_temp.truth();
  PERFORM pg_temp.ok((t->'q6_channels'->'legacy_store'->>'paid')::int = 1 AND (t->'q5_timing'->'legacy_import'->>'paid')::int = 1,
    'truth: answers 5 / 6 separate legacy from online and store', (t->'q6_channels')::text);

  -- ═════ TEST 18 · product cost versions preserve history ═════
  SELECT p.id, v.id INTO v_prod, v_var FROM f360.products p JOIN f360.product_variants v ON v.product_id = p.id LIMIT 1;
  r := pg_temp.as(op, format('SELECT public.f360_product_cost_propose(%L, NULL, NULL, 500, %L, %L, %L, %L)', v_prod, 'MXN', '2025-01-01', 'supplier_invoice', 'prueba'));
  id1 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(pg_temp.as(op, format('SELECT public.f360_product_cost_decide(%L, true)', id1)) ? 'error', 'cost: an operator cannot approve', '');
  PERFORM pg_temp.as(own, format('SELECT public.f360_product_cost_decide(%L, true)', id1));
  r := pg_temp.as(op, format('SELECT public.f360_product_cost_propose(%L, NULL, NULL, 550, %L, %L, %L)', v_prod, 'MXN', '2025-06-01', 'supplier_invoice'));
  id2 := (r->>'id')::uuid;
  r := pg_temp.as(own, format('SELECT public.f360_product_cost_decide(%L, true)', id2));
  PERFORM pg_temp.ok((SELECT cost_amount FROM f360.product_cost_versions WHERE id = id1) = 500 AND (SELECT effective_to FROM f360.product_cost_versions WHERE id = id1) = DATE '2025-05-31'
    AND (SELECT effective_to FROM f360.product_cost_versions WHERE id = id2) IS NULL AND (SELECT count(*) FROM f360.product_cost_effective WHERE product_id = v_prod) = 2,
    'TEST 18 · a new cost is a new version: the old one keeps 500 and is closed on 2025-05-31; both remain in history', r::text);
  BEGIN UPDATE f360.product_cost_versions SET cost_amount = 1 WHERE id = id1; PERFORM pg_temp.ok(false, 'cost amount immutable');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'TEST 18b · an approved cost cannot be overwritten', SQLERRM); END;
  BEGIN DELETE FROM f360.product_cost_versions WHERE id = id1; PERFORM pg_temp.ok(false, 'cost not deletable');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'TEST 18c · a cost version cannot be deleted', SQLERRM); END;
  r := pg_temp.as(op, format('SELECT public.f360_product_cost_propose(%L, NULL, NULL, 480, %L, %L, %L)', v_prod, 'MXN', '2024-12-01', 'owner_estimate'));
  id3 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(pg_temp.as(own, format('SELECT public.f360_product_cost_decide(%L, true)', id3)) ? 'error', 'TEST 18d · backdating before an approved version is refused (history not rewritten)', '');
  PERFORM pg_temp.as(own, format('SELECT public.f360_product_cost_decide(%L, false, %L)', id3, 'fecha equivocada'));
  PERFORM pg_temp.ok((SELECT status FROM f360.product_cost_versions WHERE id = id3) = 'rejected', 'cost: a wrong proposal is rejected (kept, not edited)', '');
  r := pg_temp.as(op, format('SELECT public.f360_product_cost_propose(%L, %L, %L, 520, %L, %L, %L)', v_prod, v_var, 'CO', 'MXN', '2025-02-01', 'production_order'));
  PERFORM pg_temp.ok(NOT (r ? 'error'), 'cost: a variant + market scoped version is a separate timeline', r::text);
  PERFORM pg_temp.ok(pg_temp.as(sel, format('SELECT public.f360_product_cost_propose(%L, NULL, NULL, 1, %L, %L, %L)', v_prod, 'MXN', '2025-01-01', 'other')) ? 'error'
    AND pg_temp.as(sel, format('SELECT public.f360_product_cost_history(%L)', v_prod)) ? 'error', 'cost: a seller cannot propose or read costs', '');
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.as(own, format('SELECT public.f360_product_cost_history(%L)', v_prod))) = 4, 'cost: history lists every version (approved, rejected, proposed)', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail, ''), 120) FROM t_results ORDER BY n;
DO $$ DECLARE f int := (SELECT count(*) FROM t_results WHERE status = 'FAIL'); p int := (SELECT count(*) FROM t_results WHERE status = 'PASS');
BEGIN IF f > 0 THEN RAISE EXCEPTION 'ENSAYO FALLÓ: % de % pruebas', f, f + p; END IF; RAISE EXCEPTION 'ENSAYO OK (% pruebas)', p; END $$;
ROLLBACK;
