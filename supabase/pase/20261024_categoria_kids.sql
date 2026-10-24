-- Fuxia 360 · PRODUCCIÓN · categoría "Kids" (Mario 2026-10-24: "en la página pusieron Fuxia Kids pero en Fuxia 360 no está").
-- La agencia creó en fuxiaballerinas.com la categoría Woo "Kids" (term 96, slug kids, 0 productos). Esto la da de alta en
-- Fuxia 360 (f360.categories, sort 5) y la liga al term 96 de woo_production, igual que las otras 4 (pase C1).
-- Solo datos: no toca productos, tallas (son por producto), precios ni WooCommerce.
-- Reversión: DELETE FROM f360.woo_category_links WHERE category_key = 'kids'; DELETE FROM f360.categories WHERE key = 'kids';
--   (solo mientras ningún producto use category_key = 'kids').
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.categories WHERE key = 'kids') OR EXISTS (SELECT 1 FROM f360.woo_category_links WHERE category_key = 'kids') THEN
    RAISE EXCEPTION 'KIDS PRE: ya existe'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production') THEN
    RAISE EXCEPTION 'KIDS PRE: no hay canal woo_production'; END IF;
  IF EXISTS (SELECT 1 FROM f360.woo_category_links WHERE woo_term_id = 96) THEN
    RAISE EXCEPTION 'KIDS PRE: el term 96 ya está ligado'; END IF;
END $$;

INSERT INTO f360.categories (key, name, sort) VALUES ('kids', 'Kids', 5);

INSERT INTO f360.woo_category_links (target_id, category_key, woo_term_id, woo_slug, verified_at)
SELECT id, 'kids', 96, 'kids', now() FROM f360.sales_targets WHERE key = 'woo_production';

DO $$ BEGIN
  IF (SELECT count(*) FROM f360.categories) <> 5 OR (SELECT count(*) FROM f360.woo_category_links WHERE category_key = 'kids') <> 1 THEN
    RAISE EXCEPTION 'KIDS POST: no cuadra'; END IF;
END $$;
COMMIT;
