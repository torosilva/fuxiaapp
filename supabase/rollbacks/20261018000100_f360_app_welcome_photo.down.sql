-- Rollback of 20261018000100_f360_app_welcome_photo.sql. Drops the welcome-photo history (the uploaded files stay in
-- product-images/f360/app/). The app falls back to the store's featured / newest product on its own.
DROP FUNCTION IF EXISTS public.f360_set_app_welcome_photo(text, uuid);
DROP FUNCTION IF EXISTS public.f360_app_welcome_admin();
DROP FUNCTION IF EXISTS public.f360_app_welcome_photo();
DROP TABLE IF EXISTS f360.app_welcome_photos;
