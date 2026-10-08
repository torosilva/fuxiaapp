-- Fuxia 360 · S-G0 · TAX STATUS = PENDING ACCOUNTING CONFIRMATION (Mario 2026-10-08, pre-production gate decision 7).
-- Corrects 20261014000600 where it ASSUMED a tax treatment:
--   · its comment said "store prices include IVA" and labelled every sale without a Woo tax line 'included_not_separated'
--     — an unproven assumption (Woo tax = 0 does NOT prove there is no IVA, nor that IVA is included);
--   · product_net_before_tax was filled from product_net whenever Woo reported a tax line — a net-of-tax figure built on the
--     assumption that Woo's tax configuration is the accounting truth.
-- Now (view keeps the same columns, same order, + tax_status at the end; CREATE OR REPLACE, dependants untouched):
--   · every amount stays the RAW transaction amount in its original currency (nothing recomputed, nothing removed);
--   · product_net_before_tax = NULL for every sale (DATA INCOMPLETE until accounting confirms the treatment);
--   · iva_treatment only states a FACT about the source: 'tax_amount_reported_by_source' / 'tax_not_separated_by_source';
--   · tax_status = 'PENDING_ACCOUNTING_CONFIRMATION' on every sale; f360_measurement_truth.q8 says the basis is RAW and
--     returns net_of_tax = DATA_INCOMPLETE (value NULL); f360_measurement_sales_list returns tax_status.
--   · the Board metric catalog definition of revenue_net_product says the same (only if SB0 is present).
-- Open accounting questions (docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md §IVA): MX web prices include IVA? store prices?
-- Colombia equivalent? shipping tax? discount tax? No figure, rule or default is changed beyond the labels above.
-- Rollback: supabase/rollbacks/20261016000200_f360_sg0_tax_pending.down.sql

CREATE OR REPLACE VIEW f360.measurement_sales AS
  SELECT c.external_ref AS sale_ref, c.source_system,
         CASE WHEN c.channel = 'store' THEN 'store' ELSE 'online' END AS sales_channel,
         CASE WHEN c.source_system = 'f360_store' THEN 'f360_store_rpc'
              WHEN o.first_captured_via = 'webhook' THEN 'woo_realtime_webhook'
              WHEN o.first_captured_via = 'poll' THEN 'woo_reconciliation_recovered'
              WHEN o.first_captured_via = 'backfill' THEN 'woo_history_import'
              ELSE 'test_fixture' END AS capture_source,
         CASE WHEN o.first_captured_via = 'backfill' THEN 'historical_import' WHEN o.first_captured_via = 'test' THEN 'test' ELSE 'realtime' END AS timing_class,
         CASE WHEN o.first_captured_via = 'backfill' THEN o.first_captured_at END AS imported_at,
         coalesce(t.is_test, false) AS is_test_channel,
         c.target_id, c.woo_order_id, c.store_sale_id, c.location_id,
         c.occurred_at, c.paid_at, (coalesce(c.paid_at, c.occurred_at) AT TIME ZONE 'America/Mexico_City')::date AS business_date,
         c.status, c.status_class, c.payment_state, (c.status_class = 'countable') AS is_paid_sale,
         c.market, c.currency_original AS currency, o.billing_country AS country,
         c.product_gross AS gross_merchandise_value, c.discount AS discounts, c.product_net,
         NULL::numeric AS product_net_before_tax,                                   -- DATA INCOMPLETE until accounting confirms
         c.tax AS tax_iva, CASE WHEN c.tax <> 0 THEN 'tax_amount_reported_by_source' ELSE 'tax_not_separated_by_source' END AS iva_treatment,
         c.shipping AS shipping_charged, c.fees, c.refund_total AS refunds, c.refund_product AS refunds_product,
         c.net_product AS net_product_revenue, c.net_order_total AS total_collected, c.units,
         c.data_quality, c.data_quality_reasons, c.provenance,
         'PENDING_ACCOUNTING_CONFIRMATION'::text AS tax_status
  FROM f360.commerce_orders c
  LEFT JOIN f360.commerce_woo_orders o ON o.target_id = c.target_id AND o.woo_order_id = c.woo_order_id
  LEFT JOIN f360.sales_targets t ON t.id = c.target_id
  UNION ALL
  SELECT 'legacy_store_sale:' || s.id, 'legacy_store', 'legacy_store', 'LEGACY_IMPORT', 'legacy_import', li.imported_at, false,
         NULL, NULL, s.id, li.location_id,
         s.created_at, s.created_at, (s.created_at AT TIME ZONE 'America/Mexico_City')::date,
         'legacy_recorded', CASE WHEN li.status = 'imported' THEN 'countable' ELSE 'needs_review' END, 'paid', li.status = 'imported',
         'MX', 'MXN', NULL,
         s.total, 0, s.total, NULL::numeric, 0, 'tax_not_separated_by_source', 0, 0, 0, 0, s.total, s.total, coalesce((li.validation->>'units')::int, 0),
         'PARTIAL', ARRAY(SELECT jsonb_array_elements_text(li.validation->'issues')) || ARRAY['legacy_import'], 'offline_sales:legacy_import',
         'PENDING_ACCOUNTING_CONFIRMATION'::text
  FROM f360.legacy_store_sale_imports li JOIN public.offline_sales s ON s.id = li.sale_id;

