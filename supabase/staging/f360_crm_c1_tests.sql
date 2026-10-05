-- Fuxia 360 CRM V1 · C1 — customer profile, privacy, consent, card token, holds — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
SELECT auth_user_id AS adrian FROM f360.user_roles WHERE display_name = 'Adrián' \gset
SELECT auth_user_id AS c1 FROM public.customers WHERE phone = '+15550100011' \gset
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.mario', :'mario', true), set_config('t.adrian', :'adrian', true),
       set_config('t.c1', :'c1', true), set_config('t.s1', :'s1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; mar uuid := current_setting('t.mario')::uuid; adr uuid := current_setting('t.adrian')::uuid;
  c1 uuid := current_setting('t.c1')::uuid; s1 uuid := current_setting('t.s1')::uuid;
  loc uuid; tok text; r jsonb; r2 jsonb; ana uuid; anacard public.loyalty_cards; c1cust uuid; c1card public.loyalty_cards; n int; m int; t text; sess uuid; r2uid uuid;
  pts_before int; lines jsonb := '[{"quantity":1,"sku":"ZZ-CRM-1","product_name":"ZZ Modelo","size":"24","color":"Nude"}]';
BEGIN
  -- ── fixtures: a store, a seller with a shift ──
  loc := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ CRM Tienda', 'store')$q$)->>'id')::uuid;
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora CRM')$q$, s1));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, s1, loc));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_seller_pin(%L, '2468')$q$, s1));
  tok := pg_temp.as(s1, format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, loc))->>'token';
  PERFORM pg_temp.ok(tok IS NOT NULL, 'fixture: seller shift started', coalesce(left(tok, 6), 'no token'));
  SELECT id INTO sess FROM f360.seller_sessions WHERE token_hash = f360.token_hash(tok);

  -- ══ phone normalization ══
  SELECT count(DISTINCT f360.normalize_phone(x)) INTO n FROM unnest(ARRAY['5590000001', '55 9000 0001', '(55) 9000-0001', '+52 55 9000 0001',
    '+52 1 55 9000 0001', '5215590000001', '045 55 9000 0001', '00525590000001']) x;
  PERFORM pg_temp.ok(n = 1 AND f360.normalize_phone('55 9000 0001') = '+525590000001', 'normalize: 8 ways of writing one Mexican number → one E.164', f360.normalize_phone('55 9000 0001'));
  PERFORM pg_temp.ok(f360.normalize_phone('+57 300 123 4567') = '+573001234567' AND f360.normalize_phone('3001234567', 'CO') = '+573001234567',
    'normalize: Colombia with +57 or country CO', f360.normalize_phone('+57 300 123 4567'));
  PERFORM pg_temp.ok(f360.normalize_phone('12345') IS NULL AND f360.normalize_phone('') IS NULL AND f360.normalize_phone('+52 55 12') IS NULL,
    'normalize: unusable input → NULL (refused, never guessed)', 'ok');
  SELECT count(*) INTO n FROM public.customers WHERE f360.normalize_phone(phone) IS DISTINCT FROM phone;
  PERFORM pg_temp.ok(n = 0, 'existing staging customers are already in canonical form (the app login stays compatible)', n || ' differ');

  -- ══ seller sign-up ══
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '55 9000 0001', ' ana   maría López ', 'Ana.Lopez@Example.com', '03100', 15, 3, '24')$q$, tok));
  ana := (r->'customer'->>'customer_ref')::uuid;
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND r->>'created' = 'true' AND ana IS NOT NULL, 'register: new customer created at the store', left(r::text, 120));
  PERFORM pg_temp.ok((SELECT phone = '+525590000001' AND name = 'ana maría López' AND email = 'ana.lopez@example.com' AND source = 'store'
                        AND registered_by = s1 AND registered_location = loc AND birthday_day = 15 AND birthday_month = 3 AND postal_code = '03100'
                      FROM public.customers WHERE id = ana), 'register: stored normalized phone, lower-case email, source=store, seller+location, birthday day/month, CP', 'ok');
  PERFORM pg_temp.ok((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(r->'customer') k) = ARRAY['customer_ref','first_name','has_card','identity_verified',
      'phone_last4','points','points_pending','privacy_consent','recent_purchases','shoe_size','sizes_bought','tier'],
    'masked card: exactly the allowed keys (no name, phone, email, CP, birthday)', (SELECT string_agg(k, ',') FROM jsonb_object_keys(r->'customer') k));
  PERFORM pg_temp.ok(r->'customer'->>'first_name' = 'Ana' AND r->'customer'->>'phone_last4' = '0001' AND r->'customer'->>'shoe_size' = '24',
    'masked card: first name + last 4 digits + size', (r->'customer')::text);
  PERFORM pg_temp.ok(position('9000' IN r::text) = 0 AND position('example.com' IN r::text) = 0 AND position('López' IN r::text) = 0
                     AND position('03100' IN r::text) = 0, 'masked card: the full phone, email, surname and CP never reach the seller', 'ok');

  -- ══ duplicates ══
  r2 := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '+52 1 55 9000 0001', 'Otra Persona', 'otra@example.com')$q$, tok));
  PERFORM pg_temp.ok(r2->>'created' = 'false' AND (r2->'customer'->>'customer_ref')::uuid = ana, 'duplicate: same number in another format → the existing customer, no new row', left(r2::text, 80));
  PERFORM pg_temp.ok((SELECT name = 'ana maría López' AND email = 'ana.lopez@example.com' FROM public.customers WHERE id = ana),
    'duplicate: an existing customer is never overwritten by the seller', 'ok');
  SELECT count(*) INTO n FROM public.customers WHERE f360.normalize_phone(phone) = '+525590000001';
  PERFORM pg_temp.ok(n = 1, 'duplicate: one row per normalized phone', n::text);
  BEGIN
    INSERT INTO public.customers (phone, name) VALUES ('5215590000001', 'ZZ Dup');
    PERFORM pg_temp.ok(false, 'duplicate: database refuses the same person in another format (any writer)', 'inserted!');
  EXCEPTION WHEN unique_violation THEN
    PERFORM pg_temp.ok(true, 'duplicate: database refuses the same person in another format (any writer)', SQLERRM);
  END;
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_find(%L, '(55) 9000-0001')$q$, tok));
  PERFORM pg_temp.ok(r->>'found' = 'true' AND (r->'customer'->>'customer_ref')::uuid = ana, 'find: any format finds her', left(r::text, 80));
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_find(%L, '55 9999 8888')$q$, tok));
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND r->>'found' = 'false' AND r->'customer' = 'null'::jsonb, 'find: unknown number → not found (nothing else)', r::text);

  -- ══ validation ══
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '123', 'Bea', 'bea@example.com')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_phone', 'register: bad phone refused', r->>'code');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '5590000002', 'Bea', 'no-es-correo')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_email', 'register: email required and checked', r->>'code');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '5590000002', '', 'bea@example.com')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_name', 'register: name required', r->>'code');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '5590000002', 'Bea', 'bea@example.com', NULL, 31, 2)$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_birthday', 'register: 31 Feb refused', r->>'code');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '5590000002', 'Bea', 'bea@example.com', NULL, 29, 2)$q$, tok));
  PERFORM pg_temp.ok(r->>'created' = 'true', 'register: optional fields can be skipped; 29 Feb allowed (no year)', left(r::text, 60));

  -- ══ card token ══
  SELECT * INTO anacard FROM public.loyalty_cards WHERE customer_id = ana;
  PERFORM pg_temp.ok(anacard.qr_code ~ '^FX-[0-9A-F]{24}$' AND position('90000001' IN anacard.qr_code) = 0 AND position(ana::text IN anacard.qr_code) = 0,
    'card: opaque random token (no phone, no id)', regexp_replace(anacard.qr_code, '.{16}$', '…'));
  PERFORM pg_temp.ok(anacard.total_points = 0 AND anacard.tier = 'bronze', 'card: new card starts at 0 / bronze', anacard.total_points::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_by_card(%L, %L)$q$, tok, anacard.qr_code));
  PERFORM pg_temp.ok(r->>'found' = 'true' AND (r->'customer'->>'customer_ref')::uuid = ana AND position(anacard.qr_code IN r::text) = 0,
    'card: scanning resolves her masked card (token itself never returned)', left(r::text, 80));
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_by_card(%L, 'FX-90000001-abc-00')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_card', 'card: unknown token refused', r->>'code');
  SELECT id INTO c1cust FROM public.customers WHERE auth_user_id = c1;
  r := pg_temp.as(c1, format($q$INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (%L, 'FX-50100011-k1-00', 99999, 50, 'gold') RETURNING to_jsonb(loyalty_cards.*)$q$, c1cust));
  PERFORM pg_temp.ok(r->>'qr_code' ~ '^FX-[0-9A-F]{24}$' AND (r->>'total_points')::int = 0 AND r->>'tier' = 'bronze',
    'card: the app can no longer choose its QR, points or tier (server token, 0, bronze)', left(r::text, 120));
  DELETE FROM public.loyalty_cards WHERE id = (r->>'id')::uuid;
  r := pg_temp.as(car, format($q$SELECT public.f360_admin_rotate_card_token(%L, 'tarjeta compartida en redes')$q$, ana));
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND (SELECT qr_code FROM public.loyalty_cards WHERE id = anacard.id) <> anacard.qr_code, 'card: Carolina can revoke (rotate) a token', r::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_by_card(%L, %L)$q$, tok, anacard.qr_code));
  PERFORM pg_temp.ok(r->>'code' = 'invalid_card', 'card: a revoked token no longer resolves', r->>'code');
  PERFORM pg_temp.ok((SELECT old_token_hash = f360.token_hash(anacard.qr_code) FROM f360.card_token_events WHERE card_id = anacard.id),
    'card: revocation audited with the hash only', 'ok');
  r := pg_temp.as(s1, format($q$SELECT public.f360_admin_rotate_card_token(%L, 'x x x')$q$, ana));
  PERFORM pg_temp.ok(r ? 'error', 'card: a seller cannot rotate tokens', r->>'error');

  -- ══ consent architecture (identity ≠ privacy ≠ marketing) ══
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_consent_state WHERE customer_id = ana AND purpose_key = 'privacy_notice') = 'requested'
      AND (SELECT status FROM f360.customer_consent_state WHERE customer_id = ana AND purpose_key = 'marketing_whatsapp') = 'none'
      AND (SELECT status FROM f360.customer_consent_state WHERE customer_id = ana AND purpose_key = 'marketing_email') = 'none',
    'consent: store sign-up = privacy REQUESTED; marketing WhatsApp/email untouched (none)', 'ok');
  PERFORM pg_temp.ok((SELECT source = 'store_signup' AND actor->>'seller' = s1::text FROM f360.customer_consent_events WHERE customer_id = ana),
    'consent: event records origin + who/where', 'ok');
  BEGIN
    PERFORM f360.record_consent(ana, 'marketing_whatsapp', 'granted', NULL, 'admin');
    PERFORM pg_temp.ok(false, 'consent: a decision without notice version is refused', 'accepted!');
  EXCEPTION WHEN check_violation THEN PERFORM pg_temp.ok(true, 'consent: a decision without notice version is refused', 'check_violation');
  END;
  INSERT INTO f360.consent_notice_versions (purpose_key, version, status) VALUES ('marketing_whatsapp', 'test-v1', 'active');
  BEGIN
    PERFORM f360.record_consent(ana, 'marketing_whatsapp', 'granted', (SELECT id FROM f360.consent_notice_versions WHERE version = 'test-v1'), 'admin');
    PERFORM f360.record_consent(ana, 'privacy_notice', 'granted', (SELECT id FROM f360.consent_notice_versions WHERE version = 'test-v1'), 'admin');
    PERFORM pg_temp.ok(false, 'consent: a version of another purpose is refused', 'accepted!');
  EXCEPTION WHEN raise_exception THEN PERFORM pg_temp.ok(true, 'consent: a version of another purpose is refused', SQLERRM);
  END;
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_consent_state WHERE customer_id = ana AND purpose_key = 'privacy_notice') = 'requested',
    'consent: granting marketing does not change privacy (independent purposes)', 'ok');
  BEGIN
    UPDATE f360.customer_consent_events SET status = 'granted' WHERE customer_id = ana;
    PERFORM pg_temp.ok(false, 'consent: events are append-only', 'updated!');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'consent: events are append-only', SQLERRM);
  END;

  -- ══ points states: held → released ══
  PERFORM pg_temp.ok(NOT f360.customer_identity_verified(ana), 'identity: a store sign-up is NOT verified (phone not proven yet)', 'ok');
  r := f360.loyalty_credit_or_hold(anacard.id, lines, 2800, 'store', 'offline_sale', 'zz-crm-sale-1', 'offline_sale:zz-crm-sale-1', jsonb_build_object('auth_user_id', s1));
  PERFORM pg_temp.ok(r->>'state' = 'held' AND (r->>'points_pending')::int = 100 AND (SELECT total_points FROM public.loyalty_cards WHERE id = anacard.id) = 0,
    'points: unverified customer → HELD (100 pending), card unchanged', r::text);
  r := f360.loyalty_credit_or_hold(anacard.id, lines, 2800, 'store', 'offline_sale', 'zz-crm-sale-1', 'offline_sale:zz-crm-sale-1', jsonb_build_object('auth_user_id', s1));
  SELECT count(*) INTO n FROM f360.loyalty_holds WHERE customer_id = ana;
  PERFORM pg_temp.ok(n = 1, 'points: a retried sale holds once (idempotency key)', n::text);
  PERFORM pg_temp.ok((f360.customer_masked_card(ana)->>'points_pending')::int = 100, 'points: the card shows 100 pending', 'ok');
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-crm-c1-ana@fuxia.app', 'authenticated', 'authenticated') RETURNING id INTO r2uid;
  UPDATE public.customers SET auth_user_id = r2uid WHERE id = ana;          -- = whatsapp-otp linking after her first app login
  PERFORM pg_temp.ok(f360.customer_identity_verified(ana) AND EXISTS (SELECT 1 FROM f360.customer_verifications WHERE customer_id = ana AND method = 'app_whatsapp_otp'),
    'identity: first app login (OTP) verifies her', 'ok');
  PERFORM pg_temp.ok((SELECT total_points FROM public.loyalty_cards WHERE id = anacard.id) = 100
      AND (SELECT status FROM f360.loyalty_holds WHERE customer_id = ana) = 'released'
      AND EXISTS (SELECT 1 FROM public.loyalty_apply_audit WHERE idempotency_key = 'offline_sale:zz-crm-sale-1' AND result = 'applied'),
    'points: verification RELEASES the hold through loyalty_apply (same key, same rules)', (SELECT total_points FROM public.loyalty_cards WHERE id = anacard.id)::text);
  PERFORM pg_temp.ok(f360.release_loyalty_holds(ana) = 0 AND (SELECT total_points FROM public.loyalty_cards WHERE id = anacard.id) = 100, 'points: never credited twice', 'ok');
  SELECT * INTO c1card FROM public.loyalty_cards WHERE customer_id = c1cust ORDER BY created_at LIMIT 1;
  pts_before := c1card.total_points;
  r := f360.loyalty_credit_or_hold(c1card.id, lines, 2800, 'store', 'offline_sale', 'zz-crm-sale-2', 'offline_sale:zz-crm-sale-2', jsonb_build_object('auth_user_id', s1));
  PERFORM pg_temp.ok(r->>'state' = 'credited' AND (SELECT total_points FROM public.loyalty_cards WHERE id = c1card.id) = pts_before + 100,
    'points: verified app customer → credited immediately', r->>'state');

  -- ══ privacy: who sees what ══
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = car) AND EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = mar)
      AND NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = adr), 'privacy: viewers = Carolina + Mario; Adrián is not', 'ok');
  r := pg_temp.as(car, $q$SELECT public.f360_admin_customers('ana')$q$);
  PERFORM pg_temp.ok(jsonb_typeof(r) = 'array' AND r->0->>'phone' = '+525590000001' AND r->0->>'email' = 'ana.lopez@example.com', 'privacy: Carolina sees full data', left(r::text, 80));
  r := pg_temp.as(car, $q$SELECT public.f360_admin_customers('0001')$q$);
  PERFORM pg_temp.ok(r @> jsonb_build_array(jsonb_build_object('customer_ref', ana)), 'privacy: Carolina can search by last 4 digits', jsonb_array_length(r)::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_admin_customer(%L)$q$, ana));
  PERFORM pg_temp.ok(r->'customer'->>'email' = 'ana.lopez@example.com' AND jsonb_array_length(r->'customer'->'consent_history') >= 1, 'privacy: Mario sees the full card + consent history', 'ok');
  r := pg_temp.as(adr, $q$SELECT public.f360_admin_customers()$q$);
  PERFORM pg_temp.ok(r ? 'error', 'privacy: an owner who is not a viewer (Adrián) is refused', r->>'error');
  r := pg_temp.as(s1, $q$SELECT public.f360_admin_customers()$q$);
  PERFORM pg_temp.ok(r ? 'error', 'privacy: a seller cannot list customers (no export path)', r->>'error');
  r := pg_temp.as(s1, format($q$SELECT public.f360_admin_customer(%L)$q$, ana));
  PERFORM pg_temp.ok(r ? 'error', 'privacy: a seller cannot open the full card', r->>'error');
  r := pg_temp.as(s1, $q$SELECT jsonb_agg(c) FROM public.customers c$q$);
  PERFORM pg_temp.ok(r IS NULL OR r ? 'error' OR NOT r::text LIKE '%ana.lopez%', 'privacy: a seller reading public.customers directly gets nothing of hers (RLS)', left(coalesce(r::text, 'null'), 60));
  r := pg_temp.as(s1, $q$SELECT jsonb_agg(x) FROM f360.customer_access_log x$q$);
  PERFORM pg_temp.ok(r ? 'error', 'privacy: f360 CRM tables are not readable by clients', r->>'error');
  r := pg_temp.as(NULL, format($q$SELECT public.f360_shift_customer_find(%L, '5590000001')$q$, tok), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'privacy: anon cannot call seller RPCs', r->>'error');
  r := pg_temp.as(c1, format($q$SELECT public.f360_shift_customer_find(%L, '5590000001')$q$, tok));
  PERFORM pg_temp.ok(r ? 'error', 'privacy: someone else''s shift token is refused', r->>'error');
  r := pg_temp.as(s1, $q$SELECT public.f360_shift_customer_find('no-token', '5590000001')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'privacy: no valid shift → refused', r->>'error');

  -- ══ audit + rate limit ══
  SELECT count(*) INTO n FROM f360.customer_access_log WHERE session_id = sess;
  PERFORM pg_temp.ok(n >= 12, 'audit: every seller lookup / sign-up / scan is logged with session + location', n::text);
  PERFORM pg_temp.ok((SELECT array_agg(column_name::text ORDER BY column_name) FROM information_schema.columns WHERE table_schema = 'f360' AND table_name = 'customer_access_log')
      = ARRAY['action','at','auth_user_id','customer_id','id','location_id','result','session_id'], 'audit: the log holds no phone, name or email', 'ok');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_access_log WHERE auth_user_id = car AND action = 'admin_list')
      AND EXISTS (SELECT 1 FROM f360.customer_access_log WHERE auth_user_id = mar AND action = 'admin_view' AND customer_id = ana), 'audit: Carolina/Mario full-data access is logged too', 'ok');
  BEGIN
    DELETE FROM f360.customer_access_log WHERE session_id = sess;
    PERFORM pg_temp.ok(false, 'audit: the log is append-only', 'deleted!');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'audit: the log is append-only', SQLERRM);
  END;
  SELECT count(*) INTO n FROM f360.customer_access_log WHERE session_id = sess AND action IN ('find_phone', 'find_card', 'register') AND result <> 'rate_limited';
  INSERT INTO f360.customer_access_log (auth_user_id, session_id, location_id, action, result)
    SELECT s1, sess, loc, 'find_phone', 'not_found' FROM generate_series(1, 60 - n);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_find(%L, '5590000001')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'rate_limited', 'rate limit: the 61st lookup of a shift is refused', r->>'error');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_register(%L, '5590000003', 'Cami', 'cami@example.com')$q$, tok));
  PERFORM pg_temp.ok(r->>'code' = 'rate_limited' AND NOT EXISTS (SELECT 1 FROM public.customers WHERE phone = '+525590000003'), 'rate limit: sign-up is limited too', r->>'code');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_access_log WHERE session_id = sess AND result = 'rate_limited'), 'rate limit: refusals are logged', 'ok');
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_customer_card(%L, %L)$q$, tok, ana));
  PERFORM pg_temp.ok(r->>'ok' = 'true', 'rate limit: the card already opened can still be viewed (sale can continue)', left(r::text, 40));

  -- ══ app compatibility ══
  UPDATE public.customers SET birthday = '1990-07-21' WHERE id = c1cust;
  PERFORM pg_temp.ok((SELECT birthday_day = 21 AND birthday_month = 7 FROM public.customers WHERE id = c1cust), 'app: a full birthday from the app fills day/month', 'ok');
  r := pg_temp.as(c1, $q$SELECT to_jsonb(c) FROM public.customers c WHERE auth_user_id = auth.uid()$q$);
  PERFORM pg_temp.ok(r->>'phone' = '+15550100011', 'app: a customer still reads her own row', left(coalesce(r::text, 'null'), 60));
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
