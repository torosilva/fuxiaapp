-- Fuxia 360 · CRM V1 · C1 — Customer profile (ficha), privacy, consent architecture, card token, loyalty holds. STAGING.
-- Plan: docs/fuxia360/crm/CRM_V1_PLAN.md (C1) · decisions: growth/CUSTOMER_360_MODEL.md §3.1 (Mario 2026-10-05).
-- ADDITIVE. public.customers stays the one customer table (no second source of truth); the production app keeps working.
--
-- Three layers, never mixed:
--   1. IDENTITY      public.customers (one row per normalized phone) + f360.customer_verifications (phone proven: app
--                    WhatsApp OTP today; WhatsApp link in C3).
--   2. PRIVACY       f360.customer_consent_events purpose 'privacy_notice' (uso de datos), versioned notice, append-only.
--   3. MARKETING     same events, purposes 'marketing_whatsapp' / 'marketing_email'. Confirming the account NEVER
--                    implies marketing consent. C1 records only 'requested' for privacy at store sign-up; legal text = C3.
-- Privacy rule (Mario): ONLY f360.customer_pii_viewers see full personal data. Sellers get a MASKED card (first name +
-- last 4 digits + size + points + purchases), only through shift-token RPCs, rate-limited and logged; no list, no export.
-- Card QR: opaque random token (no phone / id / personal data), set by the SERVER on every client insert, revocable.
-- Points: a sale for a customer whose phone is not yet proven is HELD (f360.loyalty_holds) and released through the
-- existing public.loyalty_apply (same rules, same idempotency key) when she verifies. C1 builds the mechanism;
-- wiring it into the store sale is C2.
-- Rollback: supabase/rollbacks/20261010000100_f360_crm_c1_customer_profile.down.sql

-- ══ 1 · Phone normalization (E.164) ══════════════════════════════════════════
-- Same result as the app login (`+52` + 10 typed digits) for every valid Mexican number. NULL = not a usable phone.
CREATE FUNCTION f360.normalize_phone(p_raw text, p_default_country text DEFAULT 'MX') RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE SET search_path = pg_catalog AS $$
DECLARE raw text := btrim(coalesce(p_raw, '')); d text; intl boolean; cc text;
BEGIN
  IF raw = '' THEN RETURN NULL; END IF;
  intl := left(raw, 1) = '+';
  d := regexp_replace(raw, '\D', '', 'g');
  IF left(raw, 2) = '00' THEN d := substr(d, 3); intl := true; END IF;
  IF d = '' THEN RETURN NULL; END IF;
  IF intl THEN
    IF d ~ '^521\d{10}$' THEN RETURN '+52' || substr(d, 4); END IF;    -- old Mexican mobile prefix
    IF d ~ '^52' THEN RETURN CASE WHEN d ~ '^52\d{10}$' THEN '+' || d END; END IF;
    IF d ~ '^57' THEN RETURN CASE WHEN d ~ '^57\d{10}$' THEN '+' || d END; END IF;
    IF d ~ '^1'  THEN RETURN CASE WHEN d ~ '^1\d{10}$'  THEN '+' || d END; END IF;
    RETURN CASE WHEN length(d) BETWEEN 8 AND 15 AND left(d, 1) <> '0' THEN '+' || d END;
  END IF;
  -- national input
  IF d ~ '^0(44|45)\d{10}$' THEN d := substr(d, 4); END IF;              -- old Mexican 044/045 mobile prefix
  IF d ~ '^521\d{10}$' THEN RETURN '+52' || substr(d, 4); END IF;
  IF d ~ '^52\d{10}$' AND upper(p_default_country) = 'MX' THEN RETURN '+' || d; END IF;
  IF d ~ '^57\d{10}$' AND upper(p_default_country) = 'CO' THEN RETURN '+' || d; END IF;
  IF length(d) = 10 THEN
    cc := CASE upper(coalesce(p_default_country, 'MX')) WHEN 'MX' THEN '52' WHEN 'CO' THEN '57' WHEN 'US' THEN '1' END;
    RETURN CASE WHEN cc IS NOT NULL THEN '+' || cc || d END;
  END IF;
  RETURN NULL;
END $$;
COMMENT ON FUNCTION f360.normalize_phone(text, text) IS 'CRM C1: canonical E.164 for search/create (+52 + 10 digits for MX). NULL when not a usable phone.';

