-- Fuxia 360 · CRO-5 (Avísame cuando llegue → demanda sin inventario) + CRO-6 (promesa de entrega única + confianza). STAGING.
-- Authorized by Mario 2026-10-05 (staging only; no campaigns, no mass notifications, no production).
-- Sources of truth reused (no new identity / inventory):
--   * identity:   f360.channel_variant_identity (F360 + homologated legacy; Woo ids are channel ids)
--   * inventory:  f360.online_ats(variant, fulfillment)  = Bodega + stores − Gold holds (bazaars never count)
--   * MTO:        f360.products.make_to_order (all 62 models on today) → no stock + MTO = orderable, 10 business days
--   * scarcity:   f360.online_scarcity_reliable (certified inventory only)
--   * customers / consent: CRM C1 (public.customers, f360.customer_consent_events); a NEW purpose 'stock_notification'
--     of kind 'operational' — never marketing.
-- Promise text is DATA (f360.delivery_promise_rules), one row per market × case, with status known | blocked
-- (BLOCKED_BY_BUSINESS_RULE → conservative copy, no invented times). PDP, checkout, Hilo and "Pedido recibido" read the
-- same rule through public.f360_storefront_promise.
-- Rollback: supabase/rollbacks/20261010000700_f360_cro5_cro6_intent_promise.down.sql

-- ══ 1 · Operational consent purpose (C1 architecture: identity ≠ privacy ≠ marketing ≠ operational) ══
ALTER TABLE f360.consent_purposes DROP CONSTRAINT consent_purposes_kind_check;
ALTER TABLE f360.consent_purposes ADD CONSTRAINT consent_purposes_kind_check CHECK (kind IN ('privacy', 'marketing', 'operational'));
INSERT INTO f360.consent_purposes (key, kind, label) VALUES ('stock_notification', 'operational', 'Aviso cuando llegue una talla');
-- The exact sentence the customer accepts (shown next to the checkbox). Legal review pending (C3), recorded as v1.
INSERT INTO f360.consent_notice_versions (purpose_key, version, status, text_ref, effective_at)
  VALUES ('stock_notification', '2026-10-05-v1', 'active',
          'Usaremos tu WhatsApp solo para avisarte cuando esta talla vuelva a estar disponible. No es una suscripción a promociones.', now());

-- ══ 2 · Delivery promise rules (data, not hardcoded copy) ══
CREATE TABLE f360.delivery_promise_rules (
  market        text NOT NULL CHECK (market IN ('MX', 'CO', 'OTHER')),
  promise_case  text NOT NULL CHECK (promise_case IN ('in_stock', 'made_to_order', 'unavailable')),
  status        text NOT NULL CHECK (status IN ('known', 'blocked')),       -- blocked = BLOCKED_BY_BUSINESS_RULE
  headline      text NOT NULL,
  detail        text,
  business_days int,
  decided_by    text NOT NULL,
  decided_at    date NOT NULL,
  PRIMARY KEY (market, promise_case)
);
ALTER TABLE f360.delivery_promise_rules ENABLE ROW LEVEL SECURITY;
INSERT INTO f360.delivery_promise_rules VALUES
  ('MX', 'in_stock', 'known', 'Entrega Inmediata en Zona Metropolitana', 'Fuera de la Zona Metropolitana te confirmamos el tiempo al hacer tu pedido.', NULL, 'Mario', '2026-10-05'),
  ('MX', 'made_to_order', 'known', 'Producción: 10 días hábiles', 'Lo hacemos a la medida para ti.', 10, 'Mario', '2026-10-05'),
  ('MX', 'unavailable', 'known', 'Agotada', 'Déjanos tu WhatsApp y te avisamos cuando llegue.', NULL, 'Mario', '2026-10-05'),
  -- Colombia has its own rule (Mario): not decided yet → conservative copy, no times.
  ('CO', 'in_stock', 'blocked', 'Te confirmamos el tiempo de entrega al hacer tu pedido', NULL, NULL, 'pendiente (Mario)', '2026-10-05'),
  ('CO', 'made_to_order', 'blocked', 'Lo hacemos a la medida para ti', 'Te confirmamos el tiempo de entrega al hacer tu pedido.', NULL, 'pendiente (Mario)', '2026-10-05'),
  ('CO', 'unavailable', 'known', 'Agotada', 'Déjanos tu WhatsApp y te avisamos cuando llegue.', NULL, 'Mario', '2026-10-05'),
  ('OTHER', 'in_stock', 'blocked', 'Te confirmamos el tiempo de entrega al hacer tu pedido', NULL, NULL, 'pendiente (Mario)', '2026-10-05'),
  ('OTHER', 'made_to_order', 'blocked', 'Lo hacemos a la medida para ti', 'Te confirmamos el tiempo de entrega al hacer tu pedido.', NULL, 'pendiente (Mario)', '2026-10-05'),
  ('OTHER', 'unavailable', 'known', 'Agotada', 'Déjanos tu WhatsApp y te avisamos cuando llegue.', NULL, 'Mario', '2026-10-05');

