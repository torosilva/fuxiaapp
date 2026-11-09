-- Fuxia 360 · PRODUCCIÓN · Precio en pesos colombianos para los 9 modelos que no se podían comprar en Woo Colombia
-- (Mario 2026-11-09: "corrige urgente lo de los precios de Fuxia en Colombia"; sin precio COP la tienda no deja agregarlos al carrito).
-- Decisión de Mario (2026-11-09):
--   · adulta: "el más usado" entre los modelos con el mismo precio en MXN → $2,800 MXN = COP 440,000 (14 modelos así),
--     $3,000 MXN = COP 450,000 (22 modelos así);
--   · Mini Twin Studs ($1,900 MXN) = COP 280,000 (igual que Mini cucarrones).
-- Se usa la misma función de la pantalla de precios (f360_set_product_price) como Mario, así queda en el historial de precios.
-- Después: botón "Subir a la tienda" de cada modelo en Fuxia 360 para que Woo Colombia reciba el precio.
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"d11a8d33-cae6-46a5-9d0f-bd2516e8712b","role":"authenticated"}', true);
CREATE TEMP TABLE nuevos ON COMMIT DROP AS SELECT * FROM (VALUES
  ('Aladin', 2800::numeric, 440000::numeric), ('Breeze', 2800, 440000), ('Leo Penny', 2800, 440000),
  ('Nina Classic Strap', 2800, 440000), ('Suecos leopardo', 2800, 440000),
  ('Cage Wedge', 3000, 450000), ('Duo Heel', 3000, 450000), ('Macrame', 3000, 450000),
  ('Mini Twin Studs', 1900, 280000)) v(name, mxn, cop);
DO $$ DECLARE r record; BEGIN
  FOR r IN SELECT n.*, p.id, p.regular_price FROM nuevos n LEFT JOIN f360.products p ON p.name = n.name AND p.status = 'active' LOOP
    IF r.id IS NULL THEN RAISE EXCEPTION 'PRE: no encontré %', r.name; END IF;
    IF r.regular_price <> r.mxn THEN RAISE EXCEPTION 'PRE: % ya no cuesta % MXN (cuesta %)', r.name, r.mxn, r.regular_price; END IF;
    IF EXISTS (SELECT 1 FROM f360.product_prices x WHERE x.product_id = r.id AND x.currency_code = 'COP') THEN RAISE EXCEPTION 'PRE: % ya tiene precio COP', r.name; END IF;
    PERFORM public.f360_set_product_price(r.id, 'COP', r.cop);
  END LOOP;
  IF (SELECT count(*) FROM nuevos n JOIN f360.products p ON p.name = n.name AND p.status = 'active'
        JOIN f360.product_prices x ON x.product_id = p.id AND x.currency_code = 'COP' AND x.amount = n.cop) <> 9 THEN
    RAISE EXCEPTION 'POST: no quedaron los 9 precios';
  END IF;
END $$;
COMMIT;
