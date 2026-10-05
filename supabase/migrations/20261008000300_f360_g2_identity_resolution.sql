-- Fuxia 360 G2-B2.1 — Canonical identity RESOLUTION layer (STAGING). Decision: Mario 2026-10-04 (INVENTORY_MODEL.md §1.1).
-- PRODUCT → COMMERCIAL VARIANT → INVENTORY BY LOCATION → SALES CHANNEL. Woo product/variation ids are external channel ids.
-- NO new source of truth: these are VIEWS over the existing tables
--   f360.woo_variant_links (current) · f360.retired_woo_links (historic) · f360.legacy_woo_map (Carolina's confirmed homologation)
--   f360.product_variants.sku (canonical SKU F360-{MODELO}-{COLOR}-{TALLA}) · f360.products.code (F360-{MODELO}).
-- One canonical variant may own several Woo variation ids over time (current + retired). Resolution priority per
-- (channel, woo_variation_id): current link > retired link > confirmed homologation. Nothing is ever guessed by name.
-- Commerce Facts: commerce_order_lines gains channel_sku / canonical_sku through this layer (approved exception to the G1
-- freeze, identity resolution only). Facts (commerce_woo_* tables), money rules and idempotency are untouched.
-- Rollback: supabase/rollbacks/20261008000300_f360_g2_identity_resolution.down.sql

-- ── Every channel id ↔ canonical variant relation (may contain several rows per Woo variation) ──
CREATE VIEW f360.channel_variant_identity_all AS
  SELECT vl.target_id AS sales_channel_id, vl.woo_variation_id::bigint AS woo_variation_id,
         coalesce(vl.woo_product_id, pl.woo_product_id)::bigint AS woo_product_id,
         vl.variant_id AS canonical_variant_id,
         'current'::text AS link_state, 'woo_variant_links'::text AS link_source, vl.origin AS link_origin,
         -- F360-published variations carry the canonical SKU in Woo by construction (publisher + sku_mismatch guard);
         -- adopted legacy variations have no SKU of their own (they inherit the parent's, a reference only).
         CASE WHEN vl.origin = 'f360_published' THEN v.sku ELSE m.woo_parent_sku END AS woocommerce_sku,
         CASE WHEN vl.origin = 'f360_published' THEN 'canonical_by_publisher' WHEN m.woo_parent_sku IS NOT NULL THEN 'legacy_parent_reference' END AS woocommerce_sku_scope,
         vl.linked_at AS valid_from, NULL::timestamptz AS valid_to, 1 AS resolution_priority
  FROM f360.woo_variant_links vl
  JOIN f360.product_variants v ON v.id = vl.variant_id
  LEFT JOIN f360.woo_product_links pl ON pl.target_id = vl.target_id AND pl.product_id = v.product_id
  LEFT JOIN f360.legacy_woo_map m ON m.target_id = vl.target_id AND m.woo_variation_id = vl.woo_variation_id
  UNION ALL
  SELECT rl.target_id, rl.woo_variation_id::bigint, coalesce(rl.woo_product_id, m.woo_product_id)::bigint, rl.variant_id,
         'retired', 'retired_woo_links', 'legacy_retired',
         m.woo_parent_sku, CASE WHEN m.woo_parent_sku IS NOT NULL THEN 'legacy_parent_reference' END,
         m.decided_at, rl.retired_at, 2
  FROM f360.retired_woo_links rl
  LEFT JOIN f360.legacy_woo_map m ON m.target_id = rl.target_id AND m.woo_variation_id = rl.woo_variation_id
  UNION ALL
  SELECT m.target_id, m.woo_variation_id::bigint, m.woo_product_id::bigint, m.confirmed_variant_id,
         'homologated', 'legacy_woo_map', 'legacy_homologated',
         m.woo_parent_sku, CASE WHEN m.woo_parent_sku IS NOT NULL THEN 'legacy_parent_reference' END,
         m.decided_at, NULL, 3
  FROM f360.legacy_woo_map m
  WHERE m.status = 'confirmado';
COMMENT ON VIEW f360.channel_variant_identity_all IS 'G2-B2.1: every (channel, Woo variation) ↔ canonical variant relation from current links, retired links and confirmed homologation. Resolution layer only; not a source of truth.';

-- ── Resolved: exactly one canonical identity per (channel, Woo variation) ──
CREATE VIEW f360.channel_variant_identity AS
  SELECT DISTINCT ON (a.sales_channel_id, a.woo_variation_id)
         a.sales_channel_id, t.key AS sales_channel_key, a.woo_product_id, a.woo_variation_id, a.woocommerce_sku, a.woocommerce_sku_scope,
         a.canonical_variant_id, v.sku AS canonical_sku, v.product_id AS canonical_product_id,
         'F360-' || p.code AS canonical_product_key, p.code AS product_code,
         a.link_state, a.link_source, a.link_origin, a.valid_from, a.valid_to,
         count(*) OVER (PARTITION BY a.sales_channel_id, a.woo_variation_id) AS relations,
         (min(a.canonical_variant_id::text) OVER (PARTITION BY a.sales_channel_id, a.woo_variation_id)
           <> max(a.canonical_variant_id::text) OVER (PARTITION BY a.sales_channel_id, a.woo_variation_id)) AS ambiguous
  FROM f360.channel_variant_identity_all a
  JOIN f360.sales_targets t ON t.id = a.sales_channel_id
  JOIN f360.product_variants v ON v.id = a.canonical_variant_id
  JOIN f360.products p ON p.id = v.product_id
  ORDER BY a.sales_channel_id, a.woo_variation_id, a.resolution_priority;
COMMENT ON VIEW f360.channel_variant_identity IS 'G2-B2.1: the ONE place to translate a Woo variation id (per sales channel) to the canonical variant / SKU. Priority current > retired > homologated.';

-- ── Product level: Woo product id ↔ canonical product (a legacy parent can only map through its homologated variants) ──
CREATE VIEW f360.channel_product_identity AS
  SELECT pl.target_id AS sales_channel_id, pl.woo_product_id::bigint AS woo_product_id, pl.product_id AS canonical_product_id,
         'F360-' || p.code AS canonical_product_key, 'current'::text AS link_state, 'woo_product_links'::text AS link_source
  FROM f360.woo_product_links pl JOIN f360.products p ON p.id = pl.product_id
  UNION
  SELECT DISTINCT a.sales_channel_id, a.woo_product_id, v.product_id, 'F360-' || p.code, a.link_state, a.link_source
  FROM f360.channel_variant_identity_all a
  JOIN f360.product_variants v ON v.id = a.canonical_variant_id JOIN f360.products p ON p.id = v.product_id
  WHERE a.woo_product_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM f360.woo_product_links pl2 WHERE pl2.target_id = a.sales_channel_id AND pl2.woo_product_id = a.woo_product_id);
COMMENT ON VIEW f360.channel_product_identity IS 'G2-B2.1: Woo product id (per channel) ↔ canonical product. A legacy parent may map to more than one canonical product (e.g. "any colour" products); consumers must handle it.';

-- ── Commerce Facts lines: same columns as G1 + identity columns appended (facts and money untouched) ──
CREATE OR REPLACE VIEW f360.commerce_order_lines AS
  SELECT 'woo'::text AS source_system, t.key || ':' || l.woo_order_id AS external_ref, l.woo_line_id::text AS line_ref,
         ci.canonical_variant_id AS variant_id, ci.canonical_product_id AS product_id, p.category_key,
         CASE WHEN ci.link_state = 'current' THEN 'woo_variant_link' WHEN ci.link_state = 'retired' THEN 'retired_woo_link'
              WHEN ci.link_state = 'homologated' THEN 'legacy_homologation' ELSE 'unresolved' END AS product_resolution,
         l.sku, l.woo_product_id, l.woo_variation_id, l.quantity,
         CASE WHEN l.quantity > 0 THEN round(l.total / l.quantity, 2) END AS unit_net,
         l.subtotal AS gross, l.subtotal - l.total AS discount, l.total AS net, l.total_tax AS tax,
         l.list_price_hint, l.list_price_source, o.currency AS currency_original,
         l.sku AS channel_sku, ci.canonical_sku, ci.canonical_product_key,
         coalesce(ci.link_state, 'unresolved') AS identity_link_state, ci.link_source AS identity_source
  FROM f360.commerce_woo_order_lines l
  JOIN f360.commerce_woo_orders o ON o.target_id = l.target_id AND o.woo_order_id = l.woo_order_id
  JOIN f360.sales_targets t ON t.id = l.target_id
  LEFT JOIN f360.channel_variant_identity ci ON ci.sales_channel_id = l.target_id AND ci.woo_variation_id = l.woo_variation_id
  LEFT JOIN f360.products p ON p.id = ci.canonical_product_id
  UNION ALL
  SELECT 'f360_store', 'store_sale:' || i.sale_id, i.line_no::text, i.variant_id, v.product_id, p.category_key,
         CASE WHEN i.variant_id IS NOT NULL THEN 'f360_variant' ELSE 'legacy_store_item' END,
         i.sku, NULL, NULL, i.quantity, i.unit_price, i.line_total, 0, i.line_total, 0, NULL, NULL, 'MXN',
         i.sku, v.sku, CASE WHEN p.code IS NOT NULL THEN 'F360-' || p.code END,
         CASE WHEN i.variant_id IS NOT NULL THEN 'f360_store_sale' ELSE 'unresolved' END,
         CASE WHEN i.variant_id IS NOT NULL THEN 'offline_sale_items' END
  FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id AND s.created_by_rpc
  LEFT JOIN f360.product_variants v ON v.id = i.variant_id LEFT JOIN f360.products p ON p.id = v.product_id;

-- ── Dormant duplicated identity columns: DEPRECATED (kept; removal is a future unit) ──
COMMENT ON COLUMN f360.products.wc_product_id IS 'DEPRECATED (G2-B2.1): unused duplicated identity. Woo ids live in woo_product_links per channel. Do not read or write.';
COMMENT ON COLUMN f360.product_variants.wc_variation_id IS 'DEPRECATED (G2-B2.1): unused duplicated identity. Woo ids live in woo_variant_links / retired_woo_links per channel. Do not read or write.';

REVOKE ALL ON f360.channel_variant_identity_all, f360.channel_variant_identity, f360.channel_product_identity FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.channel_variant_identity_all, f360.channel_variant_identity, f360.channel_product_identity, f360.commerce_order_lines TO service_role;
