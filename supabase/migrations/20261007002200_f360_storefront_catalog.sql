-- Fuxia 360 — what the store's shop page needs to help customers find things fast (STAGING). Decision: Mario 2026-10-03.
--   * Filters by colour, size (shown as Mexican size by the store) and model, with "Entrega inmediata" = a pair in Bodega
--     CDMX or any store (stores are warehouses too, 20261007002100), "5 a 7 días" = no stock but sold anyway (make_to_order).
--   * "Más vendidas": units sold in the last 60 days in EVERY channel (online orders + stores) plus, while Fuxia 360 has
--     little history, the store's own sales of the last 90 days read at homologation (legacy_woo_map.sold_90d).
--   * "Nuevas": models registered in Fuxia 360 in the last 45 days that did NOT come from the old store catalog, or that
--     Carolina marks by hand (products.new_override: true = always new, false = never, NULL = automatic).
--   Public (anon) and read-only: model names, colours, sizes and availability states only — never quantities or prices.
-- Rollback: supabase/rollbacks/20261007002200_f360_storefront_catalog.down.sql

ALTER TABLE f360.products ADD COLUMN new_override boolean;

CREATE FUNCTION public.f360_set_product_new(p_product_id uuid, p_value boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; p f360.products;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO p FROM f360.products WHERE id = p_product_id FOR UPDATE;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Ese modelo no existe.'; END IF;
  UPDATE f360.products SET new_override = p_value, updated_at = now() WHERE id = p.id;
  INSERT INTO f360.catalog_changes (product_id, what, detail, actor_auth_user_id, actor_name)
    VALUES (p.id, 'new_override', jsonb_build_object('from', p.new_override, 'to', p_value), r.auth_user_id, r.display_name);
  RETURN jsonb_build_object('product_id', p.id, 'new_override', p_value);
END $$;

CREATE FUNCTION public.f360_storefront_catalog(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND active;
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
END $$;

-- f360_get_product: unchanged from 20261007001700 plus 'new_override'
CREATE OR REPLACE FUNCTION public.f360_get_product(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE result jsonb; online f360.locations; v_transit uuid := f360.transit_location();
BEGIN
  PERFORM f360.require_role('viewer');
  online := f360.online_location();
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.name, 'code', p.code, 'codes_locked', p.codes_locked_at IS NOT NULL,
    'category', cat.name, 'category_key', p.category_key,
    'description', p.description, 'short_description', p.short_description,
    'regular_price', p.regular_price, 'sale_price', p.sale_price, 'make_to_order', p.make_to_order, 'new_override', p.new_override,
    'image_path', f360.product_primary_image(p.id),
    'readiness', f360.product_readiness(p.id),
    'online_location', CASE WHEN online.id IS NULL THEN NULL ELSE jsonb_build_object('id', online.id, 'name', online.name) END,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]'::jsonb) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'code', c.code, 'hex', c.hex, 'image_path', f360.color_primary_image(c.id),
        'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path) ORDER BY m.sort, m.created_at), '[]'::jsonb)
                  FROM f360.product_media m WHERE m.color_id = c.id),
        'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'size', v.size_label, 'sku', v.sku) ORDER BY ps.sort), '[]'::jsonb)
                     FROM f360.product_variants v JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
                     WHERE v.color_id = c.id AND v.status = 'active'),
        'balances', (SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', b.location_id, 'size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0 AND b.location_id <> v_transit),
        'in_transit', (SELECT coalesce(jsonb_agg(jsonb_build_object('size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0 AND b.location_id = v_transit))
        ORDER BY c.sort, c.created_at), '[]'::jsonb) FROM f360.product_colors c WHERE c.product_id = p.id),
    'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id <> v_transit),
    'in_transit', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id = v_transit))
  INTO result FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key WHERE p.id = p_product_id;
  IF result IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN result;
END $$;

REVOKE ALL ON FUNCTION public.f360_set_product_new(uuid, boolean), public.f360_storefront_catalog(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_set_product_new(uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_storefront_catalog(text) TO anon, authenticated, service_role;