CREATE FUNCTION f360.market_key(p_market text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE upper(coalesce(btrim(p_market), '')) WHEN 'MX' THEN 'MX' WHEN 'CO' THEN 'CO' ELSE 'OTHER' END $$;

-- THE rule: variant × inventory × MTO × market → one promise. Unresolved variant ⇒ 'unknown' (channel shows nothing new).
CREATE FUNCTION f360.delivery_promise(p_variant uuid, p_fulfillment uuid, p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ats int; mto boolean; c text; rule f360.delivery_promise_rules; last_pair boolean := false;
BEGIN
  IF p_variant IS NULL THEN RETURN jsonb_build_object('case', 'unknown', 'status', 'blocked'); END IF;
  ats := f360.online_ats(p_variant, p_fulfillment);
  SELECT p.make_to_order INTO mto FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.id = p_variant;
  c := CASE WHEN ats > 0 THEN 'in_stock' WHEN coalesce(mto, false) THEN 'made_to_order' ELSE 'unavailable' END;
  SELECT * INTO rule FROM f360.delivery_promise_rules WHERE market = f360.market_key(p_market) AND promise_case = c;
  IF c = 'in_stock' AND ats = 1 THEN last_pair := f360.online_scarcity_reliable(p_variant, p_fulfillment); END IF;  -- certified only
  RETURN jsonb_strip_nulls(jsonb_build_object('case', c, 'status', rule.status, 'headline', rule.headline, 'detail', rule.detail,
    'business_days', rule.business_days, 'last_pair', last_pair, 'can_notify', c = 'unavailable'));
END $$;

-- Trust claims next to ATC: only verifiable ones. MSI and free shipping have no F360 source → not emitted (blocked).
CREATE FUNCTION f360.trust_claims(p_product uuid, p_market text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_array(
    CASE WHEN p.sale_price IS NOT NULL AND p.sale_price > 0 AND p.sale_price < p.regular_price
         THEN jsonb_build_object('key', 'cambios', 'text', 'Precio con descuento: sin cambio', 'status', 'known')
         ELSE jsonb_build_object('key', 'cambios', 'text', 'Cambios en 30 días', 'status', 'known') END,
    jsonb_build_object('key', 'pago_seguro', 'text', 'Pago seguro', 'status', 'known'))
  FROM f360.products p WHERE p.id = p_product
$$;

-- ══ 3 · Stock intents ("Avísame cuando llegue") — demand signal ══
CREATE TABLE f360.stock_intents (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sales_channel_id     uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_product_id       bigint NOT NULL,                          -- channel ids (always kept)
  woo_variation_id     bigint NOT NULL,
  variant_id           uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,   -- canonical (NULL = unresolved legacy)
  product_id           uuid REFERENCES f360.products(id) ON DELETE RESTRICT,
  canonical_sku        text,
  product_key          text,                                     -- F360-{MODELO}
  color                text,
  size                 text,
  market               text NOT NULL CHECK (market IN ('MX', 'CO', 'OTHER')),
  source               text NOT NULL CHECK (source IN ('pdp', 'hilo', 'app', 'store', 'admin')),
  customer_id          uuid REFERENCES public.customers(id) ON DELETE SET NULL,   -- existing customer → related, not duplicated
  contact_phone        text,                                     -- only when no customer exists; normalized E.164
  contact_name         text,
  consent_version_id   uuid NOT NULL REFERENCES f360.consent_notice_versions(id),  -- operational consent (stock_notification)
  consent_at           timestamptz NOT NULL DEFAULT now(),
  status               text NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'notified', 'converted', 'cancelled', 'expired')),
  page_url             text,
  ip_hash              text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  resolved_at          timestamptz,
  CONSTRAINT stock_intent_contact CHECK (customer_id IS NOT NULL OR contact_phone IS NOT NULL)
);
-- one waiting intent per person per size and channel
CREATE UNIQUE INDEX stock_intents_one_waiting ON f360.stock_intents
  (sales_channel_id, woo_variation_id, coalesce(customer_id::text, contact_phone)) WHERE status = 'waiting';
CREATE INDEX stock_intents_variant_idx ON f360.stock_intents (variant_id) WHERE status = 'waiting';
ALTER TABLE f360.stock_intents ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION f360.storefront_target(p_key text) RETURNS f360.sales_targets
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key AND active;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  RETURN t;
END $$;

-- Storefront (service_role via Edge Function): promise for every variation of a Woo product + trust claims.
CREATE FUNCTION public.f360_storefront_promise(p_target_key text, p_woo_product_id bigint, p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.storefront_target(p_target_key); pid uuid;
BEGIN
  SELECT canonical_product_id INTO pid FROM f360.channel_variant_identity
    WHERE sales_channel_id = t.id AND woo_product_id = p_woo_product_id LIMIT 1;
  RETURN jsonb_build_object('market', f360.market_key(p_market), 'product_key', (SELECT 'F360-' || code FROM f360.products WHERE id = pid),
    'variations', coalesce((SELECT jsonb_object_agg(ci.woo_variation_id::text, f360.delivery_promise(ci.canonical_variant_id, t.fulfillment_location_id, p_market))
                            FROM f360.channel_variant_identity ci WHERE ci.sales_channel_id = t.id AND ci.woo_product_id = p_woo_product_id), '{}'),
    'trust', CASE WHEN pid IS NOT NULL THEN f360.trust_claims(pid, p_market) ELSE '[]'::jsonb END);
END $$;

-- Storefront (service_role): register "Avísame cuando llegue". Existing customer (same normalized phone) → related.
-- Refuses when the size is actually orderable (it is not unavailable). Rate limits: 10 per phone per day, 30 per ip per hour.
CREATE FUNCTION public.f360_stock_intent_create(p_target_key text, p_woo_product_id bigint, p_woo_variation_id bigint, p_market text,
  p_phone text, p_name text DEFAULT NULL, p_consent boolean DEFAULT false, p_source text DEFAULT 'pdp', p_ip_hash text DEFAULT NULL,
  p_page_url text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.storefront_target(p_target_key); ci record; ph text; cid uuid; ver uuid; pr jsonb; mk text := f360.market_key(p_market);
  existing f360.stock_intents; new_id uuid;
BEGIN
  IF NOT coalesce(p_consent, false) THEN RETURN jsonb_build_object('ok', false, 'code', 'consent', 'error', 'Marca la casilla para que te podamos avisar.'); END IF;
  ph := f360.normalize_phone(p_phone, CASE mk WHEN 'CO' THEN 'CO' ELSE 'MX' END);
  IF ph IS NULL THEN RETURN jsonb_build_object('ok', false, 'code', 'phone', 'error', 'Revisa tu WhatsApp (10 dígitos).'); END IF;
  IF p_source NOT IN ('pdp', 'hilo', 'app', 'store', 'admin') THEN RAISE EXCEPTION 'Origen no válido.'; END IF;
  IF (SELECT count(*) FROM f360.stock_intents WHERE coalesce(contact_phone, (SELECT phone FROM public.customers WHERE id = customer_id)) = ph
        AND created_at > now() - interval '1 day') >= 10
     OR (p_ip_hash IS NOT NULL AND (SELECT count(*) FROM f360.stock_intents WHERE ip_hash = p_ip_hash AND created_at > now() - interval '1 hour') >= 30) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'rate_limited', 'error', 'Ya recibimos varios avisos. Intenta más tarde.');
  END IF;

  SELECT * INTO ci FROM f360.channel_variant_identity WHERE sales_channel_id = t.id AND woo_variation_id = p_woo_variation_id;
  IF ci.canonical_variant_id IS NOT NULL THEN
    IF ci.woo_product_id IS NOT NULL AND ci.woo_product_id <> p_woo_product_id THEN RAISE EXCEPTION 'La talla no corresponde al producto.'; END IF;
    pr := f360.delivery_promise(ci.canonical_variant_id, t.fulfillment_location_id, mk);
    IF pr->>'case' <> 'unavailable' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'available', 'error', 'Esta talla sí se puede pedir ahora.', 'promise', pr);
    END IF;
  END IF;

  SELECT id INTO cid FROM public.customers WHERE f360.normalize_phone(phone) = ph OR phone = ph ORDER BY created_at LIMIT 1;
  SELECT id INTO ver FROM f360.consent_notice_versions WHERE purpose_key = 'stock_notification' AND status = 'active';

  SELECT * INTO existing FROM f360.stock_intents WHERE sales_channel_id = t.id AND woo_variation_id = p_woo_variation_id AND status = 'waiting'
    AND coalesce(customer_id::text, contact_phone) = coalesce(cid::text, ph);
  IF existing.id IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'already', true); END IF;

  INSERT INTO f360.stock_intents (sales_channel_id, woo_product_id, woo_variation_id, variant_id, product_id, canonical_sku, product_key, color, size,
      market, source, customer_id, contact_phone, contact_name, consent_version_id, page_url, ip_hash)
    SELECT t.id, p_woo_product_id, p_woo_variation_id, ci.canonical_variant_id, ci.canonical_product_id, ci.canonical_sku, ci.canonical_product_key,
           co.name, v.size_label, mk, p_source, cid, CASE WHEN cid IS NULL THEN ph END,
           CASE WHEN cid IS NULL THEN nullif(left(btrim(coalesce(p_name, '')), 80), '') END, ver, left(p_page_url, 300), p_ip_hash
    FROM (SELECT 1) one LEFT JOIN f360.product_variants v ON v.id = ci.canonical_variant_id LEFT JOIN f360.product_colors co ON co.id = v.color_id
    RETURNING id INTO new_id;
  IF cid IS NOT NULL THEN
    PERFORM f360.record_consent(cid, 'stock_notification', 'granted', ver, 'web',
      jsonb_build_object('intent', new_id), jsonb_build_object('woo_variation_id', p_woo_variation_id, 'market', mk));
  END IF;
  RETURN jsonb_build_object('ok', true, 'already', false);
