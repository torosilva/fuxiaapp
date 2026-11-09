-- Fuxia 360 · PRODUCCIÓN · 20261109000200_f360_shopify_link_by_name VERBATIM + liga de las 252 tallas pendientes
-- (Mario 2026-11-09: "¿por qué pasó eso de las 252 tallas?"). Probada en staging (13/13, 1278/1278 ligadas).
-- Solo agrega ligas nuevas del canal shopify_mx (nombre del modelo + color + talla, únicas); no cambia ninguna existente.
-- Reversión: supabase/rollbacks/20261109000200_f360_shopify_link_by_name.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261109000200') THEN RAISE EXCEPTION 'PRE: ya está'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261109000100') THEN RAISE EXCEPTION 'PRE: falta 20261109000100'; END IF;
  IF (SELECT count(*) FROM f360.woo_variant_links l JOIN f360.sales_targets t ON t.id = l.target_id WHERE t.key = 'shopify_mx') < 1026 THEN RAISE EXCEPTION 'PRE: ligas Shopify'; END IF;
END $$;
CREATE TEMP TABLE links_before ON COMMIT DROP AS
  SELECT l.woo_variation_id, l.variant_id FROM f360.woo_variant_links l JOIN f360.sales_targets t ON t.id = l.target_id WHERE t.key IN ('shopify_mx', 'woo_production');
-- Fuxia 360 · Shopify México: third rule for the automatic link (Mario 2026-11-09: "¿por qué pasó eso de las 252 tallas?").
-- 252 Shopify sizes (42 colours: Mafalda Studs, Stud Point, Croc, Knotty…) stayed unlinked. Their old Woo variations carried no
-- colour (only "Medida 37"), so neither rule of 20261109000100 could tell Negro 37 from Vino 37. The agency kept Fuxia 360's
-- model names as Shopify titles ("Mafalda Studs", "Stud Point", "Knotty"), so a third rule links by model NAME (exactly ONE
-- active Fuxia 360 product with that name) + colour + size, only where rules 1 and 2 found nothing. Same safety as before:
-- unique matches only, one pair ↔ one Shopify variant, existing links never changed. Read-only check in production: all 252
-- resolve to exactly one pair, none collides with the 1,026 links.
-- Rollback: supabase/rollbacks/20261109000200_f360_shopify_link_by_name.down.sql

