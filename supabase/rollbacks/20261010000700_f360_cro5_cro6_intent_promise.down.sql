-- Rollback of 20261010000700 (CRO-5/CRO-6). Waiting "Avísame" intents are LOST: export f360.stock_intents first.
DROP FUNCTION public.f360_stock_demand(text);
DROP FUNCTION public.f360_stock_intent_create(text, bigint, bigint, text, text, text, boolean, text, text, text);
DROP FUNCTION public.f360_storefront_promise(text, bigint, text);
DROP FUNCTION f360.storefront_target(text);
DROP TABLE f360.stock_intents;
DROP FUNCTION f360.trust_claims(uuid, text);
DROP FUNCTION f360.delivery_promise(uuid, uuid, text);
DROP FUNCTION f360.market_key(text);
DROP TABLE f360.delivery_promise_rules;
DELETE FROM f360.consent_notice_versions WHERE purpose_key = 'stock_notification'
  AND NOT EXISTS (SELECT 1 FROM f360.customer_consent_events e WHERE e.notice_version_id = consent_notice_versions.id);
DELETE FROM f360.consent_purposes WHERE key = 'stock_notification'
  AND NOT EXISTS (SELECT 1 FROM f360.customer_consent_events e WHERE e.purpose_key = 'stock_notification');
ALTER TABLE f360.consent_purposes DROP CONSTRAINT consent_purposes_kind_check;
ALTER TABLE f360.consent_purposes ADD CONSTRAINT consent_purposes_kind_check CHECK (kind IN ('privacy', 'marketing', 'operational'));
-- ('operational' stays allowed if consent events already reference stock_notification; otherwise harmless.)