END $$;

-- Admin (viewer+): DEMANDA SIN INVENTARIO — people waiting (Avísame) + pairs sold without stock (sobre pedido). No PII.
CREATE FUNCTION public.f360_stock_demand(p_market text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('viewer'); mk text := CASE WHEN p_market IS NULL THEN NULL ELSE f360.market_key(p_market) END;
BEGIN
  RETURN jsonb_build_object('market', mk, 'models', coalesce((SELECT jsonb_agg(m ORDER BY (m->>'waiting')::int + (m->>'mto_pairs')::int DESC) FROM (
    SELECT jsonb_build_object('product', coalesce(p.name, 'Sin homologar'), 'product_key', coalesce('F360-' || p.code, 'legacy'),
             'waiting', sum(x.waiting)::int, 'mto_pairs', sum(x.mto_pairs)::int,
             'sizes', jsonb_agg(jsonb_build_object('color', x.color, 'size', x.size, 'sku', x.sku, 'waiting', x.waiting, 'mto_pairs', x.mto_pairs,
                                                   'oldest', x.oldest) ORDER BY x.waiting + x.mto_pairs DESC)) m
    FROM (SELECT product_id, color, size, sku, sum(waiting)::int waiting, sum(mto_pairs)::int mto_pairs, min(oldest) oldest FROM (
      SELECT product_id, coalesce(color, '—') color, coalesce(size, '—') size, canonical_sku sku, count(*) waiting, 0 mto_pairs, min(created_at) oldest
      FROM f360.stock_intents WHERE status = 'waiting' AND (mk IS NULL OR market = mk) GROUP BY 1, 2, 3, 4
      UNION ALL
      SELECT v.product_id, co.name, v.size_label, v.sku, 0, sum(m.quantity), min(m.created_at)
      FROM f360.made_to_order m JOIN f360.product_variants v ON v.id = m.variant_id JOIN f360.product_colors co ON co.id = v.color_id
      LEFT JOIN f360.sales_targets st ON st.id = m.target_id
      WHERE m.status IN ('pendiente', 'en_proceso') AND (mk IS NULL OR mk = 'MX') AND (NOT coalesce(st.is_test, false) OR NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE is_production))
      GROUP BY 1, 2, 3, 4) u GROUP BY 1, 2, 3, 4) x
    LEFT JOIN f360.products p ON p.id = x.product_id
    GROUP BY p.name, p.code) mm(m)), '[]'),
    'rules', (SELECT jsonb_agg(to_jsonb(d) ORDER BY d.market, d.promise_case) FROM f360.delivery_promise_rules d));
END $$;

REVOKE ALL ON f360.delivery_promise_rules, f360.stock_intents FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.delivery_promise_rules, f360.stock_intents TO service_role;
REVOKE ALL ON FUNCTION f360.market_key(text), f360.delivery_promise(uuid, uuid, text), f360.trust_claims(uuid, text), f360.storefront_target(text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_storefront_promise(text, bigint, text),
  public.f360_stock_intent_create(text, bigint, bigint, text, text, text, boolean, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_storefront_promise(text, bigint, text),
  public.f360_stock_intent_create(text, bigint, bigint, text, text, text, boolean, text, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.f360_stock_demand(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_stock_demand(text) TO authenticated;
