-- Fuxia 360 · pase C6 — shop search / filters answer for production (same as migration 20261012000600). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · shop search / filters on fuxiaballerinas.com (Mario 2026-10-06: "no aparece por ningún lado el buscador").
-- f360_storefront_catalog (the /tienda/ search, colour/size filters, "Más vendidas" / "Nuevas") answered only for an ACTIVE
-- channel; production's channel stays inactive until stock sync is approved, so the search box hid itself. The catalog now
-- also answers for a channel whose CATALOG is on (U1 capability, owner-controlled). Same public data as before: names,
-- colours, size states (inmediata / pedido / agotado), units sold — no quantities, prices or customers. Nothing else changes:
-- stock, orders, promise and Avísame still require an active channel.
-- Rollback: supabase/rollbacks/20261012000600_f360_catalog_when_catalog_on.down.sql
CREATE OR REPLACE FUNCTION public.f360_storefront_catalog(p_target_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RETURN jsonb_build_object('items', '[]'::jsonb); END IF;
  RETURN (WITH
    -- which store product sells which Fuxia 360 size: published/merged links + homologated legacy products not merged
    rows AS (
      SELECT coalesce(vl.woo_product_id, pl.woo_product_id) AS woo_product_id, vl.variant_id
        FROM f360.woo_variant_links vl LEFT JOIN f360.product_variants v ON v.id = vl.variant_id
        LEFT JOIN f360.woo_product_links pl ON pl.target_id = t.id AND pl.product_id = v.product_id
        WHERE vl.target_id = t.id
      UNION
      SELECT m.woo_product_id, m.confirmed_variant_id FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
        WHERE m.target_id = t.id AND m.status = 'confirmado' AND NOT f360.is_consolidated(t.id, v.product_id)),
    sizes AS (
      SELECT r.woo_product_id, v.product_id, v.color_id, v.size_label,
             CASE WHEN f360.online_ats(v.id, t.fulfillment_location_id) > 0 THEN 'inmediata'
                  WHEN p.make_to_order THEN 'pedido' ELSE 'agotado' END AS state
      FROM rows r JOIN f360.product_variants v ON v.id = r.variant_id AND v.status = 'active' JOIN f360.products p ON p.id = v.product_id AND p.status = 'active'
      WHERE r.woo_product_id IS NOT NULL),
    sold AS (
      SELECT v.product_id, sum(q)::int AS units FROM (
        SELECT i.variant_id, i.quantity AS q FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
          WHERE i.variant_id IS NOT NULL AND s.created_at > now() - interval '60 days'
        UNION ALL
        SELECT l.variant_id, l.quantity FROM f360.woo_order_lines l WHERE l.variant_id IS NOT NULL AND l.outcome IN ('sold', 'sobre_pedido') AND l.created_at > now() - interval '60 days'
        UNION ALL
        SELECT m.confirmed_variant_id, m.sold_90d FROM f360.legacy_woo_map m WHERE m.target_id = t.id AND m.status = 'confirmado' AND m.sold_90d > 0
      ) x JOIN f360.product_variants v ON v.id = x.variant_id GROUP BY v.product_id)
    SELECT jsonb_build_object('generated_at', now(), 'items', coalesce(jsonb_agg(jsonb_build_object(
        'woo_product_id', w.woo_product_id, 'product_id', p.id, 'name', p.name, 'category', p.category_key,
        'is_new', coalesce(p.new_override, p.created_at > now() - interval '45 days'
                    AND NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE v.product_id = p.id)),
        'sold', coalesce(s.units, 0), 'colors', w.colors) ORDER BY p.name, w.woo_product_id), '[]'::jsonb))
    FROM (SELECT z.woo_product_id, z.product_id, jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex, 'sizes', z.sizes) ORDER BY c.sort, c.name) AS colors
          FROM (SELECT woo_product_id, product_id, color_id, jsonb_object_agg(size_label, state) AS sizes FROM sizes GROUP BY woo_product_id, product_id, color_id) z
          JOIN f360.product_colors c ON c.id = z.color_id GROUP BY z.woo_product_id, z.product_id) w
    JOIN f360.products p ON p.id = w.product_id LEFT JOIN sold s ON s.product_id = p.id);
END $function$;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012000600', 'f360_catalog_when_catalog_on', '{}');
COMMIT;
