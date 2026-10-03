-- Rollback of 20261007000800_f360_catalog_tidy.sql. Colours already removed are not restored (their removal is in
-- f360.catalog_changes until this rollback drops it — export it first if needed).
CREATE OR REPLACE FUNCTION public.f360_list_products(p_query text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'last_activity') DESC NULLS LAST, x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'name', p.name, 'code', p.code, 'category', cat.name, 'image_path', f360.product_primary_image(p.id),
      'regular_price', p.regular_price, 'sale_price', p.sale_price,
      'ready', (f360.product_readiness(p.id)->>'ready')::boolean,
      'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex) ORDER BY c.sort, c.name), '[]'::jsonb)
                 FROM f360.product_colors c WHERE c.product_id = p.id),
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id <> f360.transit_location()),
      'in_transit', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id = f360.transit_location()),
      'last_activity', greatest(p.updated_at, (SELECT max(b.updated_at) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))) AS x
    FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key
    WHERE p.status = 'active'
      AND (p_query IS NULL OR btrim(p_query) = '' OR p.name ILIKE '%' || btrim(p_query) || '%'
           OR EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id AND c.name ILIKE '%' || btrim(p_query) || '%'))
  ) s);
END $$;

DROP FUNCTION IF EXISTS public.f360_remove_color(uuid, text);
DROP FUNCTION IF EXISTS public.f360_color_remove_state(uuid);
DROP FUNCTION IF EXISTS f360.color_remove_blockers(uuid);
DROP TABLE IF EXISTS f360.catalog_changes;
DROP FUNCTION IF EXISTS f360.catalog_changes_append_only();
