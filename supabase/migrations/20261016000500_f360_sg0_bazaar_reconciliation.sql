-- Fuxia 360 · S-G0 · BAZAAR LEGACY SALES ⇄ CAROLINA'S BAZAAR SUMMARIES — RECONCILIATION PREVIEW + GUARD
-- (Mario 2026-10-08, pre-production decision 8). READ-ONLY preview; nothing is imported, summed, written or deleted.
-- Problem: production has 28 legacy individual sales on the legacy bazaar channel "Guadalajara" (public.offline_sales,
-- created_by_rpc = false, legacy POS app) AND Carolina's 2 bazaar summaries in f360.historical_sales (GDL 22–24 Sep,
-- Querétaro El Campanario 29 Sep–1 Oct). Adding both would double count whatever the summary already contains.
-- Classification of every legacy BAZAAR sale (channel type bazar/bazaar) against ACTIVE bazaar summaries:
--   · UNMATCHED        no summary within 2 days of the sale day → the individual sale is the only record (may count, after the
--                      normal legacy validation of 20261014000500);
--   · MATCHED          inside ONE summary's dates, same place, and the individual sales inside that window add up to the
--                      summary amount (±1 %) → the summary and the sales are the same money: the SUMMARY is the record, the
--                      individual sale never counts on top;
--   · LIKELY_DUPLICATE inside ONE summary's dates, same place, totals do not reconcile → the summary probably contains it;
--   · AMBIGUOUS        near a summary's dates (±2 days), or a summary of ANOTHER place on the same days, or several summaries.
--   Place = normalized words of the legacy channel name/location vs the summary name (accents, punctuation, GDL/QRO/MTY/CDMX
--   aliases); dates in America/Mexico_City.
-- GUARD (financial truth): only UNMATCHED legacy bazaar sales can ever count. MATCHED / LIKELY_DUPLICATE / AMBIGUOUS
--   · are blocking issues in f360.legacy_sale_check → f360_legacy_store_sales_import registers them as needs_review;
--   · are excluded LIVE in f360.measurement_sales (is_paid_sale false, status_class needs_review) even if an earlier import
--     registered them as 'imported' (e.g. Carolina loads a summary later). Resolution = a person's decision (future step).
-- Objects: f360.bazaar_sale_classification() (same SELECT as tools/preprod/bazaar_preview_prod.sql, run read-only on prod),
-- public.f360_bazaar_reconciliation_preview() (owner / operator; no customer data: sale ids, days, channel, amounts only).
-- Rollback: supabase/rollbacks/20261016000500_f360_sg0_bazaar_reconciliation.down.sql

