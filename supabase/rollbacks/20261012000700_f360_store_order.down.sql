-- Rollback of 20261012000700_f360_store_order. The store keeps the menu_order last written (harmless; the shop falls back to
-- the mu-plugin's default order or WooCommerce's). The audit rows go with the table — export them first if they matter.
DROP FUNCTION IF EXISTS public.f360_pub_order_finish(text, uuid, boolean, integer, text);
DROP FUNCTION IF EXISTS public.f360_pub_order_begin(text, uuid);
DROP FUNCTION IF EXISTS public.f360_set_store_featured(uuid[]);
DROP FUNCTION IF EXISTS public.f360_store_order(text);
DROP FUNCTION IF EXISTS f360.store_order_plan(uuid);
DROP FUNCTION IF EXISTS f360.product_units_sold(uuid);
DROP TABLE IF EXISTS f360.store_order_runs;
ALTER TABLE f360.products DROP COLUMN IF EXISTS store_rank;
