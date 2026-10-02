-- Rollback of 20261007000500_f360_product_archive.sql. Products archived meanwhile stay archived (status column
-- predates this migration); reactivate them first if needed: UPDATE f360.products SET status = 'active' WHERE …
DROP FUNCTION IF EXISTS public.f360_set_product_archived(uuid, boolean, text);
DROP FUNCTION IF EXISTS public.f360_product_archive_state(uuid);
DROP FUNCTION IF EXISTS f360.archive_blockers(uuid);
DROP TABLE IF EXISTS f360.product_status_changes;
DROP FUNCTION IF EXISTS f360.product_status_log_append_only();
