-- Rollback of 20261030000200_f360_academy_a1 (and of 20261030000300, whose rows live in this schema).
-- Run ONLY with Mario's explicit OK: after apply it is a TEARDOWN (drops content, progress and practice history).
-- The shared approval registry keeps its academy requests/events (append-only history); revert 20261030000100 separately.
BEGIN;
DROP FUNCTION public.f360_academy_team();
DROP FUNCTION public.f360_academy_decide(uuid, boolean, text);
DROP FUNCTION public.f360_academy_submit(uuid, text);
DROP FUNCTION public.f360_academy_new_draft(uuid);
DROP FUNCTION public.f360_academy_comment(uuid, text, text, int, text);
DROP FUNCTION public.f360_academy_item_save(uuid, jsonb);
DROP FUNCTION public.f360_academy_lesson_save(uuid, text, int, jsonb, text[]);
DROP FUNCTION public.f360_academy_admin_version(uuid);
DROP FUNCTION public.f360_academy_admin_overview();
DROP FUNCTION public.f360_academy_fichas();
DROP FUNCTION public.f360_academy_answer(uuid, jsonb);
DROP FUNCTION public.f360_academy_progress_save(uuid, int, boolean);
DROP FUNCTION public.f360_academy_lesson(uuid);
DROP FUNCTION public.f360_academy_home();
DROP FUNCTION public.f360_academy_me();
DROP SCHEMA f360_academy CASCADE;
COMMIT;
