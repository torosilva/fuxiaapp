-- Rollback of 20261105000200_f360_growth_competencia. Loses recorded competitor observations (export the table first).
BEGIN;
DROP FUNCTION public.f360_competitor_observe(jsonb);
DROP FUNCTION public.f360_growth_competencia();
DROP TABLE f360.competitor_observations, f360.competitors;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261105000200';
COMMIT;
