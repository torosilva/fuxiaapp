-- Fuxia 360 · "Apártalas 3 horas" for EVERY customer, confirmed by a WhatsApp code (Mario 2026-10-09: option B — "cualquiera",
-- "3 horas en lugar de 2", "el código tiene que pedirse, sin duda, para saber que el teléfono es real").
-- Business-rule change (approved by Mario, in this order of the conversation):
--   · f360.reserve: no longer Fuxia Gold only; a hold lasts 3 hours (was 2). Unchanged: max 2 pairs per customer, only a free pair
--     (on hand − holds) in a selling store, the last pair serialized, expiry releases the pair by itself.
-- New (additive):
--   · f360.reserve_codes: one-time 6-digit codes for the store's product page, stored HASHED (sha256 with the phone), 10 minutes,
--     max 3 codes per phone per 10 minutes, max 5 attempts per code. Never readable by anon/authenticated.
--   · public.f360_reserve_code_issue(phone, country)  service_role → { ok, code } (the Edge Function sends it by WhatsApp)
--   · public.f360_reserve_with_code(phone, code, name, location_id, variant_id, country)  service_role → checks the code, finds the
--     customer by phone or registers her (name required; source 'woo' = online store, privacy notice 'requested' via 'web'),
--     then f360.reserve(..., 'web', 'clienta').
--   · public.f360_store_availability: the size is resolved through the store's links even while the channel is inactive
--     (woo_production stays inactive: no stock sync is switched on by this).
-- Rollback: supabase/rollbacks/20261020000200_f360_reserve_open_whatsapp.down.sql (restores Gold-only, 2 hours, old availability).

-- ══ 1 · The rule: any customer, 3 hours ═══════════════════════════════════════
CREATE OR REPLACE FUNCTION f360.reserve(p_customer uuid, p_location uuid, p_variant uuid, p_channel text, p_by text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE l f360.locations; v_open int; v_on int; res f360.reservations;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer) THEN RAISE EXCEPTION 'No encontramos a la clienta.'; END IF;
  SELECT * INTO l FROM f360.locations WHERE id = p_location;
  IF l.id IS NULL OR l.status <> 'active' OR NOT l.sellable OR l.type NOT IN ('store', 'bazaar') OR l.ledger_authority <> 'f360' OR f360.location_in_cutover(l.id) THEN
    RAISE EXCEPTION 'Esa tienda no tiene apartados disponibles.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = p_variant AND status = 'active') THEN RAISE EXCEPTION 'Esa talla no existe.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('f360-res-cust:' || p_customer, 0));    -- one reservation at a time per customer
  SELECT count(*) INTO v_open FROM f360.reservations WHERE customer_id = p_customer AND status = 'activa' AND expires_at > clock_timestamp();
  IF v_open >= 2 THEN RAISE EXCEPTION 'Ya tienes 2 pares apartados. Recógelos o cancela uno para apartar otro.'; END IF;
  SELECT on_hand INTO v_on FROM f360.inventory_balances WHERE variant_id = p_variant AND location_id = l.id FOR UPDATE;   -- serializes the last pair
  IF coalesce(v_on, 0) - f360.reserved_qty(p_variant, l.id) < 1 THEN RAISE EXCEPTION 'Ya no hay ese par disponible en %.', l.name; END IF;
  INSERT INTO f360.reservations (location_id, variant_id, customer_id, channel, expires_at)
    VALUES (l.id, p_variant, p_customer, p_channel, clock_timestamp() + interval '3 hours') RETURNING * INTO res;
  RETURN jsonb_build_object('id', res.id, 'store', l.name, 'variant', f360.variant_label(p_variant), 'expires_at', res.expires_at, 'status', res.status);
END $$;

