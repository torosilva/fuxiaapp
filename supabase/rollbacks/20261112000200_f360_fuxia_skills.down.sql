-- Rollback of 20261112000200_f360_fuxia_skills.sql. Drops only what that migration created (the library and its history).
BEGIN;
DROP FUNCTION IF EXISTS public.f360_skill_set_status(text, text, text);
DROP FUNCTION IF EXISTS public.f360_skill_save(text, text, text, text);
DROP FUNCTION IF EXISTS public.f360_skill(text, int);
DROP FUNCTION IF EXISTS public.f360_skills();
DROP TABLE IF EXISTS f360.skill_status_changes;
DROP TABLE IF EXISTS f360.skill_versions;
DROP TABLE IF EXISTS f360.skills;
COMMIT;
