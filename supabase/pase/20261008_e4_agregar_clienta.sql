-- Fuxia 360 · pase E4 — botón "Agregar clienta" en Clientas (same as migration 20261013000300). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · CRM C5 (Mario 2026-10-08: "falta botón de agregar cliente en Fuxia 360"). ADDITIVE.
-- f360_admin_customer_add: Carolina / Mario add a customer from the admin (e.g. a WhatsApp / Instagram sale). Same rules as
-- the counter sign-up (f360_shift_customer_register): WhatsApp is the identity (normalized, never twice), name required,
-- e-mail / CP / birthday / size optional and validated; loyalty card with a server token; privacy notice 'requested'.
-- Differences: only customer_pii_viewers may call it (f360.require_pii_viewer, same as the Clientas list), source 'admin',
-- no seller session, and it returns her id so the admin opens her profile. An existing WhatsApp returns that customer
-- unchanged (nothing is overwritten). Every call is logged in f360.customer_access_log (action 'register', no personal data).
-- Rollback: supabase/rollbacks/20261013000300_f360_admin_customer_add.down.sql

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
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261013000300', 'f360_admin_customer_add', '{}');
COMMIT;
