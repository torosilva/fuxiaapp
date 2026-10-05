-- Rollback of 20261010000100_f360_crm_c1_customer_profile.sql (CRM V1 · C1). STAGING.
-- Removes everything C1 added. public.customers / public.loyalty_cards keep their pre-C1 shape; cards issued with an
-- opaque FX1- token keep it (a valid unique qr_code). Held points (f360.loyalty_holds 'held') are LOST on rollback:
-- check `SELECT count(*) FROM f360.loyalty_holds WHERE status = 'held'` first.
DROP FUNCTION public.f360_admin_rotate_card_token(uuid, text);
DROP FUNCTION public.f360_admin_customer(uuid);
DROP FUNCTION public.f360_admin_customers(text, int, int);
DROP FUNCTION public.f360_shift_customer_register(text, text, text, text, text, int, int, text, text);
DROP FUNCTION public.f360_shift_customer_card(text, uuid);
DROP FUNCTION public.f360_shift_customer_by_card(text, text);
DROP FUNCTION public.f360_shift_customer_find(text, text, text);
DROP FUNCTION f360.customer_full(uuid);
DROP FUNCTION f360.crm_refusal(text);
DROP FUNCTION f360.crm_rate_limited(f360.seller_sessions);
DROP FUNCTION f360.crm_log(f360.seller_sessions, text, uuid, text);
DROP FUNCTION f360.customer_masked_card(uuid);
DROP FUNCTION f360.customer_purchases(uuid, int);
DROP FUNCTION f360.crm_params();
DROP TABLE f360.customer_access_log;

DROP TRIGGER customers_on_verified ON public.customers;
DROP FUNCTION f360.customers_on_verified();
DROP FUNCTION f360.release_loyalty_holds(uuid);
DROP FUNCTION f360.loyalty_credit_or_hold(uuid, jsonb, numeric, text, text, text, text, jsonb);
DROP TABLE f360.loyalty_holds;

DROP VIEW f360.cards_with_legacy_token;
DROP FUNCTION f360.rotate_card_token(uuid, text, uuid);
DROP TABLE f360.card_token_events;
DROP TRIGGER loyalty_cards_server_token ON public.loyalty_cards;
DROP FUNCTION f360.loyalty_cards_server_token();
DROP FUNCTION f360.new_card_token();

DROP FUNCTION f360.record_consent(uuid, text, text, uuid, text, jsonb, jsonb);
DROP VIEW f360.customer_consent_state;
DROP TABLE f360.customer_consent_events;
DROP TABLE f360.consent_notice_versions;
DROP TABLE f360.consent_purposes;

DROP FUNCTION f360.customer_identity_verified(uuid);
DROP TABLE f360.customer_verifications;
DROP FUNCTION f360.require_pii_viewer();
DROP TABLE f360.customer_pii_viewers;

DROP TRIGGER customers_birthday_sync ON public.customers;
DROP FUNCTION f360.customers_birthday_sync();
ALTER TABLE public.customers
  DROP CONSTRAINT customers_source_check,
  DROP CONSTRAINT customers_postal_code_check,
  DROP CONSTRAINT customers_birthday_dm_check,
  DROP COLUMN registered_location,
  DROP COLUMN registered_by,
  DROP COLUMN source,
  DROP COLUMN postal_code,
  DROP COLUMN birthday_month,
  DROP COLUMN birthday_day;
DROP INDEX public.customers_phone_normalized_key;
DROP FUNCTION f360.normalize_phone(text, text);
