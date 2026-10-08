-- Fuxia 360 · pase E3 — venta en caja con la clienta ligada, correo opcional, fotos en el catálogo de la vendedora (same as migration 20261013000200). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · CRM C2 (Mario 2026-10-08 "construye estas pantallas": registro rápido en caja). ADDITIVE.
-- 1 · f360_record_store_sale_for: the store sale with the customer LINKED by the seller (found by WhatsApp or just
--     registered), without scanning her card. It wraps f360_record_store_sale unchanged (same stock, price, idempotency,
--     reservation and audit rules):
--       · her phone is proven (she logged in to the app) → the sale goes through with her card, resolved here on the
--         server (the card token never reaches the seller's phone) → points credited now;
--       · not proven yet (registered at the counter) → the sale is recorded and linked to her, and its points are HELD
--         (f360.loyalty_credit_or_hold, same idempotency key 'offline_sale:<id>'); they are credited by the existing
--         trigger the first time she logs in to the app with that WhatsApp. Never twice.
--     A customer without a loyalty card gets one (token set by the existing trigger), as at sign-up.
-- 2 · f360_shift_customer_register: the e-mail becomes OPTIONAL (Mario: speed at the counter; the WhatsApp is the
--     identity). Everything else is unchanged.
-- 3 · f360_shift_catalog (F360 stores) also returns product_id, category and the colour's first photo (storage path in
--     the public product-images bucket), so the seller picks by photo. Same rows, same rules.
-- Rollback: supabase/rollbacks/20261013000200_f360_store_sale_customer.down.sql

CREATE FUNCTION public.f360_record_store_sale_for(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_ref uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); cu public.customers; card public.loyalty_cards;
  r jsonb; sale public.offline_sales; loy jsonb; lines jsonb; seller_name text;
BEGIN
  IF p_customer_ref IS NULL THEN
    RETURN public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, NULL);
  END IF;
  SELECT * INTO cu FROM public.customers WHERE id = p_customer_ref;
  IF cu.id IS NULL THEN RAISE EXCEPTION 'No encontramos a esa clienta.'; END IF;
  SELECT * INTO card FROM public.loyalty_cards WHERE customer_id = cu.id ORDER BY created_at LIMIT 1;
  IF card.id IS NULL THEN
    INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cu.id, '', 0, 0, 'bronze') RETURNING * INTO card;
    SELECT * INTO card FROM public.loyalty_cards WHERE id = card.id;                    -- token set by trigger
  END IF;

  IF f360.customer_identity_verified(cu.id) THEN
    r := public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, card.qr_code);
    RETURN r || jsonb_build_object('points_state', CASE WHEN (r->>'claimed')::boolean THEN 'credited' ELSE 'none' END,
                                   'customer', f360.customer_masked_card(cu.id));
  END IF;

  r := public.f360_record_store_sale(p_token, p_idempotency_key, p_lines, p_payment_method, p_payment_reference, NULL);
  SELECT * INTO sale FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid FOR UPDATE;
  IF sale.customer_id IS NULL AND sale.claimed_at IS NULL THEN                         -- not a replay already linked
    SELECT coalesce(jsonb_agg(jsonb_build_object('sku', i.sku, 'product_name', i.product_name, 'size', i.size, 'color', i.color,
             'category', p.category_key, 'quantity', i.quantity, 'unit_price', i.unit_price) ORDER BY i.line_no), '[]')
      INTO lines
      FROM public.offline_sale_items i LEFT JOIN f360.product_variants v ON v.id = i.variant_id LEFT JOIN f360.products p ON p.id = v.product_id
      WHERE i.sale_id = sale.id;
    SELECT display_name INTO seller_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
    loy := f360.loyalty_credit_or_hold(card.id, lines, sale.total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
      jsonb_build_object('type', 'seller', 'auth_user_id', s.auth_user_id, 'name', seller_name, 'location_id', s.location_id, 'session_id', s.id));
    -- linked to her: the claim code is closed (her points come from the hold, never twice)
    UPDATE public.offline_sales SET customer_id = cu.id, claimed_at = now(),
      points_earned = CASE WHEN loy->>'state' = 'credited' THEN coalesce((loy->>'points')::int, 0) ELSE 0 END
      WHERE id = sale.id;
  ELSE
    SELECT jsonb_build_object('state', h.status, 'points_pending', public.loyalty_pairs_for_lines(h.lines) * public.loyalty_points_per_pair())
      INTO loy FROM f360.loyalty_holds h WHERE h.idempotency_key = 'offline_sale:' || sale.id;
  END IF;
  RETURN (r - 'code') || jsonb_build_object('claimed', true, 'points_state', coalesce(loy->>'state', 'none'),
    'points', coalesce((loy->>'points_pending')::int, (loy->>'points')::int, 0), 'customer', f360.customer_masked_card(cu.id));
END $$;

-- Sign-up at the counter: e-mail optional (only change: the e-mail check runs when one is given; '' is stored as NULL).
CREATE OR REPLACE FUNCTION public.f360_shift_customer_register(p_token text, p_phone text, p_name text, p_email text,
  p_postal_code text DEFAULT NULL, p_birthday_day int DEFAULT NULL, p_birthday_month int DEFAULT NULL, p_shoe_size text DEFAULT NULL,
  p_country text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); ph text; nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  em text := nullif(lower(btrim(coalesce(p_email, ''))), ''); cp text := nullif(upper(btrim(coalesce(p_postal_code, ''))), ''); sz text := nullif(btrim(coalesce(p_shoe_size, '')), '');
  cid uuid; bad text;
BEGIN
  IF f360.crm_rate_limited(s) THEN PERFORM f360.crm_log(s, 'register', NULL, 'rate_limited'); RETURN f360.crm_refusal('rate_limited'); END IF;
  ph := f360.normalize_phone(p_phone, coalesce(p_country, 'MX'));
  bad := CASE WHEN ph IS NULL THEN 'invalid_phone'
              WHEN length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN 'invalid_name'
              WHEN em IS NOT NULL AND (em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(em) > 254) THEN 'invalid_email'
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

CREATE OR REPLACE FUNCTION public.f360_shift_catalog(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RETURN jsonb_build_object('location', l.name, 'ledger', 'f360', 'in_cutover', false, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', v.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
        'price', coalesce(p.sale_price, p.regular_price), 'available', b.on_hand, 'reserved', f360.reserved_qty(v.id, l.id),
        'product_id', p.id, 'category', p.category_key,
        'image', (SELECT m.storage_path FROM f360.product_media m WHERE m.product_id = p.id ORDER BY (m.color_id IS NOT DISTINCT FROM c.id) DESC, m.sort, m.created_at LIMIT 1)) ORDER BY p.name, c.sort, v.size_label), '[]'::jsonb)
      FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id WHERE b.location_id = l.id AND b.on_hand > 0));
  END IF;
  RETURN jsonb_build_object('location', l.name, 'ledger', 'legacy', 'in_cutover', f360.location_in_cutover(l.id), 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'channel_inventory_id', ci.id, 'product_name', ci.product_name, 'color', ci.color, 'size', ci.size, 'sku', ci.sku, 'price', ci.price,
      'available', greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)) ORDER BY ci.product_name, ci.color, ci.size), '[]'::jsonb)
    FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0));
END $$;

REVOKE ALL ON FUNCTION public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid) TO authenticated, service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261013000200', 'f360_store_sale_customer', '{}');
COMMIT;
