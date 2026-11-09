-- Fuxia 360 · PRODUCCIÓN · Tallas Kids = guía oficial 24–33 (Mario 2026-11-09, imagen "Fuxia Ballerinas Kids · Guía de tallas":
-- 24 16.0 · 25 16.5 · 26 17.2 · 27 17.9 · 28 18.6 · 29 19.2 · 30 19.9 · 31 20.6 · 32 21.3 · 33 21.9 cm).
-- Hoy: Mini cucarrones y Mini Twin Studs tienen 25–33 + 35–40 (tallas de adulta) y no tienen 24; Mini Paula solo tiene 35–40.
-- Lectura en prod (2026-11-09): ninguna talla de los tres modelos tiene movimiento, existencia, pedido, apartado ni conteo.
-- Hace: agrega las tallas que faltan (24 en los tres, 24–33 en Mini Paula) con una variante por color y SKU estándar;
--       borra las tallas 35–40 de los tres (variantes + sus ligas a Woo y Shopify), SOLO si siguen sin ninguna historia.
-- Woo: el publicador oculta (privado, nunca borra) las variaciones 35–40 y crea las nuevas al volver a publicar.
-- Shopify: las variantes se corrigen en el admin de Shopify; después se recarga el catálogo y se ligan (otro pase).
-- Reversión: tallas sin historia → volver a crearlas con este mismo patrón (no hay datos que se pierdan).
BEGIN;
CREATE TEMP TABLE kids ON COMMIT DROP AS
  SELECT id, name FROM f360.products WHERE name IN ('Mini cucarrones', 'Mini Paula', 'Mini Twin Studs') AND status = 'active';
CREATE TEMP TABLE adultas ON COMMIT DROP AS
  SELECT v.id FROM f360.product_variants v JOIN kids k ON k.id = v.product_id WHERE v.size_label IN ('35', '36', '37', '38', '39', '40');
DO $$ BEGIN
  IF (SELECT count(*) FROM kids) <> 3 THEN RAISE EXCEPTION 'PRE: no encontré los 3 modelos Kids'; END IF;
  IF (SELECT count(*) FROM adultas) <> 60 THEN RAISE EXCEPTION 'PRE: esperaba 60 variantes 35–40, hay %', (SELECT count(*) FROM adultas); END IF;
  IF EXISTS (SELECT 1 FROM f360.inventory_movements WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.inventory_balances WHERE variant_id IN (SELECT id FROM adultas) AND on_hand <> 0)
     OR EXISTS (SELECT 1 FROM f360.woo_order_lines WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM public.offline_sale_items WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.reservations WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.made_to_order WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.cutover_counts WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.opening_count_lines WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.transfer_lines WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.online_store_shipments WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.stock_intents WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.review_facts WHERE purchased_variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.retired_woo_links WHERE variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.legacy_woo_map WHERE confirmed_variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.legacy_inventory_map WHERE confirmed_variant_id IN (SELECT id FROM adultas) OR proposed_variant_id IN (SELECT id FROM adultas))
     OR EXISTS (SELECT 1 FROM f360.product_cost_versions WHERE variant_id IN (SELECT id FROM adultas))
  THEN RAISE EXCEPTION 'PRE: alguna talla 35–40 ya tiene historia; no se borra nada'; END IF;
END $$;

-- 1) Tallas Kids que faltan (24 en los tres; 24–33 en Mini Paula), ordenadas por número.
INSERT INTO f360.product_sizes (product_id, label, sort)
  SELECT k.id, t::text, t FROM kids k CROSS JOIN generate_series(24, 33) t
  ON CONFLICT (product_id, label) DO NOTHING;
UPDATE f360.product_sizes s SET sort = s.label::int FROM kids k WHERE s.product_id = k.id AND s.label ~ '^[0-9]+$';

-- 2) Una variante por color en cada talla nueva (mismas banderas que las existentes), con SKU estándar.
INSERT INTO f360.product_variants (product_id, color_id, size_label)
  SELECT k.id, c.id, t::text FROM kids k JOIN f360.product_colors c ON c.product_id = k.id CROSS JOIN generate_series(24, 33) t
  ON CONFLICT (color_id, size_label) DO NOTHING;
SELECT f360.refresh_skus(id) FROM kids;

-- 3) Fuera 35–40: ligas de tienda, saldos en cero, avisos de favoritos y colas de sincronización de esas variantes, luego variantes y tallas.
DELETE FROM f360.woo_variant_links WHERE variant_id IN (SELECT id FROM adultas);
DELETE FROM f360.inventory_balances WHERE variant_id IN (SELECT id FROM adultas);
UPDATE f360.favorite_events SET variant_id = NULL WHERE variant_id IN (SELECT id FROM adultas);
DELETE FROM f360.stock_sync_queue WHERE variant_id IN (SELECT id FROM adultas);
DELETE FROM f360.stock_sync_log WHERE variant_id IN (SELECT id FROM adultas);
DELETE FROM f360.sync_exceptions WHERE variant_id IN (SELECT id FROM adultas);
DELETE FROM f360.product_variants WHERE id IN (SELECT id FROM adultas);
DELETE FROM f360.product_sizes s USING kids k WHERE s.product_id = k.id AND s.label IN ('35', '36', '37', '38', '39', '40');
UPDATE f360.products SET updated_at = now() WHERE id IN (SELECT id FROM kids);

-- POST: los tres con 24–33 y nada más; una variante por color y talla.
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT k.name,
      (SELECT string_agg(s.label, ' ' ORDER BY s.sort) FROM f360.product_sizes s WHERE s.product_id = k.id) AS tallas,
      (SELECT count(*) FROM f360.product_variants v WHERE v.product_id = k.id) AS vars,
      (SELECT count(*) FROM f360.product_colors c WHERE c.product_id = k.id) AS colores,
      (SELECT count(*) FROM f360.product_variants v WHERE v.product_id = k.id AND v.sku IS NULL) AS sin_sku
    FROM kids k LOOP
    IF r.tallas <> '24 25 26 27 28 29 30 31 32 33' THEN RAISE EXCEPTION 'POST %: tallas %', r.name, r.tallas; END IF;
    IF r.vars <> r.colores * 10 OR r.sin_sku > 0 THEN RAISE EXCEPTION 'POST %: % variantes para % colores', r.name, r.vars, r.colores; END IF;
    RAISE NOTICE '% → tallas %, % variantes', r.name, r.tallas, r.vars;
  END LOOP;
END $$;
COMMIT;
