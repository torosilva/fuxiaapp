-- Rollback of 20261104000200_f360_growth_experiments: drops the experiments register (and every experiment and its history).
-- Teardown once applied: run only with Mario's OK — export f360.growth_experiments / growth_experiment_changes first if they hold real data.
BEGIN;
DROP FUNCTION public.f360_experiments_list();
DROP FUNCTION public.f360_experiment_transition(uuid, text, text, text, text);
DROP FUNCTION public.f360_experiment_save(uuid, jsonb);
DROP FUNCTION f360.growth_experiment_measure(f360.growth_experiments);
DROP FUNCTION f360.growth_threshold_error(jsonb);
DROP TABLE f360.growth_experiment_changes;
DROP TABLE f360.growth_experiments;
DROP FUNCTION f360.growth_experiment_changes_append_only();
DROP SEQUENCE f360.growth_experiment_seq;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261104000200';
COMMIT;
