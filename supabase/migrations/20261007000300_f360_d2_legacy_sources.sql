-- Fuxia 360 Track D · D2 — Where each colour of an adopted model comes from in the store (STAGING). Read-only, additive.
-- Lets the admin bring the store's existing photos, price and description into the F360 model (missing fields only,
-- through the normal f360_update_product / f360_add_media RPCs, as the person). Nothing is written to Woo.
-- Rollback: supabase/rollbacks/20261007000300_f360_d2_legacy_sources.down.sql

CREATE FUNCTION public.f360_legacy_sources(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('color_id', x.color_id, 'color', x.color, 'woo_product_id', x.woo_product_id,
      'woo_product_name', x.woo_product_name, 'target_key', x.key, 'target_name', x.name, 'base_url', x.base_url, 'variations', x.n)
      ORDER BY x.sort, x.color, x.woo_product_id), '[]')
    FROM (SELECT c.id AS color_id, c.name AS color, c.sort, m.woo_product_id, min(m.woo_product_name) AS woo_product_name,
                 t.key, t.name, t.base_url, count(*) AS n
          FROM f360.legacy_woo_map m
          JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
          JOIN f360.product_colors c ON c.id = v.color_id
          JOIN f360.sales_targets t ON t.id = m.target_id
          WHERE v.product_id = p_product_id AND m.status = 'confirmado' AND NOT t.is_production
          GROUP BY c.id, c.name, c.sort, m.woo_product_id, t.key, t.name, t.base_url) x);
END $$;

REVOKE ALL ON FUNCTION public.f360_legacy_sources(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_legacy_sources(uuid) TO authenticated, service_role;
