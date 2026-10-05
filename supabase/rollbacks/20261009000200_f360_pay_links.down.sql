-- Rollback of 20261009000200 (pay links). Cases of kind 'link_pago' are removed first so the old checks can come back.
DROP FUNCTION IF EXISTS public.f360_pay_link_done(uuid, bigint, text, text, text);
DROP FUNCTION IF EXISTS public.f360_pay_link_open(jsonb);
DELETE FROM f360.customer_cases WHERE kind = 'link_pago' OR source = 'web_checkout';
ALTER TABLE f360.customer_cases DROP CONSTRAINT customer_cases_kind_check,
  ADD CONSTRAINT customer_cases_kind_check CHECK (kind IN ('escalacion', 'a_la_medida'));
ALTER TABLE f360.customer_cases DROP CONSTRAINT customer_cases_source_check,
  ADD CONSTRAINT customer_cases_source_check CHECK (source IN ('hilo_web', 'hilo_app', 'hilo_whatsapp', 'hilo_voice', 'web_pdp'));