-- ══ 2 · Availability works with the channel inactive ═════════════════════════
CREATE OR REPLACE FUNCTION public.f360_store_availability(p_variant_id uuid DEFAULT NULL, p_woo_variation_id int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v uuid := p_variant_id;
BEGIN
  IF v IS NULL AND p_woo_variation_id IS NOT NULL THEN
    SELECT vl.variant_id INTO v FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id
      WHERE vl.woo_variation_id = p_woo_variation_id ORDER BY t.active DESC, t.is_production DESC, t.created_at LIMIT 1;
    IF v IS NULL THEN
      SELECT m.confirmed_variant_id INTO v FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id
        WHERE m.woo_variation_id = p_woo_variation_id AND m.status = 'confirmado' ORDER BY t.active DESC, t.is_production DESC, t.created_at LIMIT 1;
    END IF;
  END IF;
  IF v IS NULL THEN RETURN jsonb_build_object('variant_id', NULL, 'stores', '[]'::jsonb); END IF;
  RETURN jsonb_build_object('variant_id', v, 'stores', f360.store_availability(v));
END $$;

-- ══ 3 · One-time WhatsApp codes ═══════════════════════════════════════════════
CREATE TABLE f360.reserve_codes (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  phone       text NOT NULL CHECK (phone ~ '^\+[0-9]{10,15}$'),
  code_hash   text NOT NULL,
  attempts    int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz
);
CREATE INDEX reserve_codes_phone_idx ON f360.reserve_codes (phone, created_at DESC);
ALTER TABLE f360.reserve_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.reserve_codes FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE f360.reserve_codes IS 'One-time WhatsApp codes for "Apártalas 3 horas" on the store product page. Hashed; 10 minutes; 3 per phone / 10 min; 5 attempts.';

CREATE FUNCTION f360.reserve_code_hash(p_phone text, p_code text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(extensions.digest(p_phone || ':' || p_code, 'sha256'), 'hex')
$$;

CREATE FUNCTION public.f360_reserve_code_issue(p_phone text, p_country text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ph text := f360.normalize_phone(p_phone, coalesce(nullif(p_country, ''), 'MX')); v_code text; n int;
BEGIN
  IF ph IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe tu WhatsApp a 10 dígitos.'); END IF;
  SELECT count(*) INTO n FROM f360.reserve_codes WHERE phone = ph AND created_at > clock_timestamp() - interval '10 minutes';
  IF n >= 3 THEN RETURN jsonb_build_object('ok', false, 'error', 'Ya te mandamos 3 códigos. Espera 10 minutos e inténtalo otra vez.'); END IF;
  v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000))::text, 6, '0');
  INSERT INTO f360.reserve_codes (phone, code_hash, expires_at) VALUES (ph, f360.reserve_code_hash(ph, v_code), clock_timestamp() + interval '10 minutes');
  RETURN jsonb_build_object('ok', true, 'phone', ph, 'code', v_code);
END $$;

CREATE FUNCTION public.f360_reserve_with_code(p_phone text, p_code text, p_name text, p_location_id uuid, p_variant_id uuid, p_country text DEFAULT 'MX')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ph text := f360.normalize_phone(p_phone, coalesce(nullif(p_country, ''), 'MX')); c f360.reserve_codes; cid uuid; created boolean := false;
  nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')); r jsonb;
BEGIN
  IF ph IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe tu WhatsApp a 10 dígitos.'); END IF;
  SELECT * INTO c FROM f360.reserve_codes WHERE phone = ph AND used_at IS NULL AND expires_at > clock_timestamp()
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF c.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'El código ya venció. Pide uno nuevo.'); END IF;
  IF c.attempts >= 5 THEN RETURN jsonb_build_object('ok', false, 'error', 'Demasiados intentos. Pide un código nuevo.'); END IF;
  IF c.code_hash <> f360.reserve_code_hash(ph, btrim(coalesce(p_code, ''))) THEN
    UPDATE f360.reserve_codes SET attempts = attempts + 1 WHERE id = c.id;
    RETURN jsonb_build_object('ok', false, 'error', 'El código no es correcto. Revisa el WhatsApp que te mandamos.');
  END IF;
  -- the phone is proven: find her, or register her with this number
  SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
  IF cid IS NULL THEN
    IF length(nm) < 2 OR length(nm) > 80 OR nm ~ '\d' THEN RETURN jsonb_build_object('ok', false, 'error', 'Escribe tu nombre.'); END IF;
    BEGIN
      INSERT INTO public.customers (phone, name, country, source, role)
        VALUES (ph, nm, CASE WHEN ph LIKE '+57%' THEN 'CO' ELSE 'MX' END, 'woo', 'customer') RETURNING id INTO cid;
      created := true;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
    END;
    IF created THEN
      INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cid, '', 0, 0, 'bronze');
      PERFORM f360.record_consent(cid, 'privacy_notice', 'requested',
        (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'privacy_notice' AND status = 'active'), 'web',
        jsonb_build_object('flow', 'apartado_tienda_en_linea'), jsonb_build_object('phone_verified', 'whatsapp_code'));
    END IF;
  END IF;
  r := f360.reserve(cid, p_location_id, p_variant_id, 'web', 'clienta');     -- raises with a customer-readable message
  UPDATE f360.reserve_codes SET used_at = clock_timestamp() WHERE id = c.id;   -- only a successful hold consumes the code
  RETURN jsonb_build_object('ok', true, 'created', created, 'first_name', (SELECT split_part(btrim(name), ' ', 1) FROM public.customers WHERE id = cid), 'reservation', r);
END $$;

REVOKE ALL ON FUNCTION f360.reserve_code_hash(text, text), public.f360_reserve_code_issue(text, text),
  public.f360_reserve_with_code(text, text, text, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_reserve_code_issue(text, text), public.f360_reserve_with_code(text, text, text, uuid, uuid, text) TO service_role;