-- The same person can never exist twice by writing the number differently (exact uniqueness already: customers_phone_key).
CREATE UNIQUE INDEX customers_phone_normalized_key ON public.customers (f360.normalize_phone(phone)) WHERE f360.normalize_phone(phone) IS NOT NULL;

-- ══ 2 · Customer profile columns (additive) ══════════════════════════════════
ALTER TABLE public.customers
  ADD COLUMN birthday_day smallint,
  ADD COLUMN birthday_month smallint,
  ADD COLUMN postal_code text,
  ADD COLUMN source text NOT NULL DEFAULT 'app',
  ADD COLUMN registered_by uuid,
  ADD COLUMN registered_location uuid,
  ADD CONSTRAINT customers_birthday_dm_check CHECK (
    (birthday_day IS NULL AND birthday_month IS NULL) OR
    (birthday_month BETWEEN 1 AND 12 AND birthday_day BETWEEN 1 AND
       CASE WHEN birthday_month = 2 THEN 29 WHEN birthday_month IN (4, 6, 9, 11) THEN 30 ELSE 31 END)),
  ADD CONSTRAINT customers_postal_code_check CHECK (postal_code IS NULL OR postal_code ~ '^[0-9A-Za-z -]{3,10}$'),
  ADD CONSTRAINT customers_source_check CHECK (source IN ('app', 'store', 'import', 'woo', 'admin'));
COMMENT ON COLUMN public.customers.birthday_day IS 'CRM C1: birthday day (no year, Mario). Filled from `birthday` when the app sends a full date.';
COMMENT ON COLUMN public.customers.source IS 'CRM C1: where the customer was created: app | store | import | woo | admin.';

CREATE FUNCTION f360.customers_birthday_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.birthday IS NOT NULL THEN
    NEW.birthday_day := extract(day FROM NEW.birthday)::smallint;
    NEW.birthday_month := extract(month FROM NEW.birthday)::smallint;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER customers_birthday_sync BEFORE INSERT OR UPDATE OF birthday ON public.customers
  FOR EACH ROW EXECUTE FUNCTION f360.customers_birthday_sync();
UPDATE public.customers SET birthday = birthday WHERE birthday IS NOT NULL;       -- backfill day/month

-- ══ 3 · Who may see full personal data (independent of owner/operator role) ══
CREATE TABLE f360.customer_pii_viewers (
  auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by   text NOT NULL,
  granted_at   timestamptz NOT NULL DEFAULT now(),
  note         text
);
ALTER TABLE f360.customer_pii_viewers ENABLE ROW LEVEL SECURITY;
-- Mario 2026-10-05: Carolina and Mario. Adrián (owner, technical) is NOT a viewer. Changes only by migration/service.
INSERT INTO f360.customer_pii_viewers (auth_user_id, granted_by, note)
  SELECT auth_user_id, 'migration 20261010000100', 'Decisión Mario 2026-10-05' FROM f360.user_roles WHERE display_name IN ('Carolina', 'Mario');

CREATE FUNCTION f360.require_pii_viewer() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Solo las personas autorizadas pueden ver los datos de las clientas.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN auth.uid();
END $$;

-- ══ 4 · Identity verification (layer 1) ══════════════════════════════════════
CREATE TABLE f360.customer_verifications (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  method      text NOT NULL CHECK (method IN ('app_whatsapp_otp', 'whatsapp_link', 'existing_app_account')),
  phone       text NOT NULL,                       -- the normalized phone that was proven
  at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id, method, phone)
);
ALTER TABLE f360.customer_verifications ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER customer_verifications_append_only BEFORE UPDATE OR DELETE ON f360.customer_verifications
  FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION f360.reject_audit_change();
-- Existing app accounts proved their phone with the WhatsApp OTP when they signed up.
INSERT INTO f360.customer_verifications (customer_id, method, phone, at)
  SELECT id, 'existing_app_account', coalesce(f360.normalize_phone(phone), phone), coalesce(created_at, now())
  FROM public.customers WHERE auth_user_id IS NOT NULL;

CREATE FUNCTION f360.customer_identity_verified(p_customer uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM f360.customer_verifications v JOIN public.customers c ON c.id = v.customer_id
                 WHERE v.customer_id = p_customer AND v.phone = coalesce(f360.normalize_phone(c.phone), c.phone))
