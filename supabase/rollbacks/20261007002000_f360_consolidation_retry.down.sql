-- Rollback of 20261007002000: restores f360_consolidate_start from 20261007001900.
CREATE OR REPLACE FUNCTION public.f360_consolidate_start(p_target_key text, p_product_ids uuid[] DEFAULT NULL, p_legacy_paths jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; x record; ready jsonb; job jsonb; out jsonb := '[]'; skipped jsonb := '[]'; legacy jsonb;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  IF t.is_production THEN RAISE EXCEPTION 'Unir productos en la tienda de producción no está aprobado.'; END IF;
  FOR x IN SELECT v.product_id, p.name, count(DISTINCT m.woo_product_id) AS n
           FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id JOIN f360.products p ON p.id = v.product_id
           WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
             AND (p_product_ids IS NULL OR v.product_id = ANY (p_product_ids))
           GROUP BY v.product_id, p.name ORDER BY p.name LOOP
    IF p_product_ids IS NULL AND x.n < 2 THEN CONTINUE; END IF;
    IF f360.is_consolidated(t.id, x.product_id) THEN
      SELECT jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job_id, 'status', status) INTO job
        FROM f360.legacy_consolidations WHERE target_id = t.id AND product_id = x.product_id;
      out := out || job; CONTINUE;
    END IF;
    ready := f360.product_readiness(x.product_id);
    IF NOT (ready->>'ready')::boolean THEN
      skipped := skipped || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'missing', ready->'missing'); CONTINUE;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', w.woo_product_id, 'name', w.name, 'path', p_legacy_paths->>(w.woo_product_id::text)) ORDER BY w.woo_product_id), '[]')
      INTO legacy FROM (SELECT DISTINCT m.woo_product_id, min(m.woo_product_name) AS name FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
                        WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id GROUP BY m.woo_product_id) w;
    INSERT INTO f360.legacy_consolidations (target_id, product_id, legacy_products, requested_by) VALUES (t.id, x.product_id, legacy, r.display_name);
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT vl.target_id, vl.woo_variation_id, vl.woo_product_id, vl.variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    -- also every confirmed legacy variation that was never linked (orders can still name it)
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT m.target_id, m.woo_variation_id, m.woo_product_id, m.confirmed_variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    DELETE FROM f360.stock_sync_queue q USING f360.woo_variant_links vl, f360.product_variants v
      WHERE q.target_id = t.id AND q.variant_id = vl.variant_id AND vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    DELETE FROM f360.woo_variant_links vl USING f360.product_variants v
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    job := public.f360_request_publish(x.product_id, gen_random_uuid(), p_target_key);
    UPDATE f360.legacy_consolidations SET job_id = (job->>'id')::uuid WHERE target_id = t.id AND product_id = x.product_id;
    out := out || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job->>'id', 'status', 'publicando');
  END LOOP;
  RETURN jsonb_build_object('items', out, 'skipped', skipped);
END $$;
