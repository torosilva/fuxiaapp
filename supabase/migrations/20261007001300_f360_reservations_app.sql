-- Fuxia 360 — Apartado Gold in the seller app (phase 4, STAGING). Decisions: Mario 2026-10-02 ("si eso si hacerlo dale").
--   * When a pair is reserved, the sellers of THAT store get a push notification: who is assigned to the store, plus
--     whoever has a shift open there (owner/operator covering). Outbox + Edge Function f360-push (Expo push API).
--     The notification never blocks the reservation: the outbox row is written in the same transaction, the send is
--     asynchronous (pg_net after commit) and retried by a cron tick every minute (max 5 attempts).
--   * The seller app shows the active reservations of her SHIFT's store and marks one "Ya lo separé" (pair on the counter).
--     Marking does not move inventory and does not change the reservation rules (ledger_move already holds the pair).
--   * The shift catalog tells how many pairs of each size are reserved, so the seller does not offer them to someone else.
-- No secret or URL in this file: the tick reads 'f360_push_url' and 'f360_push_secret' from Supabase Vault; an environment
-- without them (production) queues nothing to send and the tick does nothing.
-- Rollback: supabase/rollbacks/20261007001300_f360_reservations_app.down.sql

ALTER TABLE f360.reservations ADD COLUMN separated_at timestamptz, ADD COLUMN separated_by text;

CREATE TABLE f360.push_outbox (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         text NOT NULL,
  body          text NOT NULL,
  data          jsonb NOT NULL DEFAULT '{}',
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  attempts      int NOT NULL DEFAULT 0,
  sent_at       timestamptz,
  result        text
);
CREATE INDEX push_outbox_pending_idx ON f360.push_outbox (created_at) WHERE sent_at IS NULL;

-- People who should hear about a location right now: active assignment, or an open shift there.
CREATE FUNCTION f360.location_team(p_location uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT a.auth_user_id FROM f360.location_assignments a JOIN f360.user_roles u ON u.auth_user_id = a.auth_user_id
    WHERE a.location_id = p_location AND a.active AND u.role IN ('seller', 'operator', 'owner')
  UNION
  SELECT s.auth_user_id FROM f360.seller_sessions s
    WHERE s.location_id = p_location AND s.revoked_at IS NULL AND s.expires_at > now()
$$;

-- pg_cron / trigger tick: POST f360-push only when something is waiting. URL + Bearer from Vault; no-op without them.
CREATE FUNCTION f360.push_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.push_outbox WHERE sent_at IS NULL AND attempts < 5) THEN RETURN; END IF;
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_push_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_push_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"send"}'::jsonb, timeout_milliseconds := 20000);
END $$;

CREATE FUNCTION f360.notify_reservation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_label text; v_who text; v_until text;
BEGIN
  SELECT p.name || ' ' || c.name || ' ' || v.size_label INTO v_label
    FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id WHERE v.id = NEW.variant_id;
  SELECT split_part(btrim(name), ' ', 1) INTO v_who FROM public.customers WHERE id = NEW.customer_id;
  v_until := replace(replace(to_char(NEW.expires_at AT TIME ZONE 'America/Mexico_City', 'FMHH12:MI am'), 'am', 'a. m.'), 'pm', 'p. m.');
  INSERT INTO f360.push_outbox (auth_user_id, title, body, data)
    SELECT t, 'Apartado Fuxia Gold',
           'Separa ' || coalesce(v_label, 'un par') || ' para ' || coalesce(nullif(v_who, ''), 'una clienta') || ' · hasta las ' || v_until,
           jsonb_build_object('type', 'f360_reservation', 'reservation_id', NEW.id, 'location_id', NEW.location_id)
    FROM f360.location_team(NEW.location_id) t;
  BEGIN
    PERFORM f360.push_tick();                                -- sent after commit by pg_net; never blocks the reservation
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END $$;
CREATE TRIGGER reservations_notify AFTER INSERT ON f360.reservations FOR EACH ROW EXECUTE FUNCTION f360.notify_reservation();

-- Edge Function f360-push (service_role): claim what is due, with the Expo tokens of each person; then report back.
CREATE FUNCTION public.f360_push_claim(p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_out jsonb;
BEGIN
  WITH due AS (
      SELECT o.id FROM f360.push_outbox o WHERE o.sent_at IS NULL AND o.attempts < 5
        AND o.created_at > now() - interval '2 hours'                -- a reservation notice older than the hold is useless
      ORDER BY o.created_at LIMIT greatest(1, least(p_limit, 500)) FOR UPDATE SKIP LOCKED),
    upd AS (UPDATE f360.push_outbox o SET attempts = o.attempts + 1 FROM due WHERE o.id = due.id RETURNING o.*)
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'title', u.title, 'body', u.body, 'data', u.data,
      'tokens', (SELECT coalesce(jsonb_agg(DISTINCT pt.expo_token), '[]') FROM public.push_tokens pt JOIN public.customers cu ON cu.id = pt.customer_id
                 WHERE cu.auth_user_id = u.auth_user_id))), '[]') INTO v_out FROM upd u;
  RETURN v_out;
END $$;

CREATE FUNCTION public.f360_push_result(p_results jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE x jsonb; n int := 0;
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_results, '[]')) LOOP
    UPDATE f360.push_outbox SET result = left(x->>'result', 200),
        sent_at = CASE WHEN (x->>'done')::boolean THEN clock_timestamp() END
      WHERE id = (x->>'id')::uuid AND sent_at IS NULL;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

