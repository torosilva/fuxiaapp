-- Rollback of 20261013000200_f360_store_sale_customer.sql: the linked-customer sale goes away (sales already recorded
-- and points held/credited stay as they are) and the counter sign-up requires the e-mail again (as in 20261010000100).
DROP FUNCTION IF EXISTS public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid);
CREATE OR REPLACE FUNCTION public.f360_shift_customer_register(p_token text, p_phone text, p_name text, p_email text,
  p_postal_code text DEFAULT NULL, p_birthday_day int DEFAULT NULL, p_birthday_month int DEFAULT NULL, p_shoe_size text DEFAULT NULL,
  p_country text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); ph text; nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  em text := lower(btrim(coalesce(p_email, ''))); cp text := nullif(upper(btrim(coalesce(p_postal_code, ''))), ''); sz text := nullif(btrim(coalesce(p_shoe_size, '')), '');
  cid uuid; bad text;
BEGIN
  IF f360.crm_rate_limited(s) THEN PERFORM f360.crm_log(s, 'register', NULL, 'rate_limited'); RETURN f360.crm_refusal('rate_limited'); END IF;
  ph := f360.normalize_phone(p_phone, coalesce(p_country, 'MX'));
  bad := CASE WHEN ph IS NULL THEN 'invalid_phone'
              WHEN length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN 'invalid_name'
              WHEN em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(em) > 254 THEN 'invalid_email'
              WHEN cp IS NOT NULL AND cp !~ '^[0-9A-Z -]{3,10}$' THEN 'invalid_postal_code'
              WHEN (p_birthday_day IS NULL) <> (p_birthday_month IS NULL)
                OR (p_birthday_month IS NOT NULL AND (p_birthday_month NOT BETWEEN 1 AND 12 OR p_birthday_day NOT BETWEEN 1 AND
                    CASE WHEN p_birthday_month = 2 THEN 29 WHEN p_birthday_month IN (4, 6, 9, 11) THEN 30 ELSE 31 END)) THEN 'invalid_birthday'
              WHEN sz IS NOT NULL AND (length(sz) > 6 OR sz !~ '^[0-9]{2}(\.5)?$') THEN 'invalid_size' END;
  IF bad IS NOT NULL THEN PERFORM f360.crm_log(s, 'register', NULL, 'invalid'); RETURN f360.crm_refusal(bad); END IF;
  SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
  IF cid IS NOT NULL THEN
    PERFORM f360.crm_log(s, 'register', cid, 'existing');
    RETURN jsonb_build_object('ok', true, 'created', false, 'customer', f360.customer_masked_card(cid));
  END IF;
  BEGIN
    INSERT INTO public.customers (phone, name, email, country, postal_code, birthday_day, birthday_month, shoe_size, source,
                                  registered_by, registered_location, role)
      VALUES (ph, nm, em, CASE WHEN ph LIKE '+57%' THEN 'CO' ELSE 'MX' END, cp, p_birthday_day, p_birthday_month, sz, 'store',
              s.auth_user_id, s.location_id, 'customer')
      RETURNING id INTO cid;
  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
    PERFORM f360.crm_log(s, 'register', cid, 'existing');
    RETURN jsonb_build_object('ok', true, 'created', false, 'customer', f360.customer_masked_card(cid));
  END;
  INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cid, '', 0, 0, 'bronze');
  PERFORM f360.record_consent(cid, 'privacy_notice', 'requested',
    (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'privacy_notice' AND status = 'active'), 'store_signup',
    jsonb_build_object('seller', s.auth_user_id, 'location', s.location_id, 'session', s.id));
  PERFORM f360.crm_log(s, 'register', cid, 'created');
  RETURN jsonb_build_object('ok', true, 'created', true, 'customer', f360.customer_masked_card(cid));
END $$;

-- the shop catalog for the seller, as in 20261007001300
CREATE OR REPLACE FUNCTION public.f360_shift_catalog(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RETURN jsonb_build_object('location', l.name, 'ledger', 'f360', 'in_cutover', false, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', v.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
        'price', coalesce(p.sale_price, p.regular_price), 'available', b.on_hand, 'reserved', f360.reserved_qty(v.id, l.id)) ORDER BY p.name, c.sort, v.size_label), '[]'::jsonb)
      FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id WHERE b.location_id = l.id AND b.on_hand > 0));
  END IF;
  RETURN jsonb_build_object('location', l.name, 'ledger', 'legacy', 'in_cutover', f360.location_in_cutover(l.id), 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'channel_inventory_id', ci.id, 'product_name', ci.product_name, 'color', ci.color, 'size', ci.size, 'sku', ci.sku, 'price', ci.price,
      'available', greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)) ORDER BY ci.product_name, ci.color, ci.size), '[]'::jsonb)
    FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0));
END $$;
