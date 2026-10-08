-- Rollback of 20261013000600_f360_thanks_whatsapp.sql. Deploy the previous f360-woo-orders FIRST (it calls f360_web_order_loyalty).
-- Customers already registered from online orders, their holds and transactions STAY (real loyalty data); the outbox table is
-- kept (message history) — drop it only with Mario's explicit OK.
SELECT cron.unschedule('f360-whatsapp');
DROP TRIGGER IF EXISTS loyalty_holds_thanks ON f360.loyalty_holds;
DROP TRIGGER IF EXISTS transactions_cancel_web_hold ON public.transactions;
DROP TRIGGER IF EXISTS transactions_web_order_id ON public.transactions;
DROP FUNCTION IF EXISTS public.f360_web_order_loyalty(text, jsonb);
DROP FUNCTION IF EXISTS f360.transactions_cancel_web_hold();
DROP FUNCTION IF EXISTS f360.transactions_web_order_id();
DROP FUNCTION IF EXISTS public.f360_whatsapp_claim(int);
DROP FUNCTION IF EXISTS public.f360_whatsapp_result(uuid, boolean, text, text);
DROP FUNCTION IF EXISTS f360.enqueue_thanks_on_hold();
DROP FUNCTION IF EXISTS f360.whatsapp_tick();
