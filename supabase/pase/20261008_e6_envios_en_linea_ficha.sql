-- Fuxia 360 · pase E6 — los pedidos en línea guardan a dónde se envían y llenan la ficha (same as migration 20261013000500). Apply ONLY with scripts/f360/prod_sql.sh.
-- Apply BEFORE deploying f360-woo-orders (the function calls f360_capture_order_shipping; until then it answers 'error', never blocks stock).
BEGIN;
-- Fuxia 360 · CRM C7 (Mario 2026-10-08: "para vender online siempre estará [la dirección] y esto nos servirá para más adelante
-- hacer análisis demográficos"). ADDITIVE.
-- Until now f360-woo-orders dropped every customer field before storing an order (by design). Now a PAID online order
-- (processing / completed) also keeps WHERE it ships:
--   · f360.order_shipping: one row per store order — recipient name, WhatsApp (normalized), e-mail and shipping address. This
--     is the order's delivery data (it belongs to the order); the customer's CURRENT address stays only in public.customers.
--   · if a customer with that WhatsApp (or e-mail) already exists, the order is linked to her and her ficha takes the address of
--     her NEWEST order (address_source 'woo');
--   · NO customer is created here: creating one would make the existing loyalty webhook (woocommerce-webhook) credit points and
--     send the welcome right away — a loyalty rule change that is not part of this request. When she registers later (app,
--     counter or admin), a trigger fills her ficha from her newest order and links her orders.
-- Called by f360-woo-orders AFTER the inventory and economics steps, best effort (a failure here never blocks stock).
-- Rollback: supabase/rollbacks/20261013000500_f360_order_shipping.down.sql

CREATE TABLE f360.order_shipping (
  target_id     uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_order_id  bigint NOT NULL,
  customer_id   uuid REFERENCES public.customers(id) ON DELETE SET NULL,
  status        text NOT NULL,
  name          text,
  phone         text,                       -- f360.normalize_phone, NULL when unusable
  email         text,
  street        text,
  neighborhood  text,
  city          text,
  state         text,
  postal_code   text,
  country       text,
  order_created_at timestamptz,
  captured_at   timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, woo_order_id)
);
CREATE INDEX order_shipping_phone_idx ON f360.order_shipping (phone) WHERE phone IS NOT NULL;
CREATE INDEX order_shipping_email_idx ON f360.order_shipping (lower(email)) WHERE email IS NOT NULL;
CREATE INDEX order_shipping_customer_idx ON f360.order_shipping (customer_id) WHERE customer_id IS NOT NULL;
CREATE INDEX order_shipping_geo_idx ON f360.order_shipping (country, state, city, postal_code);
ALTER TABLE f360.order_shipping ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.order_shipping FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.order_shipping TO service_role;
COMMENT ON TABLE f360.order_shipping IS 'CRM C7: where each paid online order ships (personal data: service role only; read through PII-viewer functions).';

