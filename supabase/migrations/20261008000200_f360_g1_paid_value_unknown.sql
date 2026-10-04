-- Fuxia 360 G1-B fix (STAGING): a paid order first seen ALREADY cancelled (e.g. backfill of a paid order later edited to
-- total 0, DQ-02) has no paid snapshot. It stays reversed / paid_cancelled, but its quality is PARTIAL with the reason
-- 'paid_value_unknown' instead of VERIFIED. Same columns; only the quality expressions change.
-- Rollback: supabase/rollbacks/20261008000200_f360_g1_paid_value_unknown.down.sql (restores the 000100 view)
CREATE OR REPLACE VIEW f360.commerce_orders AS
  SELECT 'woo'::text AS source_system, o.business_origin, o.created_via, 'online'::text AS channel,
         t.key || ':' || o.woo_order_id AS external_ref, o.target_id, o.woo_order_id, NULL::uuid AS store_sale_id, NULL::uuid AS location_id,
         o.woo_created_at AS occurred_at, coalesce(o.first_paid_at, o.paid_at) AS paid_at, o.woo_status AS status,
         f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class,
         CASE WHEN NOT o.ever_paid THEN 'never_paid'
              WHEN o.woo_status = 'cancelled' THEN 'paid_cancelled'
              WHEN o.woo_status = 'refunded' OR coalesce(rt.refund_total, 0) >= coalesce(o.paid_order_total, o.order_total) AND coalesce(rt.refund_total, 0) > 0 THEN 'paid_refunded_full'
              WHEN coalesce(rt.refund_total, 0) > 0 THEN 'paid_refunded_partial'
              ELSE 'paid' END AS payment_state,
         o.market, o.currency AS currency_original, o.payment_method, o.payment_category,
         o.woo_customer_id, tx.customer_id AS loyalty_customer_id,
         CASE WHEN tx.customer_id IS NOT NULL THEN 'loyalty_member' WHEN o.woo_customer_id IS NOT NULL THEN 'registered' ELSE 'guest' END AS customer_link_status,
         o.units, o.items_subtotal AS product_gross, o.discount_total AS discount, o.items_total AS product_net,
         o.shipping_total AS shipping, o.total_tax AS tax, o.fees_total + o.fees_tax AS fees, o.order_total,
         coalesce(rt.refund_total, 0) AS refund_total, coalesce(rt.refund_product, 0) AS refund_product,
         o.items_total - least(coalesce(rt.refund_product, 0), o.items_total) AS net_product,
         o.order_total - least(coalesce(rt.refund_total, 0), o.order_total) AS net_order_total,
         o.paid_items_total, o.paid_order_total,
         CASE WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01
                OR abs((o.items_subtotal - o.items_total) - o.discount_total) > 0.01 THEN 'UNVERIFIED'
              WHEN coalesce(rt.has_header_only, false) OR o.market_conflict OR o.business_origin = 'unknown'
                OR (o.ever_paid AND o.woo_status = 'cancelled' AND o.paid_order_total IS NULL) THEN 'PARTIAL'
              ELSE 'VERIFIED' END AS data_quality,
         array_remove(ARRAY[
           CASE WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 THEN 'total_does_not_reconcile' END,
           CASE WHEN abs((o.items_subtotal - o.items_total) - o.discount_total) > 0.01 THEN 'discount_does_not_reconcile' END,
           CASE WHEN coalesce(rt.has_header_only, false) THEN 'refund_without_line_detail' END,
           CASE WHEN o.market_conflict THEN 'market_conflict_currency_vs_path' END,
           CASE WHEN o.business_origin = 'unknown' THEN 'origin_unknown' END,
           CASE WHEN o.ever_paid AND o.woo_status = 'cancelled' AND o.paid_order_total IS NULL THEN 'paid_value_unknown' END], NULL) AS data_quality_reasons,
         'woo_order:' || o.last_captured_via AS provenance
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN LATERAL (SELECT lc.customer_id FROM public.transactions x JOIN public.loyalty_cards lc ON lc.id = x.loyalty_card_id
                     WHERE x.wc_order_id = o.woo_order_id ORDER BY x.created_at LIMIT 1) tx ON true
  UNION ALL
  -- Physical store sales: read from the authoritative record, never copied. Store sales are MXN by construction
  -- (stores are in Mexico; the store sale stores no currency) and have no discount / shipping / tax / refunds today (DW4).
  SELECT 'f360_store', 'physical_store', 'f360_rpc', 'store',
         'store_sale:' || s.id, NULL, NULL, s.id, s.location_id,
         s.created_at, s.created_at, 'completed', 'countable', 'paid',
         'MX', 'MXN', s.payment_method, CASE s.payment_method WHEN 'cash' THEN 'cash' WHEN 'card' THEN 'card' WHEN 'transfer' THEN 'transfer' ELSE 'other' END,
         NULL, s.customer_id, CASE WHEN s.customer_id IS NOT NULL THEN 'loyalty_member' ELSE 'anonymous' END,
         li.units, li.gross, 0, li.gross, 0, 0, 0, s.total, 0, 0, li.gross, s.total, li.gross, s.total,
         CASE WHEN abs(s.total - li.gross) > 0.01 THEN 'UNVERIFIED' ELSE 'VERIFIED' END,
         array_remove(ARRAY[CASE WHEN abs(s.total - li.gross) > 0.01 THEN 'total_does_not_match_lines' END, 'currency_implied_mxn'], NULL),
         'offline_sales:created_by_rpc'
  FROM public.offline_sales s
  JOIN LATERAL (SELECT coalesce(sum(i.quantity), 0)::int AS units, coalesce(sum(i.line_total), 0) AS gross FROM public.offline_sale_items i WHERE i.sale_id = s.id) li ON true
  WHERE s.created_by_rpc;
