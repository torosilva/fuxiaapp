-- Rollback of 20261007001000_f360_stores_rename_color.sql (renamed colours keep their new names).
DROP FUNCTION IF EXISTS public.f360_legacy_channels_available();
DROP FUNCTION IF EXISTS public.f360_rename_color(uuid, text);
