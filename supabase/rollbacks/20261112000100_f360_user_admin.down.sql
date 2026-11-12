-- Rollback of 20261112000100_f360_user_admin.sql. Drops only what that migration created.
-- Roles (f360.user_roles), store assignments and the f360.access_changes history are untouched.
-- Module access granted through the screen is lost; people keep their role.
BEGIN;
DROP FUNCTION IF EXISTS public.f360_my_access();
DROP FUNCTION IF EXISTS public.f360_admin_remove_user(uuid, text);
DROP FUNCTION IF EXISTS public.f360_admin_set_module(uuid, text, boolean, text);
DROP FUNCTION IF EXISTS public.f360_admin_set_profile(uuid, text, text, text);
DROP FUNCTION IF EXISTS public.f360_admin_users();
DROP FUNCTION IF EXISTS f360.require_module(text);
DROP FUNCTION IF EXISTS f360.user_sensitive(uuid);
DROP FUNCTION IF EXISTS f360.require_reason(text);
DROP FUNCTION IF EXISTS f360.user_modules(uuid);
DROP FUNCTION IF EXISTS f360.user_profile(text, text[]);
DROP TABLE IF EXISTS f360.user_module_access;
COMMIT;
