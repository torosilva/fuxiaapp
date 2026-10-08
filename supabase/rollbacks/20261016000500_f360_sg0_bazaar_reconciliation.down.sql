-- Rollback of 20261016000500_f360_sg0_bazaar_reconciliation.sql: restores f360.measurement_sales as left by 20261016000200 and
-- f360.legacy_sale_check as in 20261014000500, then drops the preview + classifier. Registered imports are not touched.
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
CREATE OR REPLACE FUNCTION f360.legacy_sale_check(p_sale_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s public.offline_sales; v_items numeric := 0; v_units int := 0; v_bad int := 0; v_n int := 0; v_loc uuid; v_ch_type text;
  v_day date; issues text[] := '{}'; blocking text[] := '{}';
BEGIN
  SELECT * INTO s FROM public.offline_sales WHERE id = p_sale_id;
  IF s.id IS NULL THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('sale_not_found')); END IF;
  IF s.created_by_rpc THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('not_legacy_created_by_f360_rpc')); END IF;
  v_day := (s.created_at AT TIME ZONE 'America/Mexico_City')::date;
  IF jsonb_typeof(s.items) = 'array' THEN
    SELECT count(*), coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'
                                        THEN (e->>'quantity')::numeric * (e->>'unit_price')::numeric END), 0),
           coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' THEN (e->>'quantity')::int END), 0),
           count(*) FILTER (WHERE NOT ((e->>'quantity') ~ '^[1-9]\d*$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'))
      INTO v_n, v_items, v_units, v_bad
      FROM jsonb_array_elements(s.items) e;
  END IF;
  IF v_n = 0 THEN blocking := array_append(blocking, 'no_items'); END IF;
  IF v_bad > 0 THEN blocking := array_append(blocking, 'item_quantity_or_price_invalid'); END IF;
  IF s.total IS NULL OR s.total <= 0 THEN blocking := array_append(blocking, 'total_not_positive'); END IF;
  IF v_n > 0 AND abs(coalesce(s.total, 0) - v_items) > 0.01 THEN blocking := array_append(blocking, 'total_does_not_match_items'); END IF;
  IF v_day < DATE '2020-01-01' OR s.created_at > now() THEN blocking := array_append(blocking, 'date_out_of_range'); END IF;
  SELECT l.id INTO v_loc FROM f360.locations l WHERE s.channel_id IS NOT NULL AND l.legacy_channel_id = s.channel_id LIMIT 1;
  SELECT c.type INTO v_ch_type FROM public.channels c WHERE c.id = s.channel_id;
  IF v_loc IS NULL THEN issues := array_append(issues, 'location_unresolved'); END IF;
  -- possible double count with Carolina's historical summaries (same place / a bazaar on the same days)
  IF EXISTS (SELECT 1 FROM f360.historical_sales h WHERE h.status = 'active' AND v_day BETWEEN h.period_start AND h.period_end
               AND ((v_loc IS NOT NULL AND h.location_id = v_loc) OR (h.location_id IS NULL AND h.kind = 'bazaar' AND coalesce(v_ch_type, '') IN ('bazar', 'bazaar')))) THEN
    blocking := array_append(blocking, 'possible_overlap_historical_summary');
  END IF;
  issues := array_append(blocking || issues, 'currency_implied_mxn');
  RETURN jsonb_build_object('ok_to_import', cardinality(blocking) = 0, 'issues', to_jsonb(issues), 'location_id', v_loc,
    'total', s.total, 'items_total', round(v_items, 2), 'units', v_units, 'sale_date', v_day);
END $$;
DROP FUNCTION public.f360_bazaar_reconciliation_preview();
DROP FUNCTION f360.bazaar_sale_classification();
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261016000500';
