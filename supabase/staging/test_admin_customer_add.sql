-- Rehearsal of 20261013000300_f360_admin_customer_add — NEVER commits: it ends with RAISE 'ENSAYO OK' (success = that message).
-- Run: scripts/f360/prod_sql.sh --dry-run supabase/staging/test_admin_customer_add.sql
BEGIN;
CREATE FUNCTION public.f360_admin_customer_add(p_phone text, p_name text, p_email text DEFAULT NULL, p_postal_code text DEFAULT NULL,
  p_birthday_day int DEFAULT NULL, p_birthday_month int DEFAULT NULL, p_shoe_size text DEFAULT NULL, p_country text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); ph text; nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  em text := nullif(lower(btrim(coalesce(p_email, ''))), ''); cp text := nullif(upper(btrim(coalesce(p_postal_code, ''))), ''); sz text := nullif(btrim(coalesce(p_shoe_size, '')), '');
  cid uuid; bad text;
BEGIN
  ph := f360.normalize_phone(p_phone, coalesce(nullif(btrim(p_country), ''), 'MX'));
  bad := CASE WHEN ph IS NULL THEN 'Escribe un WhatsApp válido (10 dígitos).'
              WHEN length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN 'Escribe su nombre (sin números).'
              WHEN em IS NOT NULL AND (em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(em) > 254) THEN 'El correo no es válido.'
              WHEN cp IS NOT NULL AND cp !~ '^[0-9A-Z -]{3,10}$' THEN 'El código postal no es válido.'
              WHEN (p_birthday_day IS NULL) <> (p_birthday_month IS NULL)
                OR (p_birthday_month IS NOT NULL AND (p_birthday_month NOT BETWEEN 1 AND 12 OR p_birthday_day NOT BETWEEN 1 AND
                    CASE WHEN p_birthday_month = 2 THEN 29 WHEN p_birthday_month IN (4, 6, 9, 11) THEN 30 ELSE 31 END)) THEN 'El cumpleaños no es válido (día y mes).'
              WHEN sz IS NOT NULL AND (length(sz) > 6 OR sz !~ '^[0-9]{2}(\.5)?$') THEN 'La talla no es válida (ej. 37 o 37.5).' END;
  IF bad IS NOT NULL THEN
    INSERT INTO f360.customer_access_log (auth_user_id, action, result) VALUES (uid, 'register', 'invalid');
    RETURN jsonb_build_object('ok', false, 'error', bad);
  END IF;
  SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
  IF cid IS NULL THEN
    BEGIN
      INSERT INTO public.customers (phone, name, email, country, postal_code, birthday_day, birthday_month, shoe_size, source, registered_by, role)
        VALUES (ph, nm, em, CASE WHEN ph LIKE '+57%' THEN 'CO' WHEN ph LIKE '+1%' THEN 'US' ELSE 'MX' END, cp, p_birthday_day, p_birthday_month, sz,
                'admin', uid, 'customer')
        RETURNING id INTO cid;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
    END;
    IF NOT EXISTS (SELECT 1 FROM public.loyalty_cards WHERE customer_id = cid) THEN
      INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cid, '', 0, 0, 'bronze');   -- token set by trigger
      PERFORM f360.record_consent(cid, 'privacy_notice', 'requested',
        (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'privacy_notice' AND status = 'active'), 'admin',
        jsonb_build_object('auth_user_id', uid));
      INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'register', cid, 'created');
      RETURN jsonb_build_object('ok', true, 'created', true, 'customer_ref', cid);
    END IF;
  END IF;
  INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'register', cid, 'existing');
  RETURN jsonb_build_object('ok', true, 'created', false, 'customer_ref', cid,
    'role', (SELECT role FROM public.customers WHERE id = cid));
END $$;

REVOKE ALL ON FUNCTION public.f360_admin_customer_add(text, text, text, text, int, int, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_admin_customer_add(text, text, text, text, int, int, text, text) TO authenticated, service_role;
DO $$
DECLARE j jsonb; k jsonb; c public.customers; n int;
BEGIN
  IF EXISTS (SELECT 1 FROM public.customers WHERE f360.normalize_phone(phone) = '+525599990042') THEN RAISE EXCEPTION 'fixture: phone in use'; END IF;
  -- T0 · not a PII viewer → refused
  PERFORM set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
  BEGIN PERFORM public.f360_admin_customer_add('5599990042', 'Prueba Clienta'); RAISE EXCEPTION 'T0 non-viewer accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
  -- T1 · bad input → ok false, nothing created
  j := public.f360_admin_customer_add('123', 'Prueba Clienta');           IF (j->>'ok')::boolean THEN RAISE EXCEPTION 'T1 phone %', j; END IF;
  j := public.f360_admin_customer_add('5599990042', 'P4');                IF (j->>'ok')::boolean THEN RAISE EXCEPTION 'T1 name %', j; END IF;
  j := public.f360_admin_customer_add('5599990042', 'Prueba Clienta', 'x@'); IF (j->>'ok')::boolean THEN RAISE EXCEPTION 'T1 email %', j; END IF;
  j := public.f360_admin_customer_add('5599990042', 'Prueba Clienta', NULL, NULL, 31, 2); IF (j->>'ok')::boolean THEN RAISE EXCEPTION 'T1 bday %', j; END IF;
  -- T2 · created: source admin, card with server token, consent requested
  j := public.f360_admin_customer_add('55 9999 0042', '  Prueba   Clienta ', '', '66250', 8, 10, '38');
  IF NOT (j->>'created')::boolean THEN RAISE EXCEPTION 'T2 %', j; END IF;
  SELECT * INTO c FROM public.customers WHERE id = (j->>'customer_ref')::uuid;
  IF c.phone <> '+525599990042' OR c.name <> 'Prueba Clienta' OR c.email IS NOT NULL OR c.source <> 'admin' OR c.role <> 'customer'
     OR c.postal_code <> '66250' OR c.shoe_size <> '38' OR c.birthday_month <> 10 OR c.registered_by <> 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b' THEN RAISE EXCEPTION 'T2 row %', to_jsonb(c); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.loyalty_cards WHERE customer_id = c.id AND qr_code LIKE 'FX-%' AND length(qr_code) > 20) THEN RAISE EXCEPTION 'T2 card'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.customer_consent_events WHERE customer_id = c.id AND source = 'admin' AND status = 'requested') THEN RAISE EXCEPTION 'T2 consent'; END IF;
  -- T3 · same WhatsApp written differently → the same customer, nothing overwritten, no second card
  k := public.f360_admin_customer_add('+52 (55) 9999-0042', 'Otro Nombre', 'otro@correo.com');
  IF (k->>'created')::boolean OR k->>'customer_ref' <> j->>'customer_ref' THEN RAISE EXCEPTION 'T3 %', k; END IF;
  IF (SELECT name FROM public.customers WHERE id = c.id) <> 'Prueba Clienta' OR (SELECT count(*) FROM public.loyalty_cards WHERE customer_id = c.id) <> 1 THEN RAISE EXCEPTION 'T3 overwritten'; END IF;
  -- T4 · she shows in the Clientas list; every call logged without personal data
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.f360_admin_customers('5599990042')) x WHERE x->>'customer_ref' = c.id::text) THEN RAISE EXCEPTION 'T4 list'; END IF;
  SELECT count(*) INTO n FROM f360.customer_access_log WHERE action = 'register' AND auth_user_id = 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b' AND at >= now();
  IF n < 6 THEN RAISE EXCEPTION 'T4 log %', n; END IF;
  RAISE EXCEPTION 'ENSAYO OK';
END $$;
COMMIT;
