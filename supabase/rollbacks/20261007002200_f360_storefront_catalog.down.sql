-- Rollback of 20261007002200.
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
    'regular_price', p.regular_price, 'sale_price', p.sale_price, 'make_to_order', p.make_to_order,
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
DROP FUNCTION IF EXISTS public.f360_storefront_catalog(text);
DROP FUNCTION IF EXISTS public.f360_set_product_new(uuid, boolean);
ALTER TABLE f360.products DROP COLUMN IF EXISTS new_override;