$$;

-- ══ 5 · Consent architecture (layers 2 and 3) ════════════════════════════════
CREATE TABLE f360.consent_purposes (
  key   text PRIMARY KEY,
  kind  text NOT NULL CHECK (kind IN ('privacy', 'marketing')),
  label text NOT NULL
);
INSERT INTO f360.consent_purposes VALUES
  ('privacy_notice', 'privacy', 'Aviso de privacidad / uso de datos'),
  ('marketing_whatsapp', 'marketing', 'Novedades y promociones por WhatsApp'),
  ('marketing_email', 'marketing', 'Novedades y promociones por correo');
ALTER TABLE f360.consent_purposes ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360.consent_notice_versions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purpose_key  text NOT NULL REFERENCES f360.consent_purposes(key),
  version      text NOT NULL,
  status       text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'retired')),
  text_ref     text,                               -- URL / document of the reviewed legal text (C3)
  effective_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (purpose_key, version)
);
CREATE UNIQUE INDEX consent_notice_one_active ON f360.consent_notice_versions (purpose_key) WHERE status = 'active';
ALTER TABLE f360.consent_notice_versions ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360.customer_consent_events (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  customer_id       uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  purpose_key       text NOT NULL REFERENCES f360.consent_purposes(key),
  status            text NOT NULL CHECK (status IN ('requested', 'granted', 'denied', 'withdrawn')),
  notice_version_id uuid REFERENCES f360.consent_notice_versions(id),
  source            text NOT NULL CHECK (source IN ('store_signup', 'whatsapp_link', 'app', 'web', 'import', 'admin')),
  actor             jsonb NOT NULL DEFAULT '{}',
  evidence          jsonb NOT NULL DEFAULT '{}',
  at                timestamptz NOT NULL DEFAULT now(),
  -- a decision (granted/denied/withdrawn) always names the exact notice version it refers to
  CONSTRAINT consent_decision_has_version CHECK (status = 'requested' OR notice_version_id IS NOT NULL)
);
CREATE INDEX customer_consent_events_idx ON f360.customer_consent_events (customer_id, purpose_key, id DESC);
ALTER TABLE f360.customer_consent_events ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER customer_consent_events_append_only BEFORE UPDATE OR DELETE ON f360.customer_consent_events
  FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION f360.reject_audit_change();

-- Current state per customer and purpose = latest event ('none' when there is none).
CREATE VIEW f360.customer_consent_state AS
  SELECT c.id AS customer_id, p.key AS purpose_key, p.kind,
         coalesce(e.status, 'none') AS status, e.notice_version_id, e.source, e.at
  FROM public.customers c CROSS JOIN f360.consent_purposes p
  LEFT JOIN LATERAL (SELECT * FROM f360.customer_consent_events x WHERE x.customer_id = c.id AND x.purpose_key = p.key ORDER BY x.id DESC LIMIT 1) e ON true;

CREATE FUNCTION f360.record_consent(p_customer uuid, p_purpose text, p_status text, p_notice_version uuid, p_source text,
  p_actor jsonb DEFAULT '{}', p_evidence jsonb DEFAULT '{}') RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v f360.consent_notice_versions; v_id bigint;
BEGIN
  IF p_notice_version IS NOT NULL THEN
    SELECT * INTO v FROM f360.consent_notice_versions n WHERE n.id = p_notice_version;
    IF v.id IS NULL OR v.purpose_key <> p_purpose THEN RAISE EXCEPTION 'record_consent: la versión del aviso no corresponde al propósito.'; END IF;
  END IF;
  INSERT INTO f360.customer_consent_events (customer_id, purpose_key, status, notice_version_id, source, actor, evidence)
    VALUES (p_customer, p_purpose, p_status, p_notice_version, p_source, coalesce(p_actor, '{}'), coalesce(p_evidence, '{}'))
    RETURNING customer_consent_events.id INTO v_id;
  RETURN v_id;
END $$;

-- ══ 6 · Loyalty card token (opaque, server-made, revocable) ══════════════════
CREATE FUNCTION f360.new_card_token() RETURNS text LANGUAGE sql VOLATILE AS
$$ SELECT 'FX1-' || upper(encode(extensions.gen_random_bytes(12), 'hex')) $$;

