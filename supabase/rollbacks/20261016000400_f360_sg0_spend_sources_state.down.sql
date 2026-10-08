-- Rollback of 20261016000400_f360_sg0_spend_sources_state.sql: back to the 20261014000600 seed state (both UNKNOWN, NOT_CONFIGURED).
UPDATE f360.measurement_sources SET spend_expected = NULL, config_status = 'NOT_CONFIGURED', notes = NULL,
       updated_by_name = 'rollback 20261016000400', updated_at = now()
 WHERE key IN ('meta_ads', 'google_ads');
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261016000400';
