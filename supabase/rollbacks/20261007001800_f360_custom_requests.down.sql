-- Rollback of 20261007001800_f360_custom_requests.sql (drops the requests: export them first if needed).
DROP FUNCTION IF EXISTS public.f360_custom_request_set(uuid, text);
DROP FUNCTION IF EXISTS public.f360_custom_requests_list(int);
DROP FUNCTION IF EXISTS public.f360_custom_request_create(jsonb);
DROP TABLE IF EXISTS f360.custom_requests;
