-- Rollback of 20261007002600.
DROP TRIGGER IF EXISTS custom_requests_case ON f360.custom_requests;
DROP FUNCTION IF EXISTS f360.case_from_custom_request();
DROP FUNCTION IF EXISTS public.f360_case_set(uuid, text);
DROP FUNCTION IF EXISTS public.f360_inbox_list(int);
DROP FUNCTION IF EXISTS public.f360_case_upsert(jsonb);
DROP FUNCTION IF EXISTS f360.case_email(f360.customer_cases, text);
DROP TABLE IF EXISTS f360.customer_cases;
DELETE FROM f360.notification_recipients WHERE kind = 'customer_case';
