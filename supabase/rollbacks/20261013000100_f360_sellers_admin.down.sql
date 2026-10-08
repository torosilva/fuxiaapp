-- Rollback of 20261013000100_f360_sellers_admin.sql. Sellers already activated keep their role, store and PIN
-- (f360.user_roles / location_assignments / seller_credentials are the existing tables); only the Vendedoras screen,
-- its pending invitations and the first-login activation go away. The customers rows it created stay (role 'staff').
DROP TRIGGER IF EXISTS customers_activate_seller ON public.customers;
DROP FUNCTION IF EXISTS public.f360_admin_seller_deactivate(uuid);
DROP FUNCTION IF EXISTS public.f360_admin_seller_reset_pin(uuid, text);
DROP FUNCTION IF EXISTS public.f360_admin_seller_set_store(uuid, uuid);
DROP FUNCTION IF EXISTS public.f360_admin_seller_add(text, text, uuid, text);
DROP FUNCTION IF EXISTS public.f360_admin_sellers();
DROP FUNCTION IF EXISTS f360.customers_activate_seller();
DROP FUNCTION IF EXISTS f360.activate_seller(uuid, uuid, text, uuid);
DROP FUNCTION IF EXISTS f360.assert_seller_store(uuid);
DROP FUNCTION IF EXISTS f360.seller_pin_hash(text);
DROP FUNCTION IF EXISTS f360.seller_json(f360.sellers);
DROP TABLE IF EXISTS f360.sellers;
