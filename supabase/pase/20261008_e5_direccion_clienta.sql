-- Fuxia 360 · pase E5 — dirección en la ficha de clienta (same as migration 20261013000400). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · CRM C6 (Mario 2026-10-08: "tienes que guardar las direcciones… en la ficha de cliente debe de ser opcional cuando sea
-- en la tienda física pero para vender online siempre estará, y esto nos servirá para más adelante hacer análisis demográficos").
-- ADDITIVE. public.customers stays the one customer table (no second source of truth):
--   · address columns: street + number, neighborhood (colonia), city (municipio), state; the CP is the existing postal_code
--     and the country the existing country. All optional. address_source says where the last address came from
--     (admin | store | woo) and address_updated_at when, so later analysis can tell a typed address from an order's.
--   · f360.customer_full (Clientas list + ficha) returns them as 'address'.
--   · f360_admin_customer_add (C5) takes the address too (same function, wider signature; the admin is the only caller).
--   · f360_admin_customer_set_contact: Carolina / Mario correct a customer's address / CP / e-mail / name from her ficha.
--     PII viewers only, validated, logged (customer_access_log action 'admin_edit', no personal data in the log).
--   · f360.customer_save_address (server-only): the one place an address is written, reused by the online-order capture.
-- Rollback: supabase/rollbacks/20261013000400_f360_customer_address.down.sql

ALTER TABLE public.customers
  ADD COLUMN address_street text,
  ADD COLUMN address_neighborhood text,
  ADD COLUMN address_city text,
  ADD COLUMN address_state text,
  ADD COLUMN address_source text,
  ADD COLUMN address_updated_at timestamptz,
  ADD CONSTRAINT customers_address_len_check CHECK (length(address_street) <= 160 AND length(address_neighborhood) <= 120
    AND length(address_city) <= 120 AND length(address_state) <= 80),
  ADD CONSTRAINT customers_address_source_check CHECK (address_source IN ('admin', 'store', 'woo'));
COMMENT ON COLUMN public.customers.address_street IS 'CRM C6: calle y número (optional in store; online orders always bring it).';
COMMENT ON COLUMN public.customers.address_source IS 'CRM C6: where the current address came from: admin | store | woo.';

ALTER TABLE f360.customer_access_log DROP CONSTRAINT customer_access_log_action_check,
  ADD CONSTRAINT customer_access_log_action_check CHECK (action IN ('find_phone', 'find_card', 'register', 'view_card', 'admin_list', 'admin_view',
    'admin_rotate_card', 'admin_edit'));

-- Cleans and validates one address; NULL fields mean "not given". Raises with an operator-readable message.
CREATE FUNCTION f360.customer_save_address(p_customer uuid, p_street text, p_neighborhood text, p_city text, p_state text,
  p_postal_code text, p_source text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE clean text[] := ARRAY(SELECT nullif(btrim(regexp_replace(coalesce(x, ''), '\s+', ' ', 'g')), '') FROM unnest(ARRAY[p_street, p_neighborhood, p_city, p_state]) WITH ORDINALITY u(x, i) ORDER BY i);
  cp text := nullif(upper(btrim(coalesce(p_postal_code, ''))), '');
BEGIN
  IF length(clean[1]) > 160 OR length(clean[2]) > 120 OR length(clean[3]) > 120 OR length(clean[4]) > 80 THEN RAISE EXCEPTION 'La dirección es demasiado larga.'; END IF;
  IF cp IS NOT NULL AND cp !~ '^[0-9A-Z -]{3,10}$' THEN RAISE EXCEPTION 'El código postal no es válido.'; END IF;
  IF clean[1] IS NULL AND clean[2] IS NULL AND clean[3] IS NULL AND clean[4] IS NULL AND cp IS NULL THEN RETURN; END IF;
  UPDATE public.customers SET address_street = clean[1], address_neighborhood = clean[2], address_city = clean[3], address_state = clean[4],
      postal_code = coalesce(cp, postal_code), address_source = p_source, address_updated_at = now()
    WHERE id = p_customer;
END $$;
REVOKE ALL ON FUNCTION f360.customer_save_address(uuid, text, text, text, text, text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION f360.customer_full(p_customer uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.customer_masked_card(c.id) || jsonb_build_object(
    'name', c.name, 'phone', c.phone, 'email', c.email, 'postal_code', c.postal_code, 'country', c.country,
    'birthday_day', c.birthday_day, 'birthday_month', c.birthday_month, 'source', c.source, 'created_at', c.created_at,
    'registered_location', (SELECT name FROM f360.locations WHERE id = c.registered_location),
    'consents', (SELECT jsonb_object_agg(purpose_key, status) FROM f360.customer_consent_state WHERE customer_id = c.id),
    'address', CASE WHEN coalesce(c.address_street, c.address_neighborhood, c.address_city, c.address_state) IS NOT NULL THEN
      jsonb_build_object('street', c.address_street, 'neighborhood', c.address_neighborhood, 'city', c.address_city, 'state', c.address_state,
                         'source', c.address_source, 'updated_at', c.address_updated_at) END)
  FROM public.customers c WHERE c.id = p_customer
$$;

DROP FUNCTION public.f360_admin_customer_add(text, text, text, text, int, int, text, text);
CREATE FUNCTION public.f360_admin_customer_add(p_phone text, p_name text, p_email text DEFAULT NULL, p_postal_code text DEFAULT NULL,
  p_birthday_day int DEFAULT NULL, p_birthday_month int DEFAULT NULL, p_shoe_size text DEFAULT NULL, p_country text DEFAULT 'MX',
  p_street text DEFAULT NULL, p_neighborhood text DEFAULT NULL, p_city text DEFAULT NULL, p_state text DEFAULT NULL) RETURNS jsonb
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
              WHEN sz IS NOT NULL AND (length(sz) > 6 OR sz !~ '^[0-9]{2}(\.5)?$') THEN 'La talla no es válida (ej. 37 o 37.5).'
              WHEN length(p_street) > 160 OR length(p_neighborhood) > 120 OR length(p_city) > 120 OR length(p_state) > 80 THEN 'La dirección es demasiado larga.' END;
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
      PERFORM f360.customer_save_address(cid, p_street, p_neighborhood, p_city, p_state, NULL, 'admin');
      INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'register', cid, 'created');
      RETURN jsonb_build_object('ok', true, 'created', true, 'customer_ref', cid);
    END IF;
  END IF;
  INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'register', cid, 'existing');
  RETURN jsonb_build_object('ok', true, 'created', false, 'customer_ref', cid,
    'role', (SELECT role FROM public.customers WHERE id = cid));
END $$;

-- From her ficha: correct name / e-mail / CP / address. The WhatsApp (her identity) is NOT editable here.
CREATE FUNCTION public.f360_admin_customer_set_contact(p_customer uuid, p_name text, p_email text, p_postal_code text,
  p_street text, p_neighborhood text, p_city text, p_state text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  em text := nullif(lower(btrim(coalesce(p_email, ''))), ''); cp text := nullif(upper(btrim(coalesce(p_postal_code, ''))), '');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer AND role = 'customer') THEN RETURN jsonb_build_object('ok', false, 'error', 'No encontramos a esa clienta.'); END IF;
  IF length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe su nombre (sin números).'); END IF;
  IF em IS NOT NULL AND (em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' OR length(em) > 254) THEN RETURN jsonb_build_object('ok', false, 'error', 'El correo no es válido.'); END IF;
  IF cp IS NOT NULL AND cp !~ '^[0-9A-Z -]{3,10}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'El código postal no es válido.'); END IF;
  IF length(p_street) > 160 OR length(p_neighborhood) > 120 OR length(p_city) > 120 OR length(p_state) > 80 THEN RETURN jsonb_build_object('ok', false, 'error', 'La dirección es demasiado larga.'); END IF;
  UPDATE public.customers SET name = nm, email = em, postal_code = cp WHERE id = p_customer;
  UPDATE public.customers SET address_street = nullif(btrim(regexp_replace(coalesce(p_street, ''), '\s+', ' ', 'g')), ''),
      address_neighborhood = nullif(btrim(regexp_replace(coalesce(p_neighborhood, ''), '\s+', ' ', 'g')), ''),
      address_city = nullif(btrim(regexp_replace(coalesce(p_city, ''), '\s+', ' ', 'g')), ''),
      address_state = nullif(btrim(regexp_replace(coalesce(p_state, ''), '\s+', ' ', 'g')), ''),
      address_source = 'admin', address_updated_at = now()
    WHERE id = p_customer AND (address_street, address_neighborhood, address_city, address_state) IS DISTINCT FROM
      (nullif(btrim(regexp_replace(coalesce(p_street, ''), '\s+', ' ', 'g')), ''), nullif(btrim(regexp_replace(coalesce(p_neighborhood, ''), '\s+', ' ', 'g')), ''),
       nullif(btrim(regexp_replace(coalesce(p_city, ''), '\s+', ' ', 'g')), ''), nullif(btrim(regexp_replace(coalesce(p_state, ''), '\s+', ' ', 'g')), ''));
  INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'admin_edit', p_customer, 'ok');
  RETURN jsonb_build_object('ok', true, 'customer', f360.customer_full(p_customer));
END $$;

REVOKE ALL ON FUNCTION public.f360_admin_customer_add(text, text, text, text, int, int, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_admin_customer_add(text, text, text, text, int, int, text, text, text, text, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_admin_customer_set_contact(uuid, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_admin_customer_set_contact(uuid, text, text, text, text, text, text, text) TO authenticated, service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261013000400', 'f360_customer_address', '{}');
COMMIT;