CREATE FUNCTION f360.bazaar_sale_classification()
RETURNS TABLE (sale_id uuid, sale_day date, total numeric, channel_name text, summary_id uuid, summary_name text, class text, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH s AS (
    SELECT o.id AS sale_id, (o.created_at AT TIME ZONE 'America/Mexico_City')::date AS sale_day, o.total, c.name AS channel_name,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(c.name || ' ' || coalesce(c.location, ''), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS place_norm
    FROM public.offline_sales o LEFT JOIN public.channels c ON c.id = o.channel_id
    WHERE NOT o.created_by_rpc AND lower(coalesce(c.type, '')) IN ('bazar', 'bazaar')),
  h AS (
    SELECT hs.id AS summary_id, coalesce(l.name, hs.bazaar_name) AS summary_name, hs.period_start, hs.period_end, hs.amount, hs.pairs,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(coalesce(l.name, hs.bazaar_name), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS name_norm
    FROM f360.historical_sales hs LEFT JOIN f360.locations l ON l.id = hs.location_id
    WHERE hs.status = 'active' AND hs.kind = 'bazaar'),
  cand AS (
    SELECT s.sale_id, h.summary_id, s.sale_day BETWEEN h.period_start AND h.period_end AS in_window,
           EXISTS (SELECT 1 FROM regexp_split_to_table(btrim(s.place_norm), ' ') w
                   WHERE length(w) >= 4 AND w NOT IN ('bazar', 'bazaar', 'tienda', 'fuxia', 'store', 'ciudad', 'mexico')
                     AND position(' ' || w || ' ' IN h.name_norm) > 0) AS name_match
    FROM s JOIN h ON s.sale_day BETWEEN h.period_start - 2 AND h.period_end + 2),
  agg AS (
    SELECT s.sale_id, count(c.summary_id) AS n_cand, count(c.summary_id) FILTER (WHERE c.in_window AND c.name_match) AS n_strict,
           (array_agg(c.summary_id ORDER BY (c.in_window AND c.name_match) DESC, c.name_match DESC) FILTER (WHERE c.summary_id IS NOT NULL))[1] AS summary_id,
           bool_or(c.in_window AND NOT c.name_match) AS other_place_same_days, bool_or(NOT c.in_window) AS near_edge
    FROM s LEFT JOIN cand c ON c.sale_id = s.sale_id GROUP BY s.sale_id),
  win AS (
    SELECT c.summary_id, sum(s.total) AS sales_total, count(*) AS sales_n
    FROM cand c JOIN s ON s.sale_id = c.sale_id WHERE c.in_window AND c.name_match GROUP BY c.summary_id),
  cls AS (
    SELECT s.sale_id, s.sale_day, s.total, s.channel_name, a.summary_id, h.summary_name,
           CASE WHEN a.n_cand = 0 THEN 'UNMATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'MATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'LIKELY_DUPLICATE'
                ELSE 'AMBIGUOUS' END AS class,
           CASE WHEN a.n_cand = 0 THEN 'no_bazaar_summary_within_2_days'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'window_sales_total_equals_summary_amount'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'inside_summary_dates_same_place'
                WHEN a.n_cand > 1 THEN 'several_summaries_nearby'
                WHEN a.other_place_same_days THEN 'summary_of_another_place_on_same_days'
                WHEN a.near_edge THEN 'within_2_days_of_summary_dates'
                ELSE 'unclear' END AS reason
    FROM s JOIN agg a ON a.sale_id = s.sale_id LEFT JOIN h ON h.summary_id = a.summary_id LEFT JOIN win w ON w.summary_id = a.summary_id)
  SELECT sale_id, sale_day, total, channel_name, summary_id, summary_name, class, reason FROM cls
$$;
COMMENT ON FUNCTION f360.bazaar_sale_classification() IS 'S-G0 pre-prod: classification of legacy bazaar sales vs active bazaar summaries (UNMATCHED / MATCHED / LIKELY_DUPLICATE / AMBIGUOUS). Read-only.';

CREATE FUNCTION public.f360_bazaar_reconciliation_preview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (WITH c AS (SELECT * FROM f360.bazaar_sale_classification())
  SELECT jsonb_build_object(
    'kind', 'PREVIEW_READ_ONLY', 'generated_at', now(), 'timezone', 'America/Mexico_City', 'currency', 'MXN',
    'rule', 'Only UNMATCHED legacy bazaar sales may count; MATCHED (summary is the record), LIKELY_DUPLICATE and AMBIGUOUS never count until a person resolves them.',
    'by_class', (SELECT coalesce(jsonb_object_agg(class, x), '{}') FROM (
        SELECT class, jsonb_build_object('sales', count(*), 'total', sum(total), 'first_day', min(sale_day), 'last_day', max(sale_day),
                 'channels', jsonb_agg(DISTINCT channel_name), 'counts_in_financial_truth', class = 'UNMATCHED') x
        FROM c GROUP BY class) q),
    'summaries', (SELECT coalesce(jsonb_agg(jsonb_build_object('summary_id', h.id, 'name', coalesce(l.name, h.bazaar_name), 'from', h.period_start, 'to', h.period_end,
          'amount', h.amount, 'pairs', h.pairs,
          'legacy_sales_linked', (SELECT count(*) FROM c WHERE c.summary_id = h.id),
          'legacy_total_linked', (SELECT coalesce(sum(total), 0) FROM c WHERE c.summary_id = h.id),
          'linked_by_class', (SELECT coalesce(jsonb_object_agg(class, n), '{}') FROM (SELECT class, count(*) n FROM c WHERE c.summary_id = h.id GROUP BY class) y))
          ORDER BY h.period_start), '[]')
        FROM f360.historical_sales h LEFT JOIN f360.locations l ON l.id = h.location_id WHERE h.status = 'active' AND h.kind = 'bazaar'),
    'sales', (SELECT coalesce(jsonb_agg(jsonb_build_object('sale_ref', sale_id, 'day', sale_day, 'channel', channel_name, 'total', total,
          'class', class, 'reason', reason, 'summary', summary_name) ORDER BY sale_day, sale_id), '[]') FROM c)));
END $$;

CREATE OR REPLACE FUNCTION f360.legacy_sale_check(p_sale_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s public.offline_sales; v_items numeric := 0; v_units int := 0; v_bad int := 0; v_n int := 0; v_loc uuid; v_ch_type text;
  v_day date; issues text[] := '{}'; blocking text[] := '{}'; v_bz text;
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
  -- pre-prod decision 8: a legacy BAZAAR sale counts only when no Carolina bazaar summary may contain it
  SELECT bc.class INTO v_bz FROM f360.bazaar_sale_classification() bc WHERE bc.sale_id = p_sale_id;
  IF v_bz IS NOT NULL AND v_bz <> 'UNMATCHED' THEN blocking := array_append(blocking, 'bazaar_reconciliation_' || lower(v_bz)); END IF;
  issues := array_append(blocking || issues, 'currency_implied_mxn');
  RETURN jsonb_build_object('ok_to_import', cardinality(blocking) = 0, 'issues', to_jsonb(issues), 'location_id', v_loc,
    'total', s.total, 'items_total', round(v_items, 2), 'units', v_units, 'sale_date', v_day);
END $$;

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
         'legacy_recorded', CASE WHEN li.status = 'imported' AND coalesce(bc.class, 'UNMATCHED') = 'UNMATCHED' THEN 'countable' ELSE 'needs_review' END, 'paid',
         li.status = 'imported' AND coalesce(bc.class, 'UNMATCHED') = 'UNMATCHED',
         'MX', 'MXN', NULL,
         s.total, 0, s.total, NULL::numeric, 0, 'tax_not_separated_by_source', 0, 0, 0, 0, s.total, s.total, coalesce((li.validation->>'units')::int, 0),
         'PARTIAL', ARRAY(SELECT jsonb_array_elements_text(li.validation->'issues')) || ARRAY['legacy_import']
           || CASE WHEN bc.class IS NOT NULL AND bc.class <> 'UNMATCHED' THEN ARRAY['bazaar_reconciliation_' || lower(bc.class)] ELSE '{}'::text[] END, 'offline_sales:legacy_import',
         'PENDING_ACCOUNTING_CONFIRMATION'::text
  FROM f360.legacy_store_sale_imports li JOIN public.offline_sales s ON s.id = li.sale_id
  LEFT JOIN f360.bazaar_sale_classification() bc ON bc.sale_id = s.id;

REVOKE ALL ON f360.measurement_sales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.measurement_sales TO service_role;
REVOKE ALL ON FUNCTION f360.bazaar_sale_classification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.bazaar_sale_classification() TO service_role;
REVOKE ALL ON FUNCTION public.f360_bazaar_reconciliation_preview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_bazaar_reconciliation_preview() TO authenticated, service_role;
