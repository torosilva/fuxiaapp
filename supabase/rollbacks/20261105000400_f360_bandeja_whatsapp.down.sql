-- Rollback of 20261105000400_f360_bandeja_whatsapp. Queued notices are deleted (they were never customer data).
BEGIN;
SELECT cron.unschedule('f360-bandeja-resumen');
DROP TRIGGER IF EXISTS customer_cases_whatsapp ON f360.customer_cases;
DROP FUNCTION IF EXISTS f360.case_whatsapp();
DROP FUNCTION IF EXISTS f360.bandeja_resumen();
DROP FUNCTION IF EXISTS f360.staff_whatsapp_enqueue(text, text, text, text, text);
DROP FUNCTION IF EXISTS f360.wa_line(text, int);
DELETE FROM f360.whatsapp_outbox WHERE kind = 'aviso_equipo';
ALTER TABLE f360.whatsapp_outbox DROP CONSTRAINT whatsapp_outbox_kind_check,
  ADD CONSTRAINT whatsapp_outbox_kind_check CHECK (kind IN ('thanks', 'thanks_member'));
DROP TABLE IF EXISTS f360.staff_whatsapp;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261105000400';
COMMIT;
