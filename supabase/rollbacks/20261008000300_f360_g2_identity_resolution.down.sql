-- Rollback of 20261008000300 (G2-B2.1 identity resolution). Restores the G1 commerce_order_lines view exactly.
DROP VIEW IF EXISTS f360.commerce_order_lines;
CREATE VIEW f360.commerce_order_lines AS
  SELECT 'woo'::text AS source_system, t.key || ':' || l.woo_order_id AS external_ref, l.woo_line_id::text AS line_ref,
         coalesce(vl.variant_id, rl.variant_id, lm.confirmed_variant_id) AS variant_id, v.product_id, p.category_key,
         CASE WHEN vl.variant_id IS NOT NULL THEN 'woo_variant_link' WHEN rl.variant_id IS NOT NULL THEN 'retired_woo_link'
              WHEN lm.confirmed_variant_id IS NOT NULL THEN 'legacy_homologation' ELSE 'unresolved' END AS product_resolution,
         l.sku, l.woo_product_id, l.woo_variation_id, l.quantity,
         CASE WHEN l.quantity > 0 THEN round(l.total / l.quantity, 2) END AS unit_net,
         l.subtotal AS gross, l.subtotal - l.total AS discount, l.total AS net, l.total_tax AS tax,
         l.list_price_hint, l.list_price_source, o.currency AS currency_original
  FROM f360.commerce_woo_order_lines l
  JOIN f360.commerce_woo_orders o ON o.target_id = l.target_id AND o.woo_order_id = l.woo_order_id
  JOIN f360.sales_targets t ON t.id = l.target_id
  LEFT JOIN f360.woo_variant_links vl ON vl.target_id = l.target_id AND vl.woo_variation_id = l.woo_variation_id
  LEFT JOIN f360.retired_woo_links rl ON rl.target_id = l.target_id AND rl.woo_variation_id = l.woo_variation_id
  LEFT JOIN f360.legacy_woo_map lm ON lm.target_id = l.target_id AND lm.woo_variation_id = l.woo_variation_id AND lm.status = 'confirmado'
  LEFT JOIN f360.product_variants v ON v.id = coalesce(vl.variant_id, rl.variant_id, lm.confirmed_variant_id)
  LEFT JOIN f360.products p ON p.id = v.product_id
  UNION ALL
  SELECT 'f360_store', 'store_sale:' || i.sale_id, i.line_no::text, i.variant_id, v.product_id, p.category_key,
         CASE WHEN i.variant_id IS NOT NULL THEN 'f360_variant' ELSE 'legacy_store_item' END,
         i.sku, NULL, NULL, i.quantity, i.unit_price, i.line_total, 0, i.line_total, 0, NULL, NULL, 'MXN'
  FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id AND s.created_by_rpc
  LEFT JOIN f360.product_variants v ON v.id = i.variant_id LEFT JOIN f360.products p ON p.id = v.product_id;
REVOKE ALL ON f360.commerce_order_lines FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.commerce_order_lines TO service_role;
DROP VIEW IF EXISTS f360.channel_product_identity;
DROP VIEW IF EXISTS f360.channel_variant_identity;
DROP VIEW IF EXISTS f360.channel_variant_identity_all;
COMMENT ON COLUMN f360.products.wc_product_id IS NULL;
COMMENT ON COLUMN f360.product_variants.wc_variation_id IS NULL;
