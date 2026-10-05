-- Fuxia 360 · CRO-6 — the time window of "Entrega Inmediata en Zona Metropolitana" moves INTO the single rule. STAGING.
-- The installed PDP snippet (f360-entrega-inmediata.html, decision Mario 2026-10-03) already shows, for MX in-stock sizes:
-- 8:00–18:59 CDMX → "Entrega Inmediata en Zona Metropolitana"; otherwise → "Entrega mañana a partir de las 8 a. m. en Zona
-- Metropolitana". CRO-5/6 replaces that snippet's promise with Fuxia 360, so the window becomes rule DATA (not a silent change).
-- Mario 2026-10-05 (CRO-5/6 decisions): "Avísame" only for really non-purchasable sizes (never on made-to-order);
-- CO and outside-ZM keep conservative copy (no invented days); stock consent text = LEGAL_REVIEW_REQUIRED (not blocking).
-- Rollback: supabase/rollbacks/20261010000800_f360_cro6_promise_hours.down.sql
ALTER TABLE f360.delivery_promise_rules
  ADD COLUMN hours_start smallint CHECK (hours_start BETWEEN 0 AND 23),
  ADD COLUMN hours_end smallint CHECK (hours_end BETWEEN 1 AND 24),
  ADD COLUMN after_hours_headline text,
  ADD CONSTRAINT promise_hours_complete CHECK ((hours_start IS NULL) = (hours_end IS NULL) AND (hours_start IS NULL) = (after_hours_headline IS NULL));
UPDATE f360.delivery_promise_rules SET hours_start = 8, hours_end = 19,
    after_hours_headline = 'Entrega mañana a partir de las 8 a. m. en Zona Metropolitana', decided_by = 'Mario (2026-10-03 · PDP)'
  WHERE market = 'MX' AND promise_case = 'in_stock';
COMMENT ON COLUMN f360.consent_notice_versions.text_ref IS 'Exact text the customer accepted. stock_notification 2026-10-05-v1: LEGAL_REVIEW_REQUIRED (Mario 2026-10-05, not blocking staging).';

DROP FUNCTION f360.delivery_promise(uuid, uuid, text);
CREATE FUNCTION f360.delivery_promise(p_variant uuid, p_fulfillment uuid, p_market text, p_at timestamptz DEFAULT now()) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ats int; mto boolean; c text; rule f360.delivery_promise_rules; last_pair boolean := false; h int; head text;
BEGIN
  IF p_variant IS NULL THEN RETURN jsonb_build_object('case', 'unknown', 'status', 'blocked'); END IF;
  ats := f360.online_ats(p_variant, p_fulfillment);
  SELECT p.make_to_order INTO mto FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.id = p_variant;
  c := CASE WHEN ats > 0 THEN 'in_stock' WHEN coalesce(mto, false) THEN 'made_to_order' ELSE 'unavailable' END;
  SELECT * INTO rule FROM f360.delivery_promise_rules WHERE market = f360.market_key(p_market) AND promise_case = c;
  head := rule.headline;
  IF rule.hours_start IS NOT NULL THEN
    h := extract(hour FROM p_at AT TIME ZONE 'America/Mexico_City')::int;
    IF NOT (h >= rule.hours_start AND h < rule.hours_end) THEN head := rule.after_hours_headline; END IF;
  END IF;
  IF c = 'in_stock' AND ats = 1 THEN last_pair := f360.online_scarcity_reliable(p_variant, p_fulfillment); END IF;  -- certified only
  RETURN jsonb_strip_nulls(jsonb_build_object('case', c, 'status', rule.status, 'headline', head, 'detail', rule.detail,
    'business_days', rule.business_days, 'last_pair', last_pair, 'can_notify', c = 'unavailable'));
END $$;
REVOKE ALL ON FUNCTION f360.delivery_promise(uuid, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated;
