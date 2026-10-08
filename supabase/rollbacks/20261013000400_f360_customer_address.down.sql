-- Rollback of 20261013000400_f360_customer_address.sql. The address COLUMNS stay (real customer data, never dropped by a
-- rollback); only the functions return to C5. Re-run 20261013000300 to restore the 8-argument f360_admin_customer_add.
DROP FUNCTION IF EXISTS public.f360_admin_customer_set_contact(uuid, text, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS public.f360_admin_customer_add(text, text, text, text, int, int, text, text, text, text, text, text);
DROP FUNCTION IF EXISTS f360.customer_save_address(uuid, text, text, text, text, text, text);
CREATE OR REPLACE FUNCTION f360.customer_full(p_customer uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.customer_masked_card(c.id) || jsonb_build_object(
    'name', c.name, 'phone', c.phone, 'email', c.email, 'postal_code', c.postal_code, 'country', c.country,
    'birthday_day', c.birthday_day, 'birthday_month', c.birthday_month, 'source', c.source, 'created_at', c.created_at,
    'registered_location', (SELECT name FROM f360.locations WHERE id = c.registered_location),
    'consents', (SELECT jsonb_object_agg(purpose_key, status) FROM f360.customer_consent_state WHERE customer_id = c.id))
  FROM public.customers c WHERE c.id = p_customer
$$;
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
