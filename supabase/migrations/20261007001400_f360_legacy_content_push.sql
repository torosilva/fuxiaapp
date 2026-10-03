-- Fuxia 360 — content of the CURRENT store's products comes from Fuxia 360 (STAGING only). Decision: Mario 2026-10-02
-- ("Sí, todo, solo staging4"): photos, description, price (base + other currencies) and the colour name that Carolina
-- edits in Fuxia 360 overwrite what the legacy Woo products of a NON-production target show. Supersedes, for staging
-- only, "No cambiar los 129 productos Woo" (D2). Production targets are refused here; that needs a separate approval.
--   * Never touched: SKU, slug, status/visibility, stock (the stock push owns it), attributes, categories.
--   * A legacy Woo product maps to ONE Fuxia 360 model and one or more of its colours (f360.legacy_woo_map, confirmed).
--     Its gallery = the photos of those colours, in colour order. Name = model name + colour name when it is one colour.
--   * Photos are uploaded once per target and remembered (f360.woo_media_links) so a later push reuses them.
--   * Every push is recorded (f360.legacy_content_pushes): who, which store product, what was sent, the result.
-- Rollback: supabase/rollbacks/20261007001400_f360_legacy_content_push.down.sql

CREATE TABLE f360.legacy_content_pushes (
  id              bigserial PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_product_id  integer NOT NULL,
  product_id      uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  requested_by    text NOT NULL,
  ok              boolean NOT NULL,
  message         text,
  sent            jsonb NOT NULL DEFAULT '{}',
  at              timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX legacy_content_pushes_idx ON f360.legacy_content_pushes (target_id, woo_product_id, at DESC);

CREATE FUNCTION f360.content_target(p_target_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND active;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Esa tienda no existe.'; END IF;
  IF t.is_production THEN RAISE EXCEPTION 'Mandar contenido a la tienda de producción no está aprobado.'; END IF;
  RETURN t;
END $$;

-- Store products to update (optionally only those of some models), with when each was last pushed.
CREATE FUNCTION public.f360_legacy_content_list(p_target_key text, p_product_ids uuid[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.content_target(p_target_key);
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', x.woo_product_id, 'product_id', x.product_id, 'name', x.name,
      'last_push', (SELECT max(at) FROM f360.legacy_content_pushes cp WHERE cp.target_id = t.id AND cp.woo_product_id = x.woo_product_id AND cp.ok))
      ORDER BY x.name, x.woo_product_id), '[]')
    FROM (SELECT DISTINCT m.woo_product_id, v.product_id, p.name
          FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id JOIN f360.products p ON p.id = v.product_id
          WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
            AND (p_product_ids IS NULL OR v.product_id = ANY (p_product_ids))) x);
END $$;

-- Everything the Edge Function needs to write ONE store product (service only).
CREATE FUNCTION public.f360_legacy_content_snapshot(p_target_key text, p_woo_product_id int) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.content_target(p_target_key); v_pid uuid; n int;
BEGIN
  SELECT count(DISTINCT v.product_id), min(v.product_id::text)::uuid INTO n, v_pid
    FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
    WHERE m.target_id = t.id AND m.woo_product_id = p_woo_product_id AND m.status = 'confirmado';
  IF n = 0 THEN RAISE EXCEPTION 'Ese producto de la tienda no está homologado.'; END IF;
  IF n > 1 THEN RAISE EXCEPTION 'Ese producto de la tienda está ligado a más de un modelo; revísalo en Homologación.'; END IF;
  RETURN (SELECT jsonb_build_object(
    'woo_product_id', p_woo_product_id, 'base_url', t.base_url,
    'product', jsonb_build_object('id', p.id, 'name', p.name, 'description', p.description, 'short_description', p.short_description,
       'regular_price', p.regular_price, 'sale_price', p.sale_price),
    'prices', (SELECT coalesce(jsonb_agg(jsonb_build_object('woo_meta_key', c.woo_meta_key, 'amount', pp.amount) ORDER BY c.sort), '[]')
               FROM f360.product_prices pp JOIN f360.currencies c ON c.code = pp.currency_code AND c.active AND NOT c.is_base WHERE pp.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'media',
         (SELECT coalesce(jsonb_agg(jsonb_build_object('id', md.id, 'path', md.storage_path, 'alt', md.alt, 'woo_media_id', wl.woo_media_id) ORDER BY md.sort, md.created_at), '[]')
          FROM f360.product_media md LEFT JOIN f360.woo_media_links wl ON wl.media_id = md.id AND wl.target_id = t.id WHERE md.color_id = c.id))
         ORDER BY c.sort, c.name), '[]')
       FROM f360.product_colors c WHERE c.id IN (SELECT v.color_id FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
                                                  WHERE m.target_id = t.id AND m.woo_product_id = p_woo_product_id AND m.status = 'confirmado')),
    'variations', (SELECT coalesce(jsonb_agg(m.woo_variation_id ORDER BY m.woo_variation_id), '[]') FROM f360.legacy_woo_map m
                   WHERE m.target_id = t.id AND m.woo_product_id = p_woo_product_id AND m.status = 'confirmado'))
    FROM f360.products p WHERE p.id = v_pid);
END $$;

CREATE FUNCTION public.f360_legacy_content_result(p_target_key text, p_woo_product_id int, p_product_id uuid, p_by text, p_ok boolean,
  p_message text, p_sent jsonb, p_media jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.content_target(p_target_key); x jsonb;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_media, '[]')) LOOP
    INSERT INTO f360.woo_media_links (target_id, media_id, woo_media_id) VALUES (t.id, (x->>'media_id')::uuid, (x->>'woo_media_id')::int)
      ON CONFLICT (target_id, media_id) DO UPDATE SET woo_media_id = EXCLUDED.woo_media_id, linked_at = now();
  END LOOP;
  INSERT INTO f360.legacy_content_pushes (target_id, woo_product_id, product_id, requested_by, ok, message, sent)
    VALUES (t.id, p_woo_product_id, p_product_id, coalesce(nullif(btrim(p_by), ''), 'Sistema'), p_ok, left(p_message, 500), coalesce(p_sent, '{}'));
END $$;

REVOKE ALL ON f360.legacy_content_pushes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.legacy_content_pushes TO service_role;
GRANT USAGE ON SEQUENCE f360.legacy_content_pushes_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_legacy_content_list(text, uuid[]), public.f360_legacy_content_snapshot(text, int),
  public.f360_legacy_content_result(text, int, uuid, text, boolean, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_legacy_content_list(text, uuid[]), public.f360_legacy_content_snapshot(text, int),
  public.f360_legacy_content_result(text, int, uuid, text, boolean, text, jsonb, jsonb) TO service_role;
