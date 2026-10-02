-- Rollback of 20261007000100_f360_d2_legacy_homologation.sql. Run AFTER the 20261007000200 rollback.
-- Drops the homologation rows and their history. F360 models/colours/variants created by confirmations are NOT deleted
-- (they are ordinary catalog rows; remove them separately only if they hold no inventory and no links).
DROP FUNCTION IF EXISTS public.f360_legacy_reopen(text, integer[], text);
DROP FUNCTION IF EXISTS public.f360_legacy_mark(text, integer[], text, text);
DROP FUNCTION IF EXISTS public.f360_legacy_confirm(text, integer[], uuid, text, text, text, text);
DROP FUNCTION IF EXISTS public.f360_legacy_homologation(text);
DROP FUNCTION IF EXISTS public.f360_legacy_propose(text, jsonb);
DROP FUNCTION IF EXISTS public.f360_legacy_load_snapshot(text, jsonb);
DROP FUNCTION IF EXISTS f360.legacy_summary(uuid);
DROP FUNCTION IF EXISTS f360.legacy_refresh_status(uuid);
DROP TABLE IF EXISTS f360.legacy_woo_map_log;
DROP TABLE IF EXISTS f360.legacy_woo_map;          -- its triggers go with it
DROP FUNCTION IF EXISTS f360.legacy_woo_map_guard();
DROP FUNCTION IF EXISTS f360.legacy_log_append_only();
