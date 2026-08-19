-- Migración 18 ago 2026
--
-- 1) purchase_items.wc_product_id
--    Puntero estable al producto de WooCommerce. Sin esto, la app resolvía la
--    foto del último pedido buscando por NOMBRE con la búsqueda difusa de
--    WooCommerce, que devuelve el primer resultado parecido — por eso
--    aparecían fotos de productos que no correspondían a la compra.
--
-- 2) customers.birthday
--    Se aplicó a mano en producción esta noche para desbloquear el registro:
--    la app enviaba `birthday` y la columna no existía, así que PostgREST
--    rechazaba la creación de CUALQUIER cuenta nueva. Queda versionada.

ALTER TABLE public.purchase_items ADD COLUMN IF NOT EXISTS wc_product_id INTEGER;
ALTER TABLE public.customers      ADD COLUMN IF NOT EXISTS birthday DATE;

NOTIFY pgrst, 'reload schema';