SELECT cron.schedule('f360-push-retry', '* * * * *', 'SELECT f360.push_tick()');

-- ── Seller app: the reservations of HER shift's store (location from the session, never from the client) ──
CREATE FUNCTION public.f360_shift_reservations(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions;
BEGIN
  s := f360.require_seller_session(p_token);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'variant_id', r.variant_id, 'product', p.name, 'color', c.name,
      'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku, 'customer', split_part(btrim(cu.name), ' ', 1),
      'phone_last4', right(regexp_replace(coalesce(cu.phone, ''), '\D', '', 'g'), 4), 'channel', r.channel,
      'status', CASE WHEN r.status = 'activa' AND r.expires_at <= clock_timestamp() THEN 'vencida' ELSE r.status END,
      'created_at', r.created_at, 'expires_at', r.expires_at, 'separated_at', r.separated_at, 'separated_by', r.separated_by,
      'closed_at', r.closed_at, 'closed_by', r.closed_by)
      ORDER BY (r.status = 'activa' AND r.expires_at > clock_timestamp()) DESC, r.expires_at), '[]')
    FROM f360.reservations r JOIN f360.product_variants v ON v.id = r.variant_id JOIN f360.products p ON p.id = v.product_id
    JOIN f360.product_colors c ON c.id = v.color_id JOIN public.customers cu ON cu.id = r.customer_id
    WHERE r.location_id = s.location_id AND (r.status = 'activa' OR r.closed_at > now() - interval '12 hours'));
END $$;

CREATE FUNCTION public.f360_shift_reservation_separate(p_token text, p_reservation_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; res f360.reservations; v_name text;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO res FROM f360.reservations WHERE id = p_reservation_id FOR UPDATE;
  IF res.id IS NULL OR res.location_id <> s.location_id THEN RAISE EXCEPTION 'Ese apartado no es de tu tienda.'; END IF;
  IF res.status <> 'activa' OR res.expires_at <= clock_timestamp() THEN RAISE EXCEPTION 'Ese apartado ya no está activo.'; END IF;
  IF res.separated_at IS NULL THEN
    SELECT display_name INTO v_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;
    UPDATE f360.reservations SET separated_at = clock_timestamp(), separated_by = coalesce(v_name, 'Vendedora') WHERE id = res.id RETURNING * INTO res;
  END IF;
  RETURN jsonb_build_object('id', res.id, 'separated_at', res.separated_at, 'separated_by', res.separated_by);
END $$;

-- ── Shift catalog: unchanged from 20261004000100 except 'reserved' (pairs held for Gold customers) in the f360 branch ──
CREATE OR REPLACE FUNCTION public.f360_shift_catalog(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RETURN jsonb_build_object('location', l.name, 'ledger', 'f360', 'in_cutover', false, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', v.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
        'price', coalesce(p.sale_price, p.regular_price), 'available', b.on_hand, 'reserved', f360.reserved_qty(v.id, l.id)) ORDER BY p.name, c.sort, v.size_label), '[]'::jsonb)
      FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id WHERE b.location_id = l.id AND b.on_hand > 0));
  END IF;
  RETURN jsonb_build_object('location', l.name, 'ledger', 'legacy', 'in_cutover', f360.location_in_cutover(l.id), 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'channel_inventory_id', ci.id, 'product_name', ci.product_name, 'color', ci.color, 'size', ci.size, 'sku', ci.sku, 'price', ci.price,
      'available', greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)) ORDER BY ci.product_name, ci.color, ci.size), '[]'::jsonb)
    FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0));
END $$;

-- ── Admin "Apartados Gold": same as 20261007001100 plus separated_at / separated_by ──
CREATE OR REPLACE FUNCTION public.f360_reservations(p_location_id uuid DEFAULT NULL, p_days int DEFAULT 7) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'location_id', r.location_id, 'store', l.name,
      'variant_id', r.variant_id, 'product', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
      'customer', cu.name, 'phone_last4', right(regexp_replace(cu.phone, '\D', '', 'g'), 4), 'channel', r.channel,
      'status', CASE WHEN r.status = 'activa' AND r.expires_at <= clock_timestamp() THEN 'vencida' ELSE r.status END,
      'created_at', r.created_at, 'expires_at', r.expires_at, 'closed_at', r.closed_at, 'closed_by', r.closed_by, 'closed_reason', r.closed_reason,
      'separated_at', r.separated_at, 'separated_by', r.separated_by)
      ORDER BY (r.status = 'activa' AND r.expires_at > clock_timestamp()) DESC, r.created_at DESC), '[]')
    FROM f360.reservations r JOIN f360.locations l ON l.id = r.location_id JOIN f360.product_variants v ON v.id = r.variant_id
    JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id JOIN public.customers cu ON cu.id = r.customer_id
    WHERE (p_location_id IS NULL OR r.location_id = p_location_id) AND r.created_at > now() - make_interval(days => greatest(1, least(p_days, 90))));
END $$;

REVOKE ALL ON f360.push_outbox FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.push_outbox TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_push_claim(int), public.f360_push_result(jsonb), public.f360_shift_reservations(text),
  public.f360_shift_reservation_separate(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_push_claim(int), public.f360_push_result(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_shift_reservations(text), public.f360_shift_reservation_separate(text, uuid) TO authenticated, service_role;
