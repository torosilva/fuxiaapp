-- Rollback of 20261012000900: back to V1. Append-only: add-to-cart rows stay (the constraint is re-added NOT VALID); V1 functions restored.
ALTER TABLE f360.favorite_events DROP CONSTRAINT favorite_events_event_check;
ALTER TABLE f360.favorite_events ADD CONSTRAINT favorite_events_event_check CHECK (event IN ('favorite_added', 'favorite_removed')) NOT VALID;

CREATE OR REPLACE FUNCTION public.f360_favorite_record(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; anon uuid; ev text := p->>'event'; mk text := lower(coalesce(p->>'market', ''));
  wp int; wv int; prod uuid; col uuid; var uuid; color_name text := nullif(btrim(coalesce(p->>'color', '')), '');
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p->>'target_key' AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  IF ev NOT IN ('favorite_added', 'favorite_removed') THEN RAISE EXCEPTION 'Evento no válido.'; END IF;
  IF mk NOT IN ('mx', 'co') THEN RAISE EXCEPTION 'Mercado no válido.'; END IF;
  BEGIN anon := (p->>'anon_id')::uuid; EXCEPTION WHEN OTHERS THEN anon := NULL; END;
  IF anon IS NULL THEN RAISE EXCEPTION 'Visitante no válido.'; END IF;
  wp := CASE WHEN (p->>'woo_product_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_product_id')::int END;
  wv := CASE WHEN (p->>'woo_variation_id') ~ '^[0-9]{1,9}$' THEN (p->>'woo_variation_id')::int END;
  IF coalesce(wp, 0) <= 0 THEN RAISE EXCEPTION 'Producto no válido.'; END IF;

  INSERT INTO f360.anon_visitors (anon_id) VALUES (anon) ON CONFLICT (anon_id) DO UPDATE SET last_seen = clock_timestamp();
  IF (SELECT count(*) FROM f360.favorite_events WHERE anon_id = anon AND at > clock_timestamp() - interval '1 hour') >= 120 THEN
    RETURN jsonb_build_object('ok', false, 'limited', true);
  END IF;

  -- canonical identity: published / merged product → its model; old store product → the model it was homologated to
  SELECT pl.product_id INTO prod FROM f360.woo_product_links pl WHERE pl.target_id = t.id AND pl.woo_product_id = wp;
  IF prod IS NULL THEN
    SELECT v.product_id INTO prod FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.woo_product_id = wp AND m.status = 'confirmado' GROUP BY v.product_id ORDER BY count(*) DESC LIMIT 1;
  END IF;
  IF wv IS NOT NULL THEN
    SELECT vl.variant_id INTO var FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND vl.woo_variation_id = wv;
    IF var IS NULL THEN
      SELECT m.confirmed_variant_id INTO var FROM f360.legacy_woo_map m WHERE m.target_id = t.id AND m.woo_variation_id = wv AND m.status = 'confirmado' LIMIT 1;
    END IF;
    IF var IS NOT NULL THEN SELECT v.color_id, coalesce(prod, v.product_id) INTO col, prod FROM f360.product_variants v WHERE v.id = var; END IF;
  END IF;
  IF col IS NULL AND prod IS NOT NULL AND color_name IS NOT NULL THEN
    SELECT c.id INTO col FROM f360.product_colors c WHERE c.product_id = prod AND lower(btrim(c.name)) = lower(color_name) LIMIT 1;
  END IF;

  INSERT INTO f360.favorite_events (anon_id, event, target_id, market, woo_product_id, woo_variation_id, product_id, color_id, variant_id)
    VALUES (anon, ev, t.id, mk, wp, wv, prod, col, var);
  RETURN jsonb_build_object('ok', true, 'identified', prod IS NOT NULL);
END $$;


CREATE OR REPLACE FUNCTION public.f360_favorites_report(p_target_key text, p_days integer DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; d int := greatest(1, least(coalesce(p_days, 30), 365));
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND (active OR catalog_mode = 'on');
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  RETURN (WITH
    ev AS (SELECT e.*, coalesce(e.product_id::text, 'woo:' || e.woo_product_id) AS k FROM f360.favorite_events e WHERE e.target_id = t.id),
    latest AS (SELECT DISTINCT ON (anon_id, woo_product_id) anon_id, woo_product_id, k, event FROM ev ORDER BY anon_id, woo_product_id, id DESC),
    active AS (SELECT k, count(DISTINCT anon_id) AS n FROM latest WHERE event = 'favorite_added' GROUP BY k),
    win AS (SELECT k, count(*) FILTER (WHERE event = 'favorite_added') AS adds, count(*) FILTER (WHERE event = 'favorite_removed') AS removes
            FROM ev WHERE at > now() - make_interval(days => d) GROUP BY k),
    sold AS (SELECT v.product_id::text AS k, sum(q)::int AS units FROM (
               SELECT i.variant_id, i.quantity AS q FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id
                 WHERE i.variant_id IS NOT NULL AND s.created_at > now() - make_interval(days => d)
               UNION ALL
               SELECT l.variant_id, l.quantity FROM f360.woo_order_lines l WHERE l.variant_id IS NOT NULL AND l.outcome IN ('sold', 'sobre_pedido')
                 AND l.created_at > now() - make_interval(days => d)) x
             JOIN f360.product_variants v ON v.id = x.variant_id GROUP BY v.product_id),
    keys AS (SELECT k FROM active UNION SELECT k FROM win)
    SELECT jsonb_build_object('days', d, 'generated_at', now(), 'atc_captured', false,
      'rows', coalesce(jsonb_agg(jsonb_build_object(
        'key', keys.k, 'product_id', p.id, 'model', coalesce(p.name, 'Producto de la tienda #' || substr(keys.k, 5)),
        'identified', p.id IS NOT NULL, 'active', coalesce(a.n, 0), 'adds', coalesce(w.adds, 0), 'removes', coalesce(w.removes, 0),
        'atc', NULL, 'sold', CASE WHEN p.id IS NULL THEN NULL ELSE coalesce(s.units, 0) END)
        ORDER BY coalesce(a.n, 0) DESC, coalesce(w.adds, 0) DESC, coalesce(p.name, keys.k)), '[]'::jsonb))
    FROM keys LEFT JOIN active a ON a.k = keys.k LEFT JOIN win w ON w.k = keys.k LEFT JOIN sold s ON s.k = keys.k
    LEFT JOIN f360.products p ON p.id::text = keys.k);
END $$;