-- Her ficha takes the address of her NEWEST captured order.
CREATE FUNCTION f360.customer_address_from_orders(p_customer uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE o f360.order_shipping;
BEGIN
  SELECT * INTO o FROM f360.order_shipping WHERE customer_id = p_customer AND coalesce(street, city, postal_code) IS NOT NULL
    ORDER BY coalesce(order_created_at, captured_at) DESC, woo_order_id DESC LIMIT 1;
  IF o.woo_order_id IS NULL THEN RETURN; END IF;
  -- a newer manual correction in the admin wins over an older order
  IF EXISTS (SELECT 1 FROM public.customers WHERE id = p_customer AND address_source = 'admin'
             AND address_updated_at > coalesce(o.order_created_at, o.captured_at)) THEN RETURN; END IF;
  PERFORM f360.customer_save_address(p_customer, o.street, o.neighborhood, o.city, o.state, o.postal_code, 'woo');
END $$;
REVOKE ALL ON FUNCTION f360.customer_address_from_orders(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_capture_order_shipping(p_target_key text, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.orders_target(p_target_key); oid bigint := (p_order->>'id')::bigint; st text := p_order->>'status';
  cl text[] := ARRAY(SELECT left(nullif(btrim(regexp_replace(coalesce(p_order->>k, ''), '\s+', ' ', 'g')), ''), n)
                     FROM unnest(ARRAY['name', 'street', 'neighborhood', 'city', 'state', 'postal_code', 'country', 'email'],
                                 ARRAY[120, 160, 120, 120, 80, 10, 2, 254]) WITH ORDINALITY u(k, n, i) ORDER BY i);
  ph text; em text; cid uuid;
BEGIN
  IF oid IS NULL OR oid <= 0 THEN RAISE EXCEPTION 'Pedido sin número.'; END IF;
  IF st NOT IN ('processing', 'completed') THEN RETURN jsonb_build_object('result', 'not_paid'); END IF;
  ph := f360.normalize_phone(p_order->>'phone', coalesce(upper(cl[7]), 'MX'));
  em := lower(cl[8]); IF em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' THEN em := NULL; END IF;
  SELECT id INTO cid FROM public.customers WHERE role = 'customer' AND ph IS NOT NULL AND f360.normalize_phone(phone) = ph ORDER BY created_at LIMIT 1;
  IF cid IS NULL AND em IS NOT NULL THEN
    SELECT id INTO cid FROM public.customers WHERE role = 'customer' AND lower(email) = em ORDER BY created_at LIMIT 1;
  END IF;
  INSERT INTO f360.order_shipping AS s (target_id, woo_order_id, customer_id, status, name, phone, email, street, neighborhood, city, state,
      postal_code, country, order_created_at)
    VALUES (t.id, oid, cid, st, cl[1], ph, em, cl[2], cl[3], cl[4], cl[5], upper(cl[6]), upper(cl[7]),
            nullif(p_order->>'created_at', '')::timestamptz)
  ON CONFLICT (target_id, woo_order_id) DO UPDATE SET customer_id = coalesce(s.customer_id, EXCLUDED.customer_id), status = EXCLUDED.status,
      name = EXCLUDED.name, phone = EXCLUDED.phone, email = EXCLUDED.email, street = EXCLUDED.street, neighborhood = EXCLUDED.neighborhood,
      city = EXCLUDED.city, state = EXCLUDED.state, postal_code = EXCLUDED.postal_code, country = EXCLUDED.country,
      order_created_at = coalesce(EXCLUDED.order_created_at, s.order_created_at), updated_at = now();
  IF cid IS NOT NULL THEN PERFORM f360.customer_address_from_orders(cid); END IF;
  RETURN jsonb_build_object('result', CASE WHEN cid IS NULL THEN 'saved' ELSE 'linked' END);
END $$;
REVOKE ALL ON FUNCTION public.f360_capture_order_shipping(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_capture_order_shipping(text, jsonb) TO service_role;

-- A customer who registers AFTER buying online (app, counter, admin): link her orders by WhatsApp / e-mail and fill her ficha.
CREATE FUNCTION f360.customers_link_order_shipping() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ph text := f360.normalize_phone(NEW.phone); em text := nullif(lower(btrim(coalesce(NEW.email, ''))), '');
BEGIN
  IF NEW.role IS DISTINCT FROM 'customer' OR (ph IS NULL AND em IS NULL) THEN RETURN NULL; END IF;
  UPDATE f360.order_shipping SET customer_id = NEW.id, updated_at = now()
    WHERE customer_id IS NULL AND ((ph IS NOT NULL AND phone = ph) OR (em IS NOT NULL AND lower(email) = em));
  IF FOUND AND NEW.address_street IS NULL AND NEW.address_city IS NULL THEN PERFORM f360.customer_address_from_orders(NEW.id); END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER customers_link_order_shipping AFTER INSERT ON public.customers FOR EACH ROW EXECUTE FUNCTION f360.customers_link_order_shipping();
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261013000500', 'f360_order_shipping', '{}');
COMMIT;
