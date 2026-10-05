-- Rollback of 20261010000800: back to the promise without time window (restores the 3-argument function).
DROP FUNCTION f360.delivery_promise(uuid, uuid, text, timestamptz);
CREATE FUNCTION f360.delivery_promise(p_variant uuid, p_fulfillment uuid, p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ats int; mto boolean; c text; rule f360.delivery_promise_rules; last_pair boolean := false;
BEGIN
  IF p_variant IS NULL THEN RETURN jsonb_build_object('case', 'unknown', 'status', 'blocked'); END IF;
  ats := f360.online_ats(p_variant, p_fulfillment);
  SELECT p.make_to_order INTO mto FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.id = p_variant;
  c := CASE WHEN ats > 0 THEN 'in_stock' WHEN coalesce(mto, false) THEN 'made_to_order' ELSE 'unavailable' END;
  SELECT * INTO rule FROM f360.delivery_promise_rules WHERE market = f360.market_key(p_market) AND promise_case = c;
  IF c = 'in_stock' AND ats = 1 THEN last_pair := f360.online_scarcity_reliable(p_variant, p_fulfillment); END IF;
  RETURN jsonb_strip_nulls(jsonb_build_object('case', c, 'status', rule.status, 'headline', rule.headline, 'detail', rule.detail,
    'business_days', rule.business_days, 'last_pair', last_pair, 'can_notify', c = 'unavailable'));
END $$;
REVOKE ALL ON FUNCTION f360.delivery_promise(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
ALTER TABLE f360.delivery_promise_rules DROP CONSTRAINT promise_hours_complete, DROP COLUMN after_hours_headline, DROP COLUMN hours_end, DROP COLUMN hours_start;
