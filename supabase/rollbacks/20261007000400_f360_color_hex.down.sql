-- Rollback of 20261007000400_f360_color_hex.sql (hex values already set stay; they are display only).
DROP FUNCTION IF EXISTS public.f360_set_color_hex(uuid, text);
