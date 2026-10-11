-- Rollback of 20261024000400_f360_ai_analyst (I3). Run inside one transaction (no BEGIN/COMMIT here). The audit is history:
-- refuses if questions were logged unless f360.ai_drop_audit = 'yes' (export f360.ai_queries first).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.ai_queries) AND coalesce(current_setting('f360.ai_drop_audit', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'ABORT: hay preguntas auditadas. Expórtalas y corre con SET f360.ai_drop_audit = ''yes''.';
  END IF;
END $$;
DROP FUNCTION public.f360_ai_settings_set(jsonb, text);
DROP FUNCTION public.f360_ai_usage();
DROP FUNCTION public.f360_ai_history();
DROP FUNCTION public.f360_ai_log(jsonb);
DROP FUNCTION public.f360_ai_quota(uuid);
DROP FUNCTION f360.ai_mask(text);
DROP TABLE f360.ai_queries;
DROP TABLE f360.ai_settings_changes;
DROP TABLE f360.ai_settings;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000400';
