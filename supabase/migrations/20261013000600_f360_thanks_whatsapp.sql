-- Fuxia 360 · CRM C8 (Mario 2026-10-08: "yo más bien quiero que pase justo como pasa en la tienda física" + the thank-you WhatsApp
-- "como lo diseñaste"). ADDITIVE.
-- 1 · ONLINE = STORE. A paid online order from a buyer who is NOT a customer yet now registers her (source 'woo', WhatsApp from
--     the order, name, e-mail, address) and HOLDS her points (f360.loyalty_credit_or_hold, channel 'web', key 'woo_order:<id>'),
--     exactly like a counter sign-up: they are credited the first time she logs in to the app with that WhatsApp (existing
--     release trigger). Before this, such an order only went to public.unmatched_orders until she signed up herself.
--     Called by f360-woo-orders after stock (best effort). Buyers who ARE customers keep today's path (woocommerce-webhook credits).
--     Never twice, in any arrival order of the two webhooks (both serialize on the same advisory lock per order):
--       · a held order is skipped by the loyalty webhook's own check: when the hold is released, the BEFORE INSERT trigger
--         stamps transactions.wc_order_id (UNIQUE) = the order, which is exactly what woocommerce-webhook looks up;
--       · if woocommerce-webhook credits the order (it found her), the still-held hold is cancelled by trigger;
--       · if it already credited it, no hold is created; the unmatched_orders row is closed so link-orders never re-credits.
--     Cancelled / refunded / failed before she logs in → the held points are cancelled (after release the loyalty webhook
--     reverses them as today, since the transaction carries the order id).
-- 2 · THANK-YOU WHATSAPP. Every HELD purchase (store sale with a customer not yet in the app, or the online case above) queues
--     ONE message in f360.whatsapp_outbox: approved Twilio template fuxia_gracias_compra ({{1}} store or "en línea",
--     {{2}} first name, {{3}} points). Sent by the edge function f360-whatsapp (pg_net kick on enqueue + 1-minute cron;
--     claim/result RPCs so a message is never sent twice; >3 days old → expired, so a late template approval never
--     sends stale thanks). Customers already in the app (points credited) get no message, as in the design.
-- Rollback: supabase/rollbacks/20261013000600_f360_thanks_whatsapp.down.sql

-- ══ 2 · outbox ══════════════════════════════════════════════════════════════
CREATE TABLE f360.whatsapp_outbox (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind         text NOT NULL CHECK (kind IN ('thanks')),
  customer_id  uuid REFERENCES public.customers(id) ON DELETE CASCADE,
  phone        text NOT NULL,
  variables    jsonb NOT NULL,
  ref_type     text NOT NULL,
  ref_id       text NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  claimed_at   timestamptz,
  attempts     int NOT NULL DEFAULT 0,
  sent_at      timestamptz,
  provider_id  text,
  result       text,
  UNIQUE (kind, ref_type, ref_id)
);
CREATE INDEX whatsapp_outbox_pending_idx ON f360.whatsapp_outbox (created_at) WHERE sent_at IS NULL;
ALTER TABLE f360.whatsapp_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.whatsapp_outbox FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.whatsapp_outbox TO service_role;

-- Kick the sender now (URL in Vault 'f360_whatsapp_url', set per environment by its pase; none → the cron only).
CREATE FUNCTION f360.whatsapp_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.whatsapp_outbox WHERE sent_at IS NULL AND attempts < 5 AND created_at > now() - interval '3 days') THEN RETURN; END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_whatsapp_url';
  IF v_url IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := '{"Content-Type": "application/json"}'::jsonb, body := '{}'::jsonb, timeout_milliseconds := 20000);
END $$;
REVOKE ALL ON FUNCTION f360.whatsapp_tick() FROM PUBLIC, anon, authenticated;

-- One thank-you per HELD purchase.
CREATE FUNCTION f360.enqueue_thanks_on_hold() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE c public.customers; place text;
BEGIN
  IF NEW.status <> 'held' THEN RETURN NULL; END IF;
  SELECT * INTO c FROM public.customers WHERE id = NEW.customer_id;
  IF c.id IS NULL OR f360.normalize_phone(c.phone) IS NULL THEN RETURN NULL; END IF;
  place := CASE NEW.ref_type
    WHEN 'offline_sale' THEN (SELECT regexp_replace(l.name, '^Tienda\s+', '', 'i') FROM public.offline_sales s JOIN f360.locations l ON l.id = s.location_id
                              WHERE s.id::text = NEW.ref_id)
    WHEN 'woo_order' THEN 'en línea' END;
  INSERT INTO f360.whatsapp_outbox (kind, customer_id, phone, variables, ref_type, ref_id)
    VALUES ('thanks', c.id, f360.normalize_phone(c.phone),
            jsonb_build_object('1', coalesce(place, 'Ballerinas'), '2', coalesce(nullif(split_part(btrim(c.name), ' ', 1), ''), 'hola'),
                               '3', (public.loyalty_pairs_for_lines(NEW.lines) * public.loyalty_points_per_pair())::text),
            NEW.ref_type, NEW.ref_id)
    ON CONFLICT (kind, ref_type, ref_id) DO NOTHING;
  BEGIN PERFORM f360.whatsapp_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;   -- a kick failure never blocks the sale
  RETURN NULL;
