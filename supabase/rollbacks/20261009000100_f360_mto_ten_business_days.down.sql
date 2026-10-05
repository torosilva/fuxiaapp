-- Rollback of 20261009000100: ship_by back to the 7th business day (the 20261007001500 definition).
CREATE OR REPLACE FUNCTION public.f360_made_to_order_list(p_days int DEFAULT 60) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'order', m.woo_order_id, 'store', t.name, 'product', p.name, 'color', c.name,
      'size', v.size_label, 'sku', v.sku, 'quantity', m.quantity, 'status', m.status, 'created_at', m.created_at, 'updated_at', m.updated_at,
      'updated_by', m.updated_by, 'note', m.note,
      'ship_by', (SELECT d FROM generate_series(m.created_at::date + 1, m.created_at::date + 14, interval '1 day') d
                  WHERE extract(isodow FROM d) < 6 OFFSET 6 LIMIT 1)::date)          -- 7th business day
      ORDER BY (m.status IN ('pendiente', 'en_proceso')) DESC, m.created_at DESC), '[]')
    FROM f360.made_to_order m JOIN f360.sales_targets t ON t.id = m.target_id JOIN f360.product_variants v ON v.id = m.variant_id
    JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
    WHERE m.created_at > now() - make_interval(days => greatest(1, least(p_days, 365))));
END $$;