-- Same as 20261109000100 + by_name.
CREATE OR REPLACE FUNCTION f360.shopify_link_variants(p_target_key text, p_woo_target_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; w f360.sales_targets; v_new int; v_total int; v_linked int; v_pending jsonb;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key AND kind = 'shopify';
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda Shopify % no configurada.', p_target_key; END IF;
  SELECT * INTO w FROM f360.sales_targets WHERE key = p_woo_target_key AND kind = 'woocommerce';
  IF w.id IS NULL THEN RAISE EXCEPTION 'Tienda Woo % no configurada.', p_woo_target_key; END IF;

  WITH s AS (SELECT * FROM f360.shopify_variants WHERE target_id = t.id
               AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.woo_variation_id = link_id)),
  prods AS (   -- the Fuxia 360 product behind the old Woo product (same slug)
    SELECT s.link_id sid, pl.product_id FROM s JOIN f360.woo_product_links pl ON pl.target_id = w.id AND pl.woo_product_id = s.woo_product_id
    UNION SELECT s.link_id, p.id FROM s JOIN f360.products p ON p.wc_product_id = s.woo_product_id),
  by_product AS (
    SELECT s.link_id sid, v.id vid FROM s JOIN prods ON prods.sid = s.link_id
      JOIN f360.product_variants v ON v.product_id = prods.product_id AND v.status = 'active' AND v.size_label = btrim(s.size)
      JOIN f360.product_colors c ON c.id = v.color_id AND f360.shopify_norm(c.name) = f360.shopify_norm(s.color)),
  by_variation AS (   -- the old Woo variation (its own colour + size) → whatever Fuxia 360 already knows about it
    SELECT s.link_id sid, coalesce(vl.variant_id, rl.variant_id, m.confirmed_variant_id) vid FROM s
      LEFT JOIN f360.woo_variant_links vl ON vl.target_id = w.id AND vl.woo_variation_id = s.woo_variation_id
      LEFT JOIN f360.retired_woo_links rl ON rl.target_id = w.id AND rl.woo_variation_id = s.woo_variation_id
      LEFT JOIN f360.legacy_woo_map m ON m.target_id = w.id AND m.woo_variation_id = s.woo_variation_id AND m.status = 'confirmado'
     WHERE s.woo_variation_id IS NOT NULL AND coalesce(vl.variant_id, rl.variant_id, m.confirmed_variant_id) IS NOT NULL),
  by_name AS (   -- 3) the agency kept Fuxia 360's model names as Shopify titles: same name (ONE active product) + colour + size
    SELECT s.link_id sid, v.id vid FROM s
      JOIN f360.products p ON p.status = 'active' AND f360.shopify_norm(p.name) = f360.shopify_norm(s.product_title)
       AND (SELECT count(*) FROM f360.products p2 WHERE p2.status = 'active' AND f360.shopify_norm(p2.name) = f360.shopify_norm(s.product_title)) = 1
      JOIN f360.product_variants v ON v.product_id = p.id AND v.status = 'active' AND v.size_label = btrim(s.size)
      JOIN f360.product_colors c ON c.id = v.color_id AND f360.shopify_norm(c.name) = f360.shopify_norm(s.color)),
  cand AS (SELECT sid, vid FROM by_product
           UNION SELECT sid, vid FROM by_variation WHERE sid NOT IN (SELECT sid FROM by_product)
           UNION SELECT sid, vid FROM by_name WHERE sid NOT IN (SELECT sid FROM by_product) AND sid NOT IN (SELECT sid FROM by_variation)),
  uniq AS (SELECT sid, min(vid::text)::uuid vid FROM cand GROUP BY sid HAVING count(DISTINCT vid) = 1),
  -- one Fuxia 360 pair ↔ one Shopify variant: two Shopify variants claiming the same pair are both left for review
  safe AS (SELECT u.* FROM uniq u WHERE (SELECT count(*) FROM uniq u2 WHERE u2.vid = u.vid) = 1
             AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.variant_id = u.vid))
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, woo_product_id, origin)
    SELECT t.id, safe.vid, safe.sid, p.link_id, 'legacy_adopted' FROM safe
      JOIN f360.shopify_variants s ON s.target_id = t.id AND s.link_id = safe.sid
      JOIN f360.shopify_products p ON p.target_id = t.id AND p.shopify_product_id = s.shopify_product_id
    ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_new = ROW_COUNT;

  SELECT count(*), count(l.variant_id) INTO v_total, v_linked FROM f360.shopify_variants s
    LEFT JOIN f360.woo_variant_links l ON l.target_id = t.id AND l.woo_variation_id = s.link_id WHERE s.target_id = t.id;
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'handle'), '[]') INTO v_pending FROM (
    SELECT jsonb_build_object('handle', s.handle, 'color', s.color, 'tallas', count(*)) x FROM f360.shopify_variants s
     WHERE s.target_id = t.id AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links l WHERE l.target_id = t.id AND l.woo_variation_id = s.link_id)
     GROUP BY s.handle, s.color) q;
  RETURN jsonb_build_object('nuevas', v_new, 'variantes', v_total, 'ligadas', v_linked, 'sin_ligar', v_total - v_linked, 'pendientes', v_pending);
END $$;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261109000200', 'f360_shopify_link_by_name', '{}');

CREATE TEMP TABLE shopify_link_result ON COMMIT DROP AS SELECT f360.shopify_link_variants('shopify_mx', 'woo_production') AS r;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM links_before b LEFT JOIN f360.woo_variant_links l ON l.woo_variation_id = b.woo_variation_id AND l.variant_id = b.variant_id
              WHERE l.variant_id IS NULL) THEN RAISE EXCEPTION 'POST: una liga existente cambió'; END IF;
  IF EXISTS (SELECT l.variant_id FROM f360.woo_variant_links l JOIN f360.sales_targets t ON t.id = l.target_id WHERE t.key = 'shopify_mx' GROUP BY l.variant_id HAVING count(*) > 1) THEN RAISE EXCEPTION 'POST: par ligado dos veces'; END IF;
  IF EXISTS (SELECT 1 FROM f360.woo_variant_links l JOIN f360.sales_targets t ON t.id = l.target_id JOIN f360.shopify_variants s ON s.target_id = t.id AND s.link_id = l.woo_variation_id
              JOIN f360.product_variants v ON v.id = l.variant_id JOIN f360.product_colors c ON c.id = v.color_id
             WHERE t.key = 'shopify_mx' AND (f360.shopify_norm(c.name) <> f360.shopify_norm(s.color) OR v.size_label <> s.size)) THEN RAISE EXCEPTION 'POST: liga con otro color o talla'; END IF;
  IF ((SELECT r FROM shopify_link_result)->>'ligadas')::int < 1270 THEN RAISE EXCEPTION 'POST: siguen faltando ligas'; END IF;
END $$;
SELECT r - 'pendientes' AS liga, r->'pendientes' AS pendientes FROM shopify_link_result;
COMMIT;