CREATE OR REPLACE FUNCTION public.f360_measurement_truth(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); incl boolean := f360.sg0_include_tests(); h jsonb := f360.sg0_source_health();
  fx_missing jsonb; v_cons numeric; rec jsonb;
BEGIN
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN RAISE EXCEPTION 'Periodo no válido.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', to_char(period, 'YYYY-MM')) ORDER BY period, currency), '[]') INTO fx_missing
    FROM (SELECT DISTINCT currency, date_trunc('month', business_date)::date AS period FROM f360.measurement_sales m
          WHERE m.is_paid_sale AND m.currency <> 'MXN' AND (incl OR NOT m.is_test_channel)
            AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to)) z
    WHERE f360.fx_rate_for(currency, period) IS NULL;
  IF jsonb_array_length(fx_missing) = 0 THEN
    SELECT coalesce(sum(m.net_product_revenue * f360.fx_rate_for(m.currency, m.business_date)), 0) INTO v_cons FROM f360.measurement_sales m
      WHERE m.is_paid_sale AND (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to);
  END IF;
  SELECT jsonb_build_object('targets', coalesce(jsonb_agg(t), '[]')) INTO rec
    FROM jsonb_array_elements((SELECT s->'detail'->'targets' FROM jsonb_array_elements(h) s WHERE s->>'key' = 'order_reconciliation')) t;

  RETURN (WITH ms AS (SELECT * FROM f360.measurement_sales m
      WHERE (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to))
  SELECT jsonb_build_object(
    'kind', 'ACTUAL', 'from', p_from, 'to', p_to, 'generated_at', now(), 'includes_test_data', incl, 'timezone', 'America/Mexico_City',
    'health', h,
    -- 1 · which paid orders Fuxia 360 knows (by channel × capture source × currency; D6 components)
    'q1_paid_orders', jsonb_build_object('total', (SELECT count(*) FROM ms WHERE is_paid_sale),
      'groups', (SELECT coalesce(jsonb_agg(g ORDER BY g->>'sales_channel', g->>'capture_source', g->>'currency'), '[]') FROM (
        SELECT jsonb_build_object('sales_channel', sales_channel, 'capture_source', capture_source, 'currency', currency, 'paid_orders', count(*), 'units', sum(units),
          'gross_merchandise_value', sum(gross_merchandise_value), 'discounts', sum(discounts), 'product_net', sum(product_net),
          'tax_iva', sum(tax_iva), 'shipping_charged', sum(shipping_charged), 'refunds', sum(refunds),
          'net_product_revenue', sum(net_product_revenue), 'total_collected', sum(total_collected)) AS g
        FROM ms WHERE is_paid_sale GROUP BY sales_channel, capture_source, currency) q),
      'not_paid', (SELECT coalesce(jsonb_object_agg(status_class, n), '{}') FROM (SELECT status_class, count(*) n FROM ms WHERE NOT is_paid_sale GROUP BY 1) y)),
    -- 2 + 3 · missing vs Woo and the last reconciliation (per channel feeding orders)
    'q2_q3_reconciliation', rec,
    -- 4 · capture health
    'q4_capture_health', (SELECT coalesce(jsonb_agg(jsonb_build_object('key', s->>'key', 'status', s->>'status', 'reasons', s->'reasons')), '[]')
                          FROM jsonb_array_elements(h) s WHERE s->>'key' IN ('woocommerce', 'order_reconciliation', 'store_sales')),
    -- 5 · realtime vs historical import
    'q5_timing', (SELECT coalesce(jsonb_object_agg(timing_class, jsonb_build_object('sales', n, 'paid', p)), '{}') FROM (
        SELECT timing_class, count(*) n, count(*) FILTER (WHERE is_paid_sale) p FROM ms GROUP BY 1) y),
    -- 6 · online vs store vs legacy
    'q6_channels', (SELECT coalesce(jsonb_object_agg(sales_channel, jsonb_build_object('paid', p, 'not_counted', n - p)), '{}') FROM (
        SELECT sales_channel, count(*) n, count(*) FILTER (WHERE is_paid_sale) p FROM ms GROUP BY 1) y),
    -- 7 · currency of each sale (counts; per sale: f360_measurement_sales_list)
    'q7_currencies', (SELECT coalesce(jsonb_object_agg(currency, n), '{}') FROM (SELECT currency, count(*) n FROM ms WHERE is_paid_sale GROUP BY 1) y),
    -- 8 · paid net product revenue per ORIGINAL currency + consolidated MXN only with approved FX
    'q8_net_product_revenue', jsonb_build_object(
      'by_currency', (SELECT coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'net_product_revenue', v, 'total_collected', tc, 'paid_orders', n) ORDER BY currency), '[]') FROM (
          SELECT currency, sum(net_product_revenue) v, sum(total_collected) tc, count(*) n FROM ms WHERE is_paid_sale GROUP BY 1) y),
      'consolidated_mxn', CASE WHEN jsonb_array_length(fx_missing) = 0
          THEN jsonb_build_object('status', 'OK', 'value', round(v_cons, 2), 'kind', 'CONVERTED', 'basis', 'approved monthly FX, base MXN')
          ELSE jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL, 'missing', jsonb_build_array('fx_rate_missing'), 'fx_missing', fx_missing) END,
      'basis', 'net_product_revenue = Σ line totals after coupons, before shipping, minus product refunds; paid sales only; RAW transaction amounts as charged (tax treatment PENDING ACCOUNTING CONFIRMATION — not net of tax)',
      'tax_status', 'PENDING_ACCOUNTING_CONFIRMATION', 'net_of_tax', jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL, 'missing', jsonb_build_array('accounting_confirmation_of_iva_treatment'))),
    -- 9 · do we have spend?
    'q9_spend', jsonb_build_object(
      'status', (SELECT s->>'status' FROM jsonb_array_elements(h) s WHERE s->>'key' = 'marketing_spend'),
      'by_currency', (SELECT coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'currency', currency, 'spend', v, 'days', d) ORDER BY platform, currency), '[]') FROM (
          SELECT platform, currency, sum(spend) v, count(DISTINCT date) d FROM f360.marketing_spend_daily
          WHERE (p_from IS NULL OR date >= p_from) AND (p_to IS NULL OR date <= p_to) GROUP BY 1, 2) y)),
    -- 10 · efficiency KPIs: never 0 when an input is missing
    'q10_efficiency', f360.sg0_efficiency_kpis(p_from, p_to)));
