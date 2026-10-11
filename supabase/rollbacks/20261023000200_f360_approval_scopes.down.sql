-- Rollback of 20261023000200. Only when 20261024000100 (daily FX) and 20261025000100 (store discounts) are NOT applied:
-- both depend on this table. Teardown — run only with Mario's OK.
DROP FUNCTION IF EXISTS f360.can_approve(text, uuid);
DROP TABLE IF EXISTS f360.approval_scopes;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261023000200';
