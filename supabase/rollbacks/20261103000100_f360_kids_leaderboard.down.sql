-- Rollback of 20261103000100 (Fuxia Kids weekly board). Loses only the game's scores; nothing else depends on them.
BEGIN;
DROP FUNCTION IF EXISTS public.f360_kids_score_submit(jsonb);
DROP FUNCTION IF EXISTS public.f360_kids_top(text);
DROP FUNCTION IF EXISTS f360.kids_week_start(timestamptz);
DROP FUNCTION IF EXISTS f360.kids_dancer_names();
DROP TABLE IF EXISTS f360.kids_scores;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261103000100';
COMMIT;
