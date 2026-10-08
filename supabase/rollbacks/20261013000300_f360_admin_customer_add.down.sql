-- Rollback of 20261013000300_f360_admin_customer_add.sql. Only the admin's "Agregar clienta" goes away; the customers it
-- created stay (they are real customers, source 'admin', with their loyalty card).
DROP FUNCTION IF EXISTS public.f360_admin_customer_add(text, text, text, text, int, int, text, text);