END $$;
CREATE TRIGGER loyalty_holds_thanks AFTER INSERT ON f360.loyalty_holds FOR EACH ROW EXECUTE FUNCTION f360.enqueue_thanks_on_hold();

-- Sender side (service role only): claim a batch, then report each result.
CREATE FUNCTION public.f360_whatsapp_claim(p_limit int DEFAULT 20) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r jsonb;
BEGIN
  UPDATE f360.whatsapp_outbox SET result = 'expired' WHERE sent_at IS NULL AND result IS DISTINCT FROM 'expired' AND created_at <= now() - interval '3 days';
  WITH c AS (
    SELECT id FROM f360.whatsapp_outbox
    WHERE sent_at IS NULL AND attempts < 5 AND created_at > now() - interval '3 days'
      AND (claimed_at IS NULL OR claimed_at < now() - interval '2 minutes')
    ORDER BY created_at LIMIT least(greatest(coalesce(p_limit, 20), 1), 50) FOR UPDATE SKIP LOCKED)
  , u AS (
    UPDATE f360.whatsapp_outbox o SET claimed_at = now(), attempts = o.attempts + 1 FROM c WHERE o.id = c.id
    RETURNING o.id, o.kind, o.phone, o.variables)
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'kind', kind, 'phone', phone, 'variables', variables)), '[]') INTO r FROM u;
  RETURN r;
