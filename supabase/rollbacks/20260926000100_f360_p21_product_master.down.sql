-- ROLLBACK for 20260926000100_f360_p21_product_master.sql
-- Drops P2.1 product-master additions (photos table, commercial fields, codes, categories, new RPCs) and
-- restores the V1 definitions of the redefined functions by re-running their V1 bodies.
-- ⚠ Photos metadata and commercial info are lost (Storage files remain). Valid pre-launch only.
-- Apply by hand, then: supabase migration repair --status reverted 20260926000100 --db-url "<target>"
BEGIN;
DROP FUNCTION IF EXISTS public.f360_add_color(uuid, text, text);
DROP FUNCTION IF EXISTS public.f360_update_product(uuid, jsonb);
DROP FUNCTION IF EXISTS public.f360_add_media(uuid, uuid, text[]);
DROP FUNCTION IF EXISTS public.f360_remove_media(uuid);
DROP FUNCTION IF EXISTS public.f360_set_primary_media(uuid);
DROP FUNCTION IF EXISTS public.f360_list_categories();
DROP TRIGGER IF EXISTS products_locked_codes ON f360.products;
DROP TRIGGER IF EXISTS product_colors_locked_codes ON f360.product_colors;
DROP TRIGGER IF EXISTS product_variants_locked_sku ON f360.product_variants;
DROP TABLE IF EXISTS f360.product_media;
ALTER TABLE f360.products DROP CONSTRAINT IF EXISTS products_sale_below_regular,
  DROP COLUMN IF EXISTS code, DROP COLUMN IF EXISTS codes_locked_at, DROP COLUMN IF EXISTS description,
  DROP COLUMN IF EXISTS short_description, DROP COLUMN IF EXISTS regular_price, DROP COLUMN IF EXISTS sale_price,
  DROP COLUMN IF EXISTS category_key;
ALTER TABLE f360.product_colors DROP COLUMN IF EXISTS code;
DROP TABLE IF EXISTS f360.categories;
-- The redefined functions (f360.event_json, f360_list_products, f360_get_product, f360_inventory_by_location,
-- f360_create_product) must then be restored from migration 20260925010000 (re-run their CREATE OR REPLACE blocks).
DROP FUNCTION IF EXISTS f360.product_readiness(uuid), f360.product_primary_image(uuid), f360.color_primary_image(uuid),
  f360.online_location(), f360.next_code(text, text[]), f360.refresh_skus(uuid), f360.variant_sku(text, text, text),
  f360.guard_locked_codes(), f360.code_from(text) CASCADE;
COMMIT;