END $$;

CREATE OR REPLACE FUNCTION public.f360_measurement_sales_list(p_limit integer DEFAULT 100, p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); incl boolean := f360.sg0_include_tests();
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x->>'business_date' DESC, x->>'sale_ref' DESC), '[]') FROM (
    SELECT jsonb_build_object('sale_ref', m.sale_ref, 'sales_channel', m.sales_channel, 'capture_source', m.capture_source, 'timing', m.timing_class,
      'imported_at', m.imported_at, 'business_date', m.business_date, 'status', m.status, 'status_class', m.status_class, 'paid', m.is_paid_sale,
      'market', m.market, 'currency', m.currency, 'net_product_revenue', m.net_product_revenue, 'total_collected', m.total_collected,
      'iva_treatment', m.iva_treatment, 'tax_status', m.tax_status, 'quality', m.data_quality, 'quality_reasons', to_jsonb(m.data_quality_reasons), 'test_channel', m.is_test_channel) AS x
    FROM f360.measurement_sales m
    WHERE (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to)
    ORDER BY m.business_date DESC, m.sale_ref DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) q);
END $$;

DO $$ BEGIN
  IF to_regclass('f360_board.metric_catalog') IS NOT NULL THEN
    UPDATE f360_board.metric_catalog
       SET definition = 'Producto cobrado − cupones − reembolsos de producto, pedidos countable, en moneda original. Montos BRUTOS tal como se cobraron: tratamiento de IVA PENDIENTE DE CONFIRMACIÓN CONTABLE (no es neto de impuestos).'
     WHERE metric_key = 'revenue_net_product';
  END IF;
END $$;

COMMENT ON VIEW f360.measurement_sales IS 'S-G0: one row per sale (online / store / legacy store) with capture source and D6 revenue components, original currency, RAW amounts; tax_status PENDING_ACCOUNTING_CONFIRMATION (no net-of-tax figure). No PII.';
REVOKE ALL ON f360.measurement_sales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.measurement_sales TO service_role;