-- A client (app) can no longer choose its QR, points, pairs or tier when creating its card. Server inserts keep theirs.
-- auth.role() = the caller's JWT role (current_user inside SECURITY DEFINER is the owner, so it can't be used).
CREATE FUNCTION f360.loyalty_cards_server_token() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE client boolean := coalesce(auth.role(), '') IN ('authenticated', 'anon');
BEGIN
  IF client OR coalesce(btrim(NEW.qr_code), '') = '' THEN
    NEW.qr_code := f360.new_card_token();
  END IF;
  IF client THEN
    NEW.total_points := 0; NEW.pairs_count := 0; NEW.tier := 'bronze';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER loyalty_cards_server_token BEFORE INSERT ON public.loyalty_cards
  FOR EACH ROW EXECUTE FUNCTION f360.loyalty_cards_server_token();

CREATE TABLE f360.card_token_events (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  card_id         uuid NOT NULL,
  old_token_hash  text NOT NULL,                   -- sha256 only; the revoked token is never stored
  reason          text NOT NULL,
  by_auth_user_id uuid,
  at              timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360.card_token_events ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER card_token_events_append_only BEFORE UPDATE OR DELETE ON f360.card_token_events
  FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360.rotate_card_token(p_card uuid, p_reason text, p_by uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE old text;
BEGIN
  SELECT qr_code INTO old FROM public.loyalty_cards WHERE id = p_card FOR UPDATE;
  IF old IS NULL THEN RAISE EXCEPTION 'Tarjeta no encontrada.'; END IF;
  UPDATE public.loyalty_cards SET qr_code = f360.new_card_token(), updated_at = now() WHERE id = p_card;
  INSERT INTO f360.card_token_events (card_id, old_token_hash, reason, by_auth_user_id) VALUES (p_card, f360.token_hash(old), p_reason, p_by);
END $$;

-- Cards whose QR still carries phone digits (pre-C1 format FX-<last 8 digits>-…). Rotation is an operational step.
CREATE VIEW f360.cards_with_legacy_token AS
  SELECT id AS card_id, customer_id FROM public.loyalty_cards WHERE qr_code !~ '^FX1-[0-9A-F]{24}$';

-- ══ 7 · Loyalty holds (points states) ════════════════════════════════════════
-- held → released (credited via loyalty_apply) | cancelled. Never credited twice: same idempotency key as the sale.
CREATE TABLE f360.loyalty_holds (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     uuid NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
  card_id         uuid NOT NULL REFERENCES public.loyalty_cards(id) ON DELETE CASCADE,
  channel         text NOT NULL,
  ref_type        text NOT NULL,
  ref_id          text NOT NULL,
  idempotency_key text NOT NULL UNIQUE,
  lines           jsonb NOT NULL,
  amount          numeric NOT NULL,
  actor           jsonb NOT NULL DEFAULT '{}',
  reason          text NOT NULL DEFAULT 'identity_unverified',
  status          text NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'released', 'cancelled')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  result          jsonb
);
CREATE INDEX loyalty_holds_customer_idx ON f360.loyalty_holds (customer_id) WHERE status = 'held';
ALTER TABLE f360.loyalty_holds ENABLE ROW LEVEL SECURITY;

-- What every sale path will call (C2): credit now if her phone is proven, otherwise hold.
CREATE FUNCTION f360.loyalty_credit_or_hold(p_card uuid, p_lines jsonb, p_amount numeric, p_channel text, p_ref_type text,
  p_ref_id text, p_idempotency_key text, p_actor jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE card public.loyalty_cards; h f360.loyalty_holds; r jsonb;
BEGIN
  SELECT * INTO card FROM public.loyalty_cards WHERE id = p_card;
  IF card.id IS NULL THEN RAISE EXCEPTION 'Tarjeta no encontrada.'; END IF;
  IF f360.customer_identity_verified(card.customer_id) THEN
    RETURN public.loyalty_apply(p_card, p_lines, p_amount, p_channel, p_ref_type, p_ref_id, p_idempotency_key, p_actor)
           || jsonb_build_object('state', 'credited');
  END IF;
  INSERT INTO f360.loyalty_holds (customer_id, card_id, channel, ref_type, ref_id, idempotency_key, lines, amount, actor)
    VALUES (card.customer_id, card.id, p_channel, p_ref_type, p_ref_id, p_idempotency_key, p_lines, p_amount, coalesce(p_actor, '{}'))
    ON CONFLICT (idempotency_key) DO NOTHING;
  SELECT * INTO h FROM f360.loyalty_holds WHERE idempotency_key = p_idempotency_key;
  RETURN jsonb_build_object('state', h.status, 'applied', false, 'held', h.status = 'held', 'hold_id', h.id,
    'points_pending', public.loyalty_pairs_for_lines(h.lines) * public.loyalty_points_per_pair());
END $$;

CREATE FUNCTION f360.release_loyalty_holds(p_customer uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE h f360.loyalty_holds; r jsonb; n int := 0;
BEGIN
  IF NOT f360.customer_identity_verified(p_customer) THEN RETURN 0; END IF;
  FOR h IN SELECT * FROM f360.loyalty_holds WHERE customer_id = p_customer AND status = 'held' ORDER BY created_at FOR UPDATE LOOP
    r := public.loyalty_apply(h.card_id, h.lines, h.amount, h.channel, h.ref_type, h.ref_id, h.idempotency_key,
                              h.actor || jsonb_build_object('released_hold', h.id));
    UPDATE f360.loyalty_holds SET status = 'released', resolved_at = now(), result = r WHERE id = h.id;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

-- When the app login links her account (whatsapp-otp sets auth_user_id after the OTP) her phone is proven:
-- record the verification and release held points. Works for app sign-up and for store-created customers.
CREATE FUNCTION f360.customers_on_verified() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.auth_user_id IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.auth_user_id IS DISTINCT FROM NEW.auth_user_id) THEN
    INSERT INTO f360.customer_verifications (customer_id, method, phone)
      VALUES (NEW.id, 'app_whatsapp_otp', coalesce(f360.normalize_phone(NEW.phone), NEW.phone)) ON CONFLICT DO NOTHING;
    PERFORM f360.release_loyalty_holds(NEW.id);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER customers_on_verified AFTER INSERT OR UPDATE OF auth_user_id ON public.customers
  FOR EACH ROW EXECUTE FUNCTION f360.customers_on_verified();

-- ══ 8 · Access log + rate limit ══════════════════════════════════════════════
CREATE TABLE f360.customer_access_log (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id  uuid,
  session_id    uuid,
  location_id   uuid,
  action        text NOT NULL CHECK (action IN ('find_phone', 'find_card', 'register', 'view_card', 'admin_list', 'admin_view', 'admin_rotate_card')),
  customer_id   uuid,                              -- never the phone, email or name
  result        text NOT NULL CHECK (result IN ('found', 'not_found', 'created', 'existing', 'invalid', 'rate_limited', 'ok')),
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX customer_access_log_session_idx ON f360.customer_access_log (session_id, at);
CREATE INDEX customer_access_log_user_idx ON f360.customer_access_log (auth_user_id, at DESC);
ALTER TABLE f360.customer_access_log ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER customer_access_log_append_only BEFORE UPDATE OR DELETE ON f360.customer_access_log
  FOR EACH ROW WHEN (pg_trigger_depth() = 0) EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360.crm_params() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('lookups_per_shift', 60)          -- Mario 2026-10-05: 60 searches per shift
$$;

-- ══ 9 · Masked card (the only customer shape a seller ever receives) ═════════
CREATE FUNCTION f360.customer_purchases(p_customer uuid, p_limit int DEFAULT 10) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('at', u.at, 'channel', u.channel, 'product', u.product, 'color', u.color, 'size', u.size,
                                               'quantity', u.quantity) ORDER BY u.at DESC), '[]')
  FROM (SELECT * FROM (
          SELECT o.created_at AS at, 'tienda'::text AS channel, i.product_name AS product, i.color, i.size, i.quantity
          FROM public.offline_sales o JOIN public.offline_sale_items i ON i.sale_id = o.id WHERE o.customer_id = p_customer
          UNION ALL
          SELECT t.created_at, 'en línea', pi.product_name, pi.color, pi.size, pi.quantity
          FROM public.purchase_items pi JOIN public.transactions t ON t.id = pi.transaction_id
          JOIN public.loyalty_cards lc ON lc.id = t.loyalty_card_id
          WHERE lc.customer_id = p_customer AND t.channel <> 'store') a
        ORDER BY at DESC LIMIT greatest(p_limit, 1)) u
$$;

CREATE FUNCTION f360.customer_masked_card(p_customer uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'customer_ref', c.id,
    'first_name', initcap(split_part(btrim(c.name), ' ', 1)),
    'phone_last4', right(regexp_replace(c.phone, '\D', '', 'g'), 4),
    'shoe_size', c.shoe_size,
    'sizes_bought', coalesce((SELECT jsonb_agg(DISTINCT z.s) FROM (
        SELECT nullif(btrim(i.size), '') s FROM public.offline_sales o JOIN public.offline_sale_items i ON i.sale_id = o.id WHERE o.customer_id = c.id
        UNION SELECT nullif(btrim(pi.size), '') FROM public.purchase_items pi JOIN public.transactions t ON t.id = pi.transaction_id
          JOIN public.loyalty_cards x ON x.id = t.loyalty_card_id WHERE x.customer_id = c.id) z WHERE z.s IS NOT NULL), '[]'),
    'points', coalesce(lc.total_points, 0), 'tier', coalesce(lc.tier, 'bronze'), 'has_card', lc.id IS NOT NULL,
    'points_pending', coalesce((SELECT sum(public.loyalty_pairs_for_lines(h.lines)) * public.loyalty_points_per_pair()
                                FROM f360.loyalty_holds h WHERE h.customer_id = c.id AND h.status = 'held'), 0),
    'identity_verified', f360.customer_identity_verified(c.id),
    'privacy_consent', (SELECT status FROM f360.customer_consent_state WHERE customer_id = c.id AND purpose_key = 'privacy_notice'),
    'recent_purchases', f360.customer_purchases(c.id, 10))
  FROM public.customers c
  LEFT JOIN LATERAL (SELECT * FROM public.loyalty_cards l WHERE l.customer_id = c.id ORDER BY l.created_at LIMIT 1) lc ON true
  WHERE c.id = p_customer
$$;

-- ══ 10 · Seller RPCs (shift token; masked; rate-limited; logged) ═════════════
CREATE FUNCTION f360.crm_log(s f360.seller_sessions, p_action text, p_customer uuid, p_result text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO f360.customer_access_log (auth_user_id, session_id, location_id, action, customer_id, result)
  VALUES (s.auth_user_id, s.id, s.location_id, p_action, p_customer, p_result)
$$;

CREATE FUNCTION f360.crm_rate_limited(s f360.seller_sessions) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT count(*) >= (f360.crm_params()->>'lookups_per_shift')::int FROM f360.customer_access_log
  WHERE session_id = s.id AND action IN ('find_phone', 'find_card', 'register') AND result <> 'rate_limited'
$$;

CREATE FUNCTION f360.crm_refusal(p_code text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('ok', false, 'code', p_code, 'error', CASE p_code
    WHEN 'rate_limited' THEN 'Llegaste al límite de búsquedas de clientas de este turno. Pide ayuda a Carolina.'
    WHEN 'invalid_phone' THEN 'Revisa el WhatsApp: 10 dígitos (o con +52 / +57).'
    WHEN 'invalid_card' THEN 'No reconocemos esa tarjeta. Pide a la clienta que abra su tarjeta en la app.'
    WHEN 'invalid_name' THEN 'Escribe el nombre de la clienta.'
    WHEN 'invalid_email' THEN 'Revisa el correo.'
    WHEN 'invalid_postal_code' THEN 'Revisa el código postal.'
    WHEN 'invalid_birthday' THEN 'Revisa el cumpleaños (día y mes).'
    WHEN 'invalid_size' THEN 'Revisa la talla.'
    WHEN 'not_found' THEN 'No encontramos a esa clienta.'
    ELSE 'No se pudo completar.' END)
$$;

CREATE FUNCTION public.f360_shift_customer_find(p_token text, p_phone text, p_country text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); ph text; cid uuid;
BEGIN
  IF f360.crm_rate_limited(s) THEN PERFORM f360.crm_log(s, 'find_phone', NULL, 'rate_limited'); RETURN f360.crm_refusal('rate_limited'); END IF;
  ph := f360.normalize_phone(p_phone, coalesce(p_country, 'MX'));
  IF ph IS NULL THEN PERFORM f360.crm_log(s, 'find_phone', NULL, 'invalid'); RETURN f360.crm_refusal('invalid_phone'); END IF;
  SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
  PERFORM f360.crm_log(s, 'find_phone', cid, CASE WHEN cid IS NULL THEN 'not_found' ELSE 'found' END);
  RETURN jsonb_build_object('ok', true, 'found', cid IS NOT NULL, 'customer', CASE WHEN cid IS NOT NULL THEN f360.customer_masked_card(cid) END);
END $$;

CREATE FUNCTION public.f360_shift_customer_by_card(p_token text, p_card_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token); cid uuid;
BEGIN
  IF f360.crm_rate_limited(s) THEN PERFORM f360.crm_log(s, 'find_card', NULL, 'rate_limited'); RETURN f360.crm_refusal('rate_limited'); END IF;
  SELECT customer_id INTO cid FROM public.loyalty_cards WHERE qr_code = btrim(coalesce(p_card_token, '')) AND btrim(coalesce(p_card_token, '')) <> '';
  PERFORM f360.crm_log(s, 'find_card', cid, CASE WHEN cid IS NULL THEN 'not_found' ELSE 'found' END);
  IF cid IS NULL THEN RETURN f360.crm_refusal('invalid_card'); END IF;
  RETURN jsonb_build_object('ok', true, 'found', true, 'customer', f360.customer_masked_card(cid));
END $$;

CREATE FUNCTION public.f360_shift_customer_card(p_token text, p_customer_ref uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions := f360.require_seller_session(p_token);
BEGIN
  IF p_customer_ref IS NULL OR NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer_ref) THEN
    PERFORM f360.crm_log(s, 'view_card', NULL, 'not_found'); RETURN f360.crm_refusal('not_found');
  END IF;
  PERFORM f360.crm_log(s, 'view_card', p_customer_ref, 'ok');
  RETURN jsonb_build_object('ok', true, 'customer', f360.customer_masked_card(p_customer_ref));
END $$;

-- Sign-up at the store. Required: WhatsApp, name, email. Optional: postal code, birthday (day+month), size.
-- An existing phone is NEVER overwritten: the seller gets that customer's masked card.
CREATE FUNCTION public.f360_shift_customer_register(p_token text, p_phone text, p_name text, p_email text,
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
  EXCEPTION WHEN unique_violation THEN                       -- a concurrent sign-up of the same number won
    SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
    PERFORM f360.crm_log(s, 'register', cid, 'existing');
    RETURN jsonb_build_object('ok', true, 'created', false, 'customer', f360.customer_masked_card(cid));
  END;
  INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cid, '', 0, 0, 'bronze');  -- token by trigger
  PERFORM f360.record_consent(cid, 'privacy_notice', 'requested',
    (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'privacy_notice' AND status = 'active'), 'store_signup',
    jsonb_build_object('seller', s.auth_user_id, 'location', s.location_id, 'session', s.id));
  PERFORM f360.crm_log(s, 'register', cid, 'created');
  RETURN jsonb_build_object('ok', true, 'created', true, 'customer', f360.customer_masked_card(cid));
END $$;

-- ══ 11 · Admin RPCs (only customer_pii_viewers; full data; logged) ═══════════
CREATE FUNCTION f360.customer_full(p_customer uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT f360.customer_masked_card(c.id) || jsonb_build_object(
    'name', c.name, 'phone', c.phone, 'email', c.email, 'postal_code', c.postal_code, 'country', c.country,
    'birthday_day', c.birthday_day, 'birthday_month', c.birthday_month, 'source', c.source, 'created_at', c.created_at,
    'registered_location', (SELECT name FROM f360.locations WHERE id = c.registered_location),
    'consents', (SELECT jsonb_object_agg(purpose_key, status) FROM f360.customer_consent_state WHERE customer_id = c.id))
  FROM public.customers c WHERE c.id = p_customer
$$;

CREATE FUNCTION public.f360_admin_customers(p_search text DEFAULT NULL, p_limit int DEFAULT 50, p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); q text := nullif(btrim(coalesce(p_search, '')), ''); ph text := f360.normalize_phone(p_search); r jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(f360.customer_full(x.id) ORDER BY x.created_at DESC), '[]') INTO r FROM (
    SELECT c.id, c.created_at FROM public.customers c
    WHERE c.role = 'customer' AND (q IS NULL OR c.name ILIKE '%' || q || '%' OR c.email ILIKE '%' || q || '%'
           OR (ph IS NOT NULL AND f360.normalize_phone(c.phone) = ph) OR right(regexp_replace(c.phone, '\D', '', 'g'), length(regexp_replace(q, '\D', '', 'g'))) = regexp_replace(q, '\D', '', 'g') AND length(regexp_replace(q, '\D', '', 'g')) >= 4)
    ORDER BY c.created_at DESC LIMIT least(greatest(coalesce(p_limit, 50), 1), 200) OFFSET greatest(coalesce(p_offset, 0), 0)) x;
  INSERT INTO f360.customer_access_log (auth_user_id, action, result) VALUES (uid, 'admin_list', 'ok');
  RETURN r;
END $$;

CREATE FUNCTION public.f360_admin_customer(p_customer uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer) THEN RETURN f360.crm_refusal('not_found'); END IF;
  INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'admin_view', p_customer, 'ok');
  RETURN jsonb_build_object('ok', true, 'customer', f360.customer_full(p_customer) || jsonb_build_object(
    'purchases', f360.customer_purchases(p_customer, 100),
    'consent_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('purpose', e.purpose_key, 'status', e.status, 'source', e.source,
                          'version', v.version, 'at', e.at) ORDER BY e.id DESC), '[]')
                        FROM f360.customer_consent_events e LEFT JOIN f360.consent_notice_versions v ON v.id = e.notice_version_id
                        WHERE e.customer_id = p_customer)));
