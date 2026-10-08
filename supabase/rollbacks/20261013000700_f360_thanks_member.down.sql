-- Rollback of 20261013000700_f360_thanks_member.sql (deploy the previous f360-whatsapp first: it calls the 2-arg claim).
DROP TRIGGER IF EXISTS transactions_thanks_member ON public.transactions;
DROP FUNCTION IF EXISTS f360.enqueue_thanks_on_credit();
DROP FUNCTION IF EXISTS public.f360_whatsapp_claim(int, text[]);
CREATE FUNCTION public.f360_whatsapp_claim(p_limit int DEFAULT 20) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$ SELECT '[]'::jsonb $$;   -- re-run 20261013000600's version to restore
UPDATE f360.whatsapp_outbox SET result = 'cancelled' WHERE kind = 'thanks_member' AND sent_at IS NULL;
