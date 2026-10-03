-- Rollback of 20261007001400_f360_legacy_content_push.sql. Woo keeps whatever was already written (staging only).
DROP FUNCTION IF EXISTS public.f360_legacy_content_result(text, int, uuid, text, boolean, text, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.f360_legacy_content_snapshot(text, int);
DROP FUNCTION IF EXISTS public.f360_legacy_content_list(text, uuid[]);
DROP FUNCTION IF EXISTS f360.content_target(text);
DROP TABLE IF EXISTS f360.legacy_content_pushes;