END $$;

CREATE FUNCTION public.f360_admin_rotate_card_token(p_customer uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); card uuid;
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT id INTO card FROM public.loyalty_cards WHERE customer_id = p_customer ORDER BY created_at LIMIT 1;
  IF card IS NULL THEN RETURN f360.crm_refusal('not_found'); END IF;
  PERFORM f360.rotate_card_token(card, btrim(p_reason), uid);
  INSERT INTO f360.customer_access_log (auth_user_id, action, customer_id, result) VALUES (uid, 'admin_rotate_card', p_customer, 'ok');
  RETURN jsonb_build_object('ok', true);
END $$;

-- ══ 12 · Grants ══════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION f360.normalize_phone(text, text), f360.customers_birthday_sync(), f360.require_pii_viewer(),
  f360.customer_identity_verified(uuid), f360.record_consent(uuid, text, text, uuid, text, jsonb, jsonb), f360.new_card_token(),
  f360.loyalty_cards_server_token(), f360.rotate_card_token(uuid, text, uuid),
  f360.loyalty_credit_or_hold(uuid, jsonb, numeric, text, text, text, text, jsonb), f360.release_loyalty_holds(uuid),
  f360.customers_on_verified(), f360.crm_params(), f360.customer_purchases(uuid, int), f360.customer_masked_card(uuid),
  f360.crm_log(f360.seller_sessions, text, uuid, text), f360.crm_rate_limited(f360.seller_sessions), f360.crm_refusal(text),
  f360.customer_full(uuid) FROM PUBLIC, anon, authenticated;
