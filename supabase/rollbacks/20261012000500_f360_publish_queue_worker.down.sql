-- Rollback of 20261012000500_f360_publish_queue_worker.sql
BEGIN;
DROP FUNCTION IF EXISTS public.f360_pub_queue_status(text);
DROP FUNCTION IF EXISTS public.f360_pub_next_job(text);
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261012000500';
COMMIT;
