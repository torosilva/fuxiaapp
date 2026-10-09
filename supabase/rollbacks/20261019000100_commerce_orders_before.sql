-- f360.commerce_orders as it was in production before 20261019000100 (pg_get_viewdef, 2026-10-08).
CREATE OR REPLACE VIEW f360.commerce_orders AS
 SELECT 'woo'::text AS source_system,
    o.business_origin,
    o.created_via,
    'online'::text AS channel,
    (t.key || ':'::text) || o.woo_order_id AS external_ref,
    o.target_id,
    o.woo_order_id,
    NULL::uuid AS store_sale_id,
    NULL::uuid AS location_id,
    o.woo_created_at AS occurred_at,
    COALESCE(o.first_paid_at, o.paid_at) AS paid_at,
    o.woo_status AS status,
    f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class,
        CASE
            WHEN NOT o.ever_paid THEN 'never_paid'::text
            WHEN o.woo_status = 'cancelled'::text THEN 'paid_cancelled'::text
            WHEN o.woo_status = 'refunded'::text OR COALESCE(rt.refund_total, 0::numeric) >= COALESCE(o.paid_order_total, o.order_total) AND COALESCE(rt.refund_total, 0::numeric) > 0::numeric THEN 'paid_refunded_full'::text
            WHEN COALESCE(rt.refund_total, 0::numeric) > 0::numeric THEN 'paid_refunded_partial'::text
            ELSE 'paid'::text
        END AS payment_state,
    o.market,
    o.currency AS currency_original,
    o.payment_method,
    o.payment_category,
    o.woo_customer_id,
    tx.customer_id AS loyalty_customer_id,
        CASE
            WHEN tx.customer_id IS NOT NULL THEN 'loyalty_member'::text
            WHEN o.woo_customer_id IS NOT NULL THEN 'registered'::text
            ELSE 'guest'::text
        END AS customer_link_status,
    o.units,
    o.items_subtotal AS product_gross,
    o.discount_total AS discount,
    o.items_total AS product_net,
    o.shipping_total AS shipping,
    o.total_tax AS tax,
    o.fees_total + o.fees_tax AS fees,
    o.order_total,
    COALESCE(rt.refund_total, 0::numeric) AS refund_total,
    COALESCE(rt.refund_product, 0::numeric) AS refund_product,
    o.items_total - LEAST(COALESCE(rt.refund_product, 0::numeric), o.items_total) AS net_product,
    o.order_total - LEAST(COALESCE(rt.refund_total, 0::numeric), o.order_total) AS net_order_total,
    o.paid_items_total,
    o.paid_order_total,
        CASE
            WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 OR abs(o.items_subtotal - o.items_total - o.discount_total) > 0.01 THEN 'UNVERIFIED'::text
            WHEN COALESCE(rt.has_header_only, false) OR o.market_conflict OR o.business_origin = 'unknown'::text OR o.ever_paid AND o.woo_status = 'cancelled'::text AND o.paid_order_total IS NULL THEN 'PARTIAL'::text
            ELSE 'VERIFIED'::text
        END AS data_quality,
    array_remove(ARRAY[
        CASE
            WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 THEN 'total_does_not_reconcile'::text
            ELSE NULL::text
        END,
        CASE
            WHEN abs(o.items_subtotal - o.items_total - o.discount_total) > 0.01 THEN 'discount_does_not_reconcile'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(rt.has_header_only, false) THEN 'refund_without_line_detail'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.market_conflict THEN 'market_conflict_currency_vs_path'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.business_origin = 'unknown'::text THEN 'origin_unknown'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.ever_paid AND o.woo_status = 'cancelled'::text AND o.paid_order_total IS NULL THEN 'paid_value_unknown'::text
            ELSE NULL::text
        END], NULL::text) AS data_quality_reasons,
    'woo_order:'::text || o.last_captured_via AS provenance
   FROM f360.commerce_woo_orders o
     JOIN f360.sales_targets t ON t.id = o.target_id
     LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
     LEFT JOIN LATERAL ( SELECT lc.customer_id
           FROM transactions x
             JOIN loyalty_cards lc ON lc.id = x.loyalty_card_id
          WHERE x.wc_order_id = o.woo_order_id
          ORDER BY x.created_at
         LIMIT 1) tx ON true
UNION ALL
 SELECT 'f360_store'::text AS source_system,
    'physical_store'::text AS business_origin,
    'f360_rpc'::text AS created_via,
    'store'::text AS channel,
    'store_sale:'::text || s.id AS external_ref,
    NULL::uuid AS target_id,
    NULL::bigint AS woo_order_id,
    s.id AS store_sale_id,
    s.location_id,
    s.created_at AS occurred_at,
    s.created_at AS paid_at,
    'completed'::text AS status,
    'countable'::text AS status_class,
    'paid'::text AS payment_state,
    'MX'::text AS market,
    'MXN'::text AS currency_original,
    s.payment_method,
        CASE s.payment_method
            WHEN 'cash'::text THEN 'cash'::text
            WHEN 'card'::text THEN 'card'::text
            WHEN 'transfer'::text THEN 'transfer'::text
            ELSE 'other'::text
        END AS payment_category,
    NULL::bigint AS woo_customer_id,
    s.customer_id AS loyalty_customer_id,
        CASE
            WHEN s.customer_id IS NOT NULL THEN 'loyalty_member'::text
            ELSE 'anonymous'::text
        END AS customer_link_status,
    li.units,
    li.gross AS product_gross,
    0 AS discount,
    li.gross AS product_net,
    0 AS shipping,
    0 AS tax,
    0 AS fees,
    s.total AS order_total,
    0 AS refund_total,
    0 AS refund_product,
    li.gross AS net_product,
    s.total AS net_order_total,
    li.gross AS paid_items_total,
    s.total AS paid_order_total,
        CASE
            WHEN abs(s.total - li.gross) > 0.01 THEN 'UNVERIFIED'::text
            ELSE 'VERIFIED'::text
        END AS data_quality,
    array_remove(ARRAY[
        CASE
            WHEN abs(s.total - li.gross) > 0.01 THEN 'total_does_not_match_lines'::text
            ELSE NULL::text
        END, 'currency_implied_mxn'::text], NULL::text) AS data_quality_reasons,
    'offline_sales:created_by_rpc'::text AS provenance
   FROM offline_sales s
     JOIN LATERAL ( SELECT COALESCE(sum(i.quantity), 0::bigint)::integer AS units,
            COALESCE(sum(i.line_total), 0::numeric) AS gross
           FROM offline_sale_items i
          WHERE i.sale_id = s.id) li ON true
  WHERE s.created_by_rpc;