-- normalize_phone is pure and is evaluated by the unique index on every app insert into customers.
GRANT EXECUTE ON FUNCTION f360.normalize_phone(text, text) TO PUBLIC;
REVOKE ALL ON f360.customer_pii_viewers, f360.customer_verifications, f360.consent_purposes, f360.consent_notice_versions,
  f360.customer_consent_events, f360.customer_consent_state, f360.card_token_events, f360.cards_with_legacy_token,
  f360.loyalty_holds, f360.customer_access_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.customer_verifications, f360.consent_purposes, f360.consent_notice_versions, f360.customer_consent_events,
  f360.customer_consent_state, f360.loyalty_holds, f360.cards_with_legacy_token TO service_role;

REVOKE ALL ON FUNCTION public.f360_shift_customer_find(text, text, text), public.f360_shift_customer_by_card(text, text),
  public.f360_shift_customer_card(text, uuid), public.f360_shift_customer_register(text, text, text, text, text, int, int, text, text),
  public.f360_admin_customers(text, int, int), public.f360_admin_customer(uuid), public.f360_admin_rotate_card_token(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_shift_customer_find(text, text, text), public.f360_shift_customer_by_card(text, text),
  public.f360_shift_customer_card(text, uuid), public.f360_shift_customer_register(text, text, text, text, text, int, int, text, text),
  public.f360_admin_customers(text, int, int), public.f360_admin_customer(uuid), public.f360_admin_rotate_card_token(uuid, text)
  TO authenticated;
