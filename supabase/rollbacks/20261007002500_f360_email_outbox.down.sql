-- Rollback of 20261007002500.
SELECT cron.unschedule('f360-email-retry');
DROP TRIGGER IF EXISTS custom_requests_notify ON f360.custom_requests;
DROP FUNCTION IF EXISTS f360.notify_custom_request();
DROP FUNCTION IF EXISTS public.f360_email_result(jsonb);
DROP FUNCTION IF EXISTS public.f360_email_claim(int);
DROP FUNCTION IF EXISTS f360.email_tick();
DROP TABLE IF EXISTS f360.email_outbox;
DROP TABLE IF EXISTS f360.notification_recipients;