END $$;
CREATE FUNCTION public.f360_whatsapp_result(p_id uuid, p_ok boolean, p_provider_id text, p_result text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  UPDATE f360.whatsapp_outbox SET sent_at = CASE WHEN p_ok THEN now() END, claimed_at = CASE WHEN p_ok THEN claimed_at END,
    provider_id = left(p_provider_id, 64), result = left(p_result, 300)
  WHERE id = p_id AND sent_at IS NULL
$$;
REVOKE ALL ON FUNCTION public.f360_whatsapp_claim(int), public.f360_whatsapp_result(uuid, boolean, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_whatsapp_claim(int), public.f360_whatsapp_result(uuid, boolean, text, text) TO service_role;

-- ══ 1 · online = store ══════════════════════════════════════════════════════
-- A released web hold becomes a transaction that carries the order id, so woocommerce-webhook sees "already processed".
-- (only when no transaction has that order yet: a release must never fail — it runs inside her first login)
CREATE FUNCTION f360.transactions_web_order_id() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.ref_type = 'woo_order' AND NEW.wc_order_id IS NULL AND NEW.ref_id ~ '^[0-9]{1,9}$'
     AND NOT EXISTS (SELECT 1 FROM public.transactions WHERE wc_order_id = NEW.ref_id::int) THEN
    NEW.wc_order_id := NEW.ref_id::int;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER transactions_web_order_id BEFORE INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION f360.transactions_web_order_id();

-- woocommerce-webhook credited the order itself (she was found) → a still-held hold for it is cancelled.
CREATE FUNCTION f360.transactions_cancel_web_hold() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.wc_order_id IS NULL OR NEW.ref_type IS NOT DISTINCT FROM 'woo_order' THEN RETURN NULL; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('woo_order:' || NEW.wc_order_id));
  UPDATE f360.loyalty_holds SET status = 'cancelled', resolved_at = now(), result = jsonb_build_object('reason', 'credited_by_loyalty_webhook', 'transaction_id', NEW.id)
    WHERE idempotency_key = 'woo_order:' || NEW.wc_order_id AND status = 'held';
  RETURN NULL;
END $$;
CREATE TRIGGER transactions_cancel_web_hold AFTER INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION f360.transactions_cancel_web_hold();

CREATE FUNCTION public.f360_web_order_loyalty(p_target_key text, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.orders_target(p_target_key); oid bigint := (p_order->>'id')::bigint; st text := lower(coalesce(p_order->>'status', ''));
  k text; ph text; em text; nm text; cid uuid; card uuid; lines jsonb; total numeric; n int; r jsonb; a jsonb := coalesce(p_order->'address', '{}');
BEGIN
  IF oid IS NULL OR oid <= 0 THEN RAISE EXCEPTION 'Pedido sin número.'; END IF;
  k := 'woo_order:' || oid;
  PERFORM pg_advisory_xact_lock(hashtext(k));
  IF st IN ('cancelled', 'refunded', 'failed') THEN
    UPDATE f360.loyalty_holds SET status = 'cancelled', resolved_at = now(), result = jsonb_build_object('reason', 'order_' || st)
      WHERE idempotency_key = k AND status = 'held';
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN jsonb_build_object('result', CASE WHEN n > 0 THEN 'hold_cancelled' ELSE 'nothing' END);
  END IF;
  IF st NOT IN ('processing', 'completed') THEN RETURN jsonb_build_object('result', 'not_paid'); END IF;
  IF EXISTS (SELECT 1 FROM public.transactions WHERE wc_order_id = oid) OR EXISTS (SELECT 1 FROM f360.loyalty_holds WHERE idempotency_key = k)
     OR EXISTS (SELECT 1 FROM public.loyalty_apply_audit WHERE idempotency_key = k) THEN
    RETURN jsonb_build_object('result', 'already');
  END IF;
  ph := f360.normalize_phone(p_order->>'phone', coalesce(upper(nullif(p_order->>'country', '')), 'MX'));
  em := nullif(lower(btrim(coalesce(p_order->>'email', ''))), '');
  IF em !~ '^[^@\s]+@[^@\s]+\.[^@\s]{2,}$' THEN em := NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.customers WHERE (ph IS NOT NULL AND f360.normalize_phone(phone) = ph) OR (em IS NOT NULL AND lower(email) = em)) THEN
    RETURN jsonb_build_object('result', 'matched');                       -- she exists: woocommerce-webhook credits as today
  END IF;
  IF ph IS NULL THEN RETURN jsonb_build_object('result', 'no_phone'); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('sku', li->>'sku', 'product_name', li->>'name', 'quantity', greatest(coalesce((li->>'quantity')::int, 0), 0),
           'unit_price', CASE WHEN coalesce((li->>'quantity')::int, 0) > 0 THEN round((li->>'total')::numeric / (li->>'quantity')::int, 2) END,
           'wc_product_id', li->>'product_id')), '[]')
    INTO lines FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) li;
  IF public.loyalty_pairs_for_lines(lines) <= 0 THEN RETURN jsonb_build_object('result', 'no_pairs'); END IF;
  total := coalesce(nullif(p_order->>'total', '')::numeric, 0);
  nm := left(nullif(btrim(regexp_replace(coalesce(p_order->>'name', ''), '\s+', ' ', 'g')), ''), 80);
  BEGIN
    INSERT INTO public.customers (phone, name, email, country, source, role)
      VALUES (ph, coalesce(nm, 'Clienta Fuxia'), em, CASE WHEN ph LIKE '+57%' THEN 'CO' WHEN ph LIKE '+1%' THEN 'US' ELSE 'MX' END, 'woo', 'customer')
      RETURNING id INTO cid;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('result', 'matched');
  END;
  INSERT INTO public.loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier) VALUES (cid, '', 0, 0, 'bronze') RETURNING id INTO card;
  PERFORM f360.record_consent(cid, 'privacy_notice', 'requested',
    (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'privacy_notice' AND status = 'active'), 'web',
    jsonb_build_object('woo_order_id', oid));
  BEGIN
    PERFORM f360.customer_save_address(cid, a->>'street', a->>'neighborhood', a->>'city', a->>'state', a->>'postal_code', 'woo');
  EXCEPTION WHEN OTHERS THEN NULL;                                        -- a malformed address never blocks her points
  END;
  r := f360.loyalty_credit_or_hold(card, lines, total, 'web', 'woo_order', oid::text, k, jsonb_build_object('type', 'woo', 'target', t.key, 'order', oid));
  UPDATE public.unmatched_orders SET matched_at = now() WHERE wc_order_id = oid AND matched_at IS NULL;
  RETURN jsonb_build_object('result', 'registered', 'customer_id', cid, 'points', r);
END $$;
REVOKE ALL ON FUNCTION public.f360_web_order_loyalty(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_web_order_loyalty(text, jsonb) TO service_role;

SELECT cron.schedule('f360-whatsapp', '* * * * *', 'SELECT f360.whatsapp_tick()');
