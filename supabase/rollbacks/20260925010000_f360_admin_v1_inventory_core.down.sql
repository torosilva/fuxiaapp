-- ROLLBACK for 20260925010000_f360_admin_v1_inventory_core.sql
-- ⚠ Drops the whole f360 schema INCLUDING its inventory ledger data. Valid only while f360 holds
--   no real business data (staging / pre-launch). Once real receipts exist, roll forward instead.
-- Apply by hand, then: supabase migration repair --status reverted 20260925010000 --db-url "<target>"
DROP POLICY IF EXISTS "f360 operators upload product images" ON storage.objects;
DROP FUNCTION IF EXISTS public.f360_can_upload();
DROP FUNCTION IF EXISTS public.f360_home();
DROP FUNCTION IF EXISTS public.f360_inventory_by_location(uuid);
DROP FUNCTION IF EXISTS public.f360_get_event(uuid);
DROP FUNCTION IF EXISTS public.f360_list_events(int, uuid, uuid);
DROP FUNCTION IF EXISTS public.f360_receive_inventory(uuid, uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.f360_create_product(text, text[], jsonb, text, text);
DROP FUNCTION IF EXISTS public.f360_get_product(uuid);
DROP FUNCTION IF EXISTS public.f360_list_products(text);
DROP FUNCTION IF EXISTS public.f360_list_locations();
DROP FUNCTION IF EXISTS public.f360_me();
DROP SCHEMA IF EXISTS f360 CASCADE;
