-- Fuxia 360 · pase E2 — Vendedoras se administran desde Fuxia 360 (same as migration 20261013000100). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · Vendedoras managed ONLY from the admin (Mario 2026-10-08: "todo debería ser gestionado desde Fuxia 360…
-- un apartado de vendedoras, asignarlas a tienda y la app reconozca a qué tienda está asignada y listo"). ADDITIVE.
--
-- One form (owner): name + WhatsApp + store + PIN. The seller is stored by her normalized phone in f360.sellers.
--   · Already has an app account (customers.auth_user_id): she is activated at once — role 'seller', her store, her PIN.
--   · No account yet: a customers row (role 'staff') is created with her phone so the app's "Ya tengo cuenta" login
--     finds her; the first time she logs in (whatsapp-otp links auth_user_id) the trigger activates her. No sign-up
--     step, no command, no second action in the admin.
-- Change store / reset PIN / deactivate: owner, from the same screen; every change revokes her open shifts and is
-- written to f360.access_changes (append-only). The PIN is bcrypt-hashed here; it is never stored or returned in clear.
-- Existing machinery reused as is: f360.user_roles, f360.location_assignments, f360.seller_credentials,
-- f360_start_seller_shift / f360_my_locations (the app opens her only store after the PIN).
-- Rollback: supabase/rollbacks/20261013000100_f360_sellers_admin.down.sql

CREATE TABLE f360.sellers (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone            text NOT NULL UNIQUE,                       -- E.164 (f360.normalize_phone)
  name             text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  location_id      uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  pin_hash         text NOT NULL CHECK (pin_hash LIKE '$2%'),  -- bcrypt only
  status           text NOT NULL DEFAULT 'pendiente' CHECK (status IN ('pendiente', 'activa', 'inactiva')),
  customer_id      uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  auth_user_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by_name  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  activated_at     timestamptz,
  updated_at       timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360.sellers ENABLE ROW LEVEL SECURITY;          -- no policies: only the SECURITY DEFINER functions below

-- What the admin sees: never the hash, only the last 4 digits of the phone.
CREATE FUNCTION f360.seller_json(s f360.sellers) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('id', s.id, 'name', s.name, 'phone_last4', right(s.phone, 4), 'status', s.status,
    'location', jsonb_build_object('id', l.id, 'name', l.name), 'activated_at', s.activated_at, 'created_at', s.created_at,
    'locked', coalesce(c.hard_locked OR c.locked_until > now(), false))
  FROM f360.locations l LEFT JOIN f360.seller_credentials c ON c.auth_user_id = s.auth_user_id WHERE l.id = s.location_id
$$;

-- Gives an account its seller access: role, her ONE store, her PIN. Never downgrades an owner/operator.
CREATE FUNCTION f360.activate_seller(p_seller uuid, p_auth_user_id uuid, p_by_name text, p_by_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.sellers; before jsonb;
BEGIN
  SELECT * INTO s FROM f360.sellers WHERE id = p_seller FOR UPDATE;
  IF s.id IS NULL OR s.status = 'inactiva' THEN RETURN; END IF;
  SELECT to_jsonb(u) INTO before FROM f360.user_roles u WHERE auth_user_id = p_auth_user_id;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (p_auth_user_id, 'seller', s.name, p_by_name)
    ON CONFLICT (auth_user_id) DO UPDATE SET display_name = EXCLUDED.display_name, granted_by = EXCLUDED.granted_by
      WHERE f360.user_roles.role IN ('seller', 'viewer');
  UPDATE f360.user_roles SET role = 'seller' WHERE auth_user_id = p_auth_user_id AND role = 'viewer';
  UPDATE f360.location_assignments SET active = false, revoked_by_name = p_by_name, revoked_at = now()
    WHERE auth_user_id = p_auth_user_id AND active AND location_id <> s.location_id;
  INSERT INTO f360.location_assignments (auth_user_id, location_id, active, granted_by_name) VALUES (p_auth_user_id, s.location_id, true, p_by_name)
    ON CONFLICT (auth_user_id, location_id) DO UPDATE SET active = true, granted_by_name = EXCLUDED.granted_by_name, granted_at = now(),
      revoked_by_name = NULL, revoked_at = NULL;
  INSERT INTO f360.seller_credentials (auth_user_id, pin_hash, pin_set_by_name) VALUES (p_auth_user_id, s.pin_hash, p_by_name)
    ON CONFLICT (auth_user_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash, pin_set_at = now(), pin_set_by_name = EXCLUDED.pin_set_by_name,
      failed_attempts = 0, locked_until = NULL, hard_locked = false;
  UPDATE f360.sellers SET status = 'activa', auth_user_id = p_auth_user_id, activated_at = coalesce(activated_at, now()), updated_at = now()
    WHERE id = s.id;
  PERFORM f360.log_seller(p_auth_user_id, s.location_id, 'pin_set', jsonb_build_object('by', p_by_name, 'via', 'vendedoras'));
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('seller_activated', p_auth_user_id::text, before, jsonb_build_object('seller', s.id, 'name', s.name, 'location', s.location_id), p_by_name, p_by_user);
END $$;

-- First app login with her phone (whatsapp-otp sets customers.auth_user_id) → a pending seller becomes active.
CREATE FUNCTION f360.customers_activate_seller() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.sellers;
BEGIN
  IF NEW.auth_user_id IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.auth_user_id IS DISTINCT FROM NEW.auth_user_id) THEN
    SELECT * INTO s FROM f360.sellers WHERE phone = f360.normalize_phone(NEW.phone) AND status = 'pendiente';
    IF s.id IS NOT NULL THEN
      UPDATE f360.sellers SET customer_id = NEW.id WHERE id = s.id;
      PERFORM f360.activate_seller(s.id, NEW.auth_user_id, s.created_by_name, NULL);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER customers_activate_seller AFTER INSERT OR UPDATE OF auth_user_id ON public.customers
  FOR EACH ROW EXECUTE FUNCTION f360.customers_activate_seller();

CREATE FUNCTION f360.seller_pin_hash(p_pin text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE prm jsonb := f360.seller_params();
BEGIN
  IF p_pin IS NULL OR p_pin !~ ('^[0-9]{' || (prm->>'pin_length') || '}$') THEN RAISE EXCEPTION 'El PIN debe tener % dígitos.', prm->>'pin_length'; END IF;
  RETURN extensions.crypt(p_pin, extensions.gen_salt('bf', 10));
END $$;

CREATE FUNCTION f360.assert_seller_store(p_location_id uuid) RETURNS f360.locations LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location_id AND status = 'active' AND sellable;
  IF l.id IS NULL THEN RAISE EXCEPTION 'Elige una tienda o bazar donde se vende.'; END IF;
  RETURN l;
END $$;

-- ── Admin RPCs (owner) ────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_admin_sellers() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('owner');
  RETURN (SELECT coalesce(jsonb_agg(f360.seller_json(s) ORDER BY s.status = 'inactiva', s.name), '[]') FROM f360.sellers s);
END $$;

CREATE FUNCTION public.f360_admin_seller_add(p_name text, p_phone text, p_location_id uuid, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); ph text := f360.normalize_phone(p_phone, 'MX');
  nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')); h text; cu public.customers; s f360.sellers;
BEGIN
  IF ph IS NULL THEN RAISE EXCEPTION 'Revisa el WhatsApp (10 dígitos).'; END IF;
  IF length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN RAISE EXCEPTION 'Escribe el nombre de la vendedora.'; END IF;
  PERFORM f360.assert_seller_store(p_location_id);
  h := f360.seller_pin_hash(p_pin);
  SELECT * INTO s FROM f360.sellers WHERE phone = ph FOR UPDATE;
  IF s.id IS NOT NULL AND s.status <> 'inactiva' THEN RAISE EXCEPTION '% ya es vendedora (%).', s.name, s.status; END IF;

  SELECT * INTO cu FROM public.customers WHERE f360.normalize_phone(phone) = ph ORDER BY created_at LIMIT 1;
  IF cu.id IS NULL THEN
    -- the phone exactly as the app login writes it (+52 + 10 digits), so "Ya tengo cuenta" finds her
    INSERT INTO public.customers (phone, name, country, role) VALUES (ph, nm, CASE WHEN ph LIKE '+57%' THEN 'CO' ELSE 'MX' END, 'staff')
      RETURNING * INTO cu;
  END IF;

  IF s.id IS NULL THEN
    INSERT INTO f360.sellers (phone, name, location_id, pin_hash, customer_id, created_by_name)
      VALUES (ph, nm, p_location_id, h, cu.id, r.display_name) RETURNING * INTO s;
  ELSE
    UPDATE f360.sellers SET name = nm, location_id = p_location_id, pin_hash = h, customer_id = cu.id, status = 'pendiente',
      created_by_name = r.display_name, updated_at = now() WHERE id = s.id RETURNING * INTO s;
  END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('seller_added', s.id::text, NULL, jsonb_build_object('name', nm, 'phone_last4', right(ph, 4), 'location', p_location_id), r.display_name, r.auth_user_id);
  IF cu.auth_user_id IS NOT NULL THEN PERFORM f360.activate_seller(s.id, cu.auth_user_id, r.display_name, r.auth_user_id); END IF;
  SELECT * INTO s FROM f360.sellers WHERE id = s.id;
  RETURN f360.seller_json(s);
END $$;

CREATE FUNCTION public.f360_admin_seller_set_store(p_seller_id uuid, p_location_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); s f360.sellers; old uuid;
BEGIN
  PERFORM f360.assert_seller_store(p_location_id);
  SELECT * INTO s FROM f360.sellers WHERE id = p_seller_id FOR UPDATE;
  IF s.id IS NULL OR s.status = 'inactiva' THEN RAISE EXCEPTION 'Esa vendedora no está activa.'; END IF;
  old := s.location_id;
  UPDATE f360.sellers SET location_id = p_location_id, updated_at = now() WHERE id = s.id RETURNING * INTO s;
  IF s.status = 'activa' THEN
    PERFORM f360.revoke_seller_sessions(s.auth_user_id, NULL, 'Cambio de tienda');
    PERFORM f360.activate_seller(s.id, s.auth_user_id, r.display_name, r.auth_user_id);
  END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('seller_store', s.id::text, jsonb_build_object('location', old), jsonb_build_object('location', p_location_id), r.display_name, r.auth_user_id);
  SELECT * INTO s FROM f360.sellers WHERE id = s.id;
  RETURN f360.seller_json(s);
END $$;

CREATE FUNCTION public.f360_admin_seller_reset_pin(p_seller_id uuid, p_pin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); s f360.sellers; h text := f360.seller_pin_hash(p_pin);
BEGIN
  SELECT * INTO s FROM f360.sellers WHERE id = p_seller_id FOR UPDATE;
  IF s.id IS NULL OR s.status = 'inactiva' THEN RAISE EXCEPTION 'Esa vendedora no está activa.'; END IF;
  UPDATE f360.sellers SET pin_hash = h, updated_at = now() WHERE id = s.id RETURNING * INTO s;
  IF s.status = 'activa' THEN
    PERFORM f360.revoke_seller_sessions(s.auth_user_id, NULL, 'PIN cambiado');
    PERFORM f360.activate_seller(s.id, s.auth_user_id, r.display_name, r.auth_user_id);   -- writes the new hash, clears locks
  END IF;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('seller_pin', s.id::text, NULL, jsonb_build_object('pin_reset', true), r.display_name, r.auth_user_id);
  RETURN f360.seller_json(s);
END $$;

CREATE FUNCTION public.f360_admin_seller_deactivate(p_seller_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); s f360.sellers;
BEGIN
  SELECT * INTO s FROM f360.sellers WHERE id = p_seller_id FOR UPDATE;
  IF s.id IS NULL OR s.status = 'inactiva' THEN RAISE EXCEPTION 'Esa vendedora ya no está activa.'; END IF;
  IF s.auth_user_id IS NOT NULL THEN
    PERFORM f360.revoke_seller_sessions(s.auth_user_id, NULL, 'Vendedora dada de baja');
    UPDATE f360.location_assignments SET active = false, revoked_by_name = r.display_name, revoked_at = now()
      WHERE auth_user_id = s.auth_user_id AND active;
    DELETE FROM f360.seller_credentials WHERE auth_user_id = s.auth_user_id;
    DELETE FROM f360.user_roles WHERE auth_user_id = s.auth_user_id AND role = 'seller';
  END IF;
  UPDATE f360.sellers SET status = 'inactiva', updated_at = now() WHERE id = s.id RETURNING * INTO s;
  INSERT INTO f360.access_changes (what, subject, before, after, by_name, by_user)
    VALUES ('seller_deactivated', s.id::text, NULL, jsonb_build_object('name', s.name), r.display_name, r.auth_user_id);
  RETURN f360.seller_json(s);
END $$;

-- ── Grants ────────────────────────────────────────────────────────────────────
REVOKE ALL ON f360.sellers FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION f360.seller_json(f360.sellers), f360.activate_seller(uuid, uuid, text, uuid), f360.customers_activate_seller(),
  f360.seller_pin_hash(text), f360.assert_seller_store(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_admin_sellers(), public.f360_admin_seller_add(text, text, uuid, text),
  public.f360_admin_seller_set_store(uuid, uuid), public.f360_admin_seller_reset_pin(uuid, text), public.f360_admin_seller_deactivate(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_admin_sellers(), public.f360_admin_seller_add(text, text, uuid, text),
  public.f360_admin_seller_set_store(uuid, uuid), public.f360_admin_seller_reset_pin(uuid, text), public.f360_admin_seller_deactivate(uuid)
  TO authenticated, service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261013000100', 'f360_sellers_admin', '{}');
COMMIT;
