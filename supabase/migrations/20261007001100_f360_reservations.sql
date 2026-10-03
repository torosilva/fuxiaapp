-- Fuxia 360 — Entrega inmediata + Apartado Gold, phase 1 (STAGING). Decisions: Mario 2026-10-02.
--   * A Fuxia Gold customer (public.loyalty_cards.tier = 'gold', the current loyalty programme) may reserve pairs in a
--     store for 2 hours; at most 2 reserved pairs open per customer; if she does not come, nothing happens (it expires).
--   * A reservation never moves inventory: it reduces what the store can give to OTHER people. The pair stays on hand.
--   * f360.ledger_move (every pair leaving a location: store sale, transfer) refuses to take a pair reserved for someone
--     else, and when the buyer is the customer who reserved it, her reservation becomes 'vendida'.
--   * The store sale passes the buyer (by her card QR) to ledger_move and gives a clear message; nothing else changes.
--   * "Entrega inmediata": stores (selling, Fuxia 360 ledger, active, not in a cut) with a free pair of the size.
--   * Expiry: pg_cron every minute (and every check already ignores expired reservations).
-- Rollback: supabase/rollbacks/20261007001100_f360_reservations.down.sql

CREATE TABLE f360.reservations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id   uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  variant_id    uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  customer_id   uuid NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
  channel       text NOT NULL CHECK (channel IN ('app', 'web', 'tienda')),
  status        text NOT NULL DEFAULT 'activa' CHECK (status IN ('activa', 'vendida', 'vencida', 'cancelada')),
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at    timestamptz NOT NULL,
  closed_at     timestamptz,
  closed_by     text,
  closed_reason text,
  sale_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT
);
CREATE INDEX reservations_active_idx ON f360.reservations (location_id, variant_id) WHERE status = 'activa';
CREATE INDEX reservations_customer_idx ON f360.reservations (customer_id, status);

-- Pairs of a size held for customers at a location (active and not yet expired), optionally excluding one customer.
CREATE FUNCTION f360.reserved_qty(p_variant uuid, p_location uuid, p_except_customer uuid DEFAULT NULL) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT count(*)::int FROM f360.reservations
  WHERE variant_id = p_variant AND location_id = p_location AND status = 'activa' AND expires_at > clock_timestamp()
    AND (p_except_customer IS NULL OR customer_id <> p_except_customer)
$$;

-- Every pair leaving a location: guarded update (never negative) + reservations respected / consumed.
CREATE OR REPLACE FUNCTION f360.ledger_move(p_event uuid, p_variant uuid, p_from uuid, p_to uuid, p_qty int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_left int; v_buyer uuid := nullif(current_setting('f360.sale_customer', true), '')::uuid; v_held int;
BEGIN
  IF p_qty <= 0 THEN RETURN; END IF;
  INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity) VALUES (p_event, p_variant, p_from, p_to, p_qty);
  IF p_from IS NOT NULL THEN
    v_held := f360.reserved_qty(p_variant, p_from, v_buyer);              -- pairs held for OTHER customers
    UPDATE f360.inventory_balances SET on_hand = on_hand - p_qty, last_event_id = p_event, updated_at = now()
      WHERE variant_id = p_variant AND location_id = p_from AND on_hand - v_held >= p_qty RETURNING on_hand INTO v_left;
    IF v_left IS NULL THEN
      IF v_held > 0 AND EXISTS (SELECT 1 FROM f360.inventory_balances WHERE variant_id = p_variant AND location_id = p_from AND on_hand >= p_qty) THEN
        RAISE EXCEPTION 'Ese par de % en % está apartado para una clienta Gold.', f360.variant_label(p_variant), (SELECT name FROM f360.locations WHERE id = p_from);
      END IF;
      RAISE EXCEPTION 'No hay suficientes pares de % en %.', f360.variant_label(p_variant), (SELECT name FROM f360.locations WHERE id = p_from);
    END IF;
    IF v_buyer IS NOT NULL THEN                                            -- the buyer takes her own reserved pairs first
      UPDATE f360.reservations SET status = 'vendida', closed_at = clock_timestamp(), closed_by = 'Venta en tienda', sale_event_id = p_event
      WHERE id IN (SELECT id FROM f360.reservations WHERE variant_id = p_variant AND location_id = p_from AND customer_id = v_buyer
                     AND status = 'activa' AND expires_at > clock_timestamp() ORDER BY created_at LIMIT p_qty);
    END IF;
  END IF;
  IF p_to IS NOT NULL THEN
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at) VALUES (p_variant, p_to, p_qty, p_event, now())
      ON CONFLICT (variant_id, location_id) DO UPDATE SET on_hand = f360.inventory_balances.on_hand + EXCLUDED.on_hand, last_event_id = p_event, updated_at = now();
  END IF;
END $$;

-- Stores that can hand this size over today (no quantities exposed).
CREATE FUNCTION f360.store_availability(p_variant uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', l.id, 'name', l.name) ORDER BY l.sort, l.name), '[]')
  FROM f360.locations l JOIN f360.inventory_balances b ON b.location_id = l.id AND b.variant_id = p_variant
  WHERE l.status = 'active' AND l.sellable AND l.type IN ('store', 'bazaar') AND l.ledger_authority = 'f360' AND NOT f360.location_in_cutover(l.id)
    AND (l.starts_on IS NULL OR l.starts_on <= current_date) AND (l.ends_on IS NULL OR l.ends_on >= current_date)
    AND b.on_hand - f360.reserved_qty(p_variant, l.id) > 0
$$;

CREATE FUNCTION public.f360_store_availability(p_variant_id uuid DEFAULT NULL, p_woo_variation_id int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v uuid := p_variant_id;
BEGIN
  IF v IS NULL AND p_woo_variation_id IS NOT NULL THEN
    SELECT vl.variant_id INTO v FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id AND t.active
      WHERE vl.woo_variation_id = p_woo_variation_id ORDER BY t.created_at LIMIT 1;
    IF v IS NULL THEN
      SELECT m.confirmed_variant_id INTO v FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id AND t.active
        WHERE m.woo_variation_id = p_woo_variation_id AND m.status = 'confirmado' ORDER BY t.created_at LIMIT 1;
    END IF;
  END IF;
  IF v IS NULL THEN RETURN jsonb_build_object('variant_id', NULL, 'stores', '[]'::jsonb); END IF;
  RETURN jsonb_build_object('variant_id', v, 'stores', f360.store_availability(v));
END $$;

CREATE FUNCTION f360.reserve(p_customer uuid, p_location uuid, p_variant uuid, p_channel text, p_by text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE l f360.locations; v_tier text; v_open int; v_on int; res f360.reservations;
BEGIN
  SELECT lc.tier INTO v_tier FROM public.loyalty_cards lc WHERE lc.customer_id = p_customer ORDER BY lc.total_points DESC NULLS LAST LIMIT 1;
  IF coalesce(v_tier, '') <> 'gold' THEN RAISE EXCEPTION 'El apartado de 2 horas es un beneficio Fuxia Gold.'; END IF;
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
    VALUES (l.id, p_variant, p_customer, p_channel, clock_timestamp() + interval '2 hours') RETURNING * INTO res;
  RETURN jsonb_build_object('id', res.id, 'store', l.name, 'variant', f360.variant_label(p_variant), 'expires_at', res.expires_at, 'status', res.status);
END $$;

-- App (customer logged in): her auth user → public.customers.
CREATE FUNCTION public.f360_reserve(p_location_id uuid, p_variant_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_cust uuid;
BEGIN
  SELECT id INTO v_cust FROM public.customers WHERE auth_user_id = auth.uid();
  IF v_cust IS NULL THEN RAISE EXCEPTION 'Inicia sesión con tu cuenta Fuxia para apartar.'; END IF;
  RETURN f360.reserve(v_cust, p_location_id, p_variant_id, 'app', 'clienta');
END $$;

-- Web (service_role only, AFTER the edge function verified the WhatsApp code for that phone).
CREATE FUNCTION public.f360_reserve_for_phone(p_phone text, p_location_id uuid, p_variant_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_cust uuid;
BEGIN
  SELECT id INTO v_cust FROM public.customers WHERE phone = btrim(p_phone) ORDER BY created_at LIMIT 1;
  IF v_cust IS NULL THEN RAISE EXCEPTION 'No encontramos una cuenta Fuxia con ese teléfono.'; END IF;
  RETURN f360.reserve(v_cust, p_location_id, p_variant_id, 'web', 'clienta');
END $$;

CREATE FUNCTION public.f360_my_reservations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'store', l.name, 'variant', f360.variant_label(r.variant_id),
      'status', CASE WHEN r.status = 'activa' AND r.expires_at <= clock_timestamp() THEN 'vencida' ELSE r.status END, 'expires_at', r.expires_at, 'created_at', r.created_at)
      ORDER BY r.created_at DESC), '[]')
    FROM f360.reservations r JOIN f360.locations l ON l.id = r.location_id
    WHERE r.customer_id = (SELECT id FROM public.customers WHERE auth_user_id = auth.uid()) AND r.created_at > now() - interval '30 days');
END $$;

-- Cancel: the customer herself, or the store team (operator/owner in Fuxia 360).
CREATE FUNCTION public.f360_reservation_cancel(p_reservation_id uuid, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE res f360.reservations; v_cust uuid; r f360.user_roles; v_by text;
BEGIN
  SELECT * INTO res FROM f360.reservations WHERE id = p_reservation_id FOR UPDATE;
  IF res.id IS NULL THEN RAISE EXCEPTION 'Apartado no encontrado.'; END IF;
  SELECT id INTO v_cust FROM public.customers WHERE auth_user_id = auth.uid();
  IF v_cust IS NOT NULL AND v_cust = res.customer_id THEN v_by := 'Clienta';
  ELSE r := f360.require_role('operator'); v_by := r.display_name; END IF;
  IF res.status <> 'activa' THEN RAISE EXCEPTION 'Ese apartado ya no está activo.'; END IF;
  UPDATE f360.reservations SET status = 'cancelada', closed_at = clock_timestamp(), closed_by = v_by, closed_reason = nullif(btrim(p_reason), '') WHERE id = res.id;
  RETURN jsonb_build_object('id', res.id, 'status', 'cancelada');
END $$;

-- Store team view (operator+): reservations of a location (default: all stores), newest first.
CREATE FUNCTION public.f360_reservations(p_location_id uuid DEFAULT NULL, p_days int DEFAULT 7) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'location_id', r.location_id, 'store', l.name,
      'variant_id', r.variant_id, 'product', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
      'customer', cu.name, 'phone_last4', right(regexp_replace(cu.phone, '\D', '', 'g'), 4), 'channel', r.channel,
      'status', CASE WHEN r.status = 'activa' AND r.expires_at <= clock_timestamp() THEN 'vencida' ELSE r.status END,
      'created_at', r.created_at, 'expires_at', r.expires_at, 'closed_at', r.closed_at, 'closed_by', r.closed_by, 'closed_reason', r.closed_reason)
      ORDER BY (r.status = 'activa' AND r.expires_at > clock_timestamp()) DESC, r.created_at DESC), '[]')
    FROM f360.reservations r JOIN f360.locations l ON l.id = r.location_id JOIN f360.product_variants v ON v.id = r.variant_id
    JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id JOIN public.customers cu ON cu.id = r.customer_id
    WHERE (p_location_id IS NULL OR r.location_id = p_location_id) AND r.created_at > now() - make_interval(days => greatest(1, least(p_days, 90))));
END $$;

CREATE FUNCTION f360.expire_reservations() RETURNS int LANGUAGE sql AS $$
  WITH x AS (UPDATE f360.reservations SET status = 'vencida', closed_at = clock_timestamp(), closed_by = 'Sistema (2 horas)'
             WHERE status = 'activa' AND expires_at <= clock_timestamp() RETURNING 1) SELECT count(*)::int FROM x
$$;
SELECT cron.schedule('f360-reservations-expire', '* * * * *', 'SELECT f360.expire_reservations()');

-- ── Store sale: unchanged from 20261004000100 except the two marked Reservation lines in the F360 branch ──
CREATE OR REPLACE FUNCTION public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_qr text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations; seller_name text; seller_role text; prior public.offline_sales; sale public.offline_sales;
  li jsonb; k text; v_id uuid; v_qty int; ci record; v_total numeric := 0; n int := 0; v_code text; card public.loyalty_cards;
  loy jsonb; lines_for_loyalty jsonb := '[]'; items_compat jsonb := '[]'; req jsonb := '{}'; is_f360 boolean; v_event uuid;
BEGIN
  -- 1 · WHO and WHERE come from the server: authenticated seller + active shift at an assigned location
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF f360.location_in_cutover(l.id) THEN RAISE EXCEPTION '% está en corte de inventario: no se puede vender hasta terminar el conteo.', l.name; END IF;
  is_f360 := l.ledger_authority = 'f360';
  IF NOT is_f360 AND l.legacy_channel_id IS NULL THEN RAISE EXCEPTION 'Esta ubicación no tiene inventario del sistema anterior.'; END IF;
  SELECT display_name, role INTO seller_name, seller_role FROM f360.user_roles WHERE auth_user_id = s.auth_user_id;

  -- 2 · idempotency (double tap / retry): the same key returns the same sale
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la venta.'; END IF;
  SELECT * INTO prior FROM public.offline_sales WHERE idempotency_key = p_idempotency_key;
  IF prior.id IS NOT NULL THEN
    IF prior.seller_auth_user_id IS DISTINCT FROM s.auth_user_id THEN RAISE EXCEPTION 'Llave de venta repetida.'; END IF;
    RETURN jsonb_build_object('ok', true, 'replayed', true, 'sale_id', prior.id, 'code', CASE WHEN prior.claimed_at IS NULL THEN prior.code END,
      'total', prior.total, 'points', prior.points_earned, 'self_sale', prior.self_sale, 'claimed', prior.claimed_at IS NOT NULL);
  END IF;

  -- 3 · payment (D-PM)
  IF p_payment_method IS NULL OR p_payment_method NOT IN ('cash', 'card', 'transfer', 'other') THEN RAISE EXCEPTION 'Elige cómo pagó la clienta.'; END IF;
  IF p_payment_reference IS NOT NULL AND (length(p_payment_reference) > 64 OR p_payment_reference ~ '[0-9]{12,}') THEN
    RAISE EXCEPTION 'La referencia no puede contener números de tarjeta.';
  END IF;

  -- 4 · input: ONLY {channel_inventory_id | variant_id, quantity}. Any price/total/points/location/seller key is refused.
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 OR jsonb_array_length(p_lines) > 50 THEN
    RAISE EXCEPTION 'La venta necesita entre 1 y 50 productos.';
  END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN (CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END, 'quantity') THEN
        RAISE EXCEPTION 'Solo se aceptan producto y cantidad: el precio, la ubicación y la vendedora los pone el sistema (campo "%").', k;
      END IF;
    END LOOP;
    v_qty := (li->>'quantity')::int;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN RAISE EXCEPTION 'Cantidad no válida.'; END IF;
    v_id := (li->>CASE WHEN is_f360 THEN 'variant_id' ELSE 'channel_inventory_id' END)::uuid;
    IF v_id IS NULL THEN RAISE EXCEPTION 'Falta el producto en una línea.'; END IF;
    req := jsonb_set(req, ARRAY[v_id::text], to_jsonb(coalesce((req->>v_id::text)::int, 0) + v_qty));   -- same product twice → summed
  END LOOP;

  IF is_f360 THEN
    -- ═══ F360 branch (C3): the single ledger is the stock; master price; never negative ═══
    -- Reservations (Apartado Gold): the buying customer (by her card QR) may take HER reserved pairs; nobody else may.
    PERFORM set_config('f360.sale_customer', coalesce((SELECT customer_id::text FROM public.loyalty_cards WHERE qr_code = btrim(coalesce(p_customer_qr, ''))), ''), true);
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(req) x LEFT JOIN f360.product_variants v ON v.id = x::uuid AND v.status = 'active' WHERE v.id IS NULL) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    PERFORM 1 FROM f360.inventory_balances b WHERE b.location_id = l.id AND b.variant_id IN (SELECT x::uuid FROM jsonb_object_keys(req) x)
      ORDER BY b.variant_id FOR UPDATE;                                                             -- same lock order as transfers
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     coalesce(b.on_hand, 0) AS on_hand, (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              LEFT JOIN f360.inventory_balances b ON b.variant_id = v.id AND b.location_id = l.id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      IF ci.on_hand < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %).', ci.product_name, ci.color, ci.size_label, ci.on_hand;
      END IF;
      IF ci.on_hand - f360.reserved_qty(ci.id, l.id, nullif(current_setting('f360.sale_customer', true), '')::uuid) < ci.qty THEN
        RAISE EXCEPTION 'Ese par de % % % está apartado para otra clienta (Apartado Gold). Quedan % libres.', ci.product_name, ci.color, ci.size_label,
          greatest(0, ci.on_hand - f360.reserved_qty(ci.id, l.id, nullif(current_setting('f360.sale_customer', true), '')::uuid));
      END IF;
      IF ci.price IS NULL THEN RAISE EXCEPTION '% no tiene precio en Fuxia 360: no se puede vender.', ci.product_name; END IF;
      v_total := v_total + ci.price * ci.qty;
    END LOOP;
  ELSE
    -- ═══ Legacy branch (S0.3, unchanged): lock the legacy stock rows; every row must belong to THIS shift's channel ═══
    FOR ci IN SELECT * FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY id FOR UPDATE LOOP
      IF ci.channel_id IS DISTINCT FROM l.legacy_channel_id THEN RAISE EXCEPTION 'Un producto no pertenece a tu tienda.'; END IF;
    END LOOP;
    IF (SELECT count(*) FROM public.channel_inventory WHERE id IN (SELECT (jsonb_object_keys(req))::uuid)) <> (SELECT count(*) FROM jsonb_object_keys(req)) THEN
      RAISE EXCEPTION 'Un producto no existe.';
    END IF;
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      IF coalesce(ci.stock, 0) - coalesce(ci.sold, 0) < ci.qty THEN
        RAISE EXCEPTION 'No hay existencia suficiente de % % % (quedan %). Pide un ajuste de inventario.', ci.product_name, coalesce(ci.color, ''), coalesce(ci.size, ''),
          greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0);
      END IF;
      v_total := v_total + ci.price * ci.qty;                                                 -- authoritative legacy price (D-P2)
    END LOOP;
  END IF;

  -- 5 · the sale (claim code from a CSPRNG)
  LOOP
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE code = v_code);
  END LOOP;
  INSERT INTO public.offline_sales (code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned,
      idempotency_key, seller_auth_user_id, location_id, session_id, payment_method, payment_reference, price_source, created_by_rpc)
    VALUES (v_code, CASE WHEN is_f360 THEN NULL ELSE l.legacy_channel_id END, NULL, NULL, NULL, '[]', v_total, 0,
      p_idempotency_key, s.auth_user_id, l.id, s.id, p_payment_method, nullif(btrim(p_payment_reference), ''),
      CASE WHEN is_f360 THEN 'f360_master_price' ELSE 'legacy_channel_inventory' END, true)
    RETURNING * INTO sale;

  IF is_f360 THEN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
      VALUES ('SALE', p_idempotency_key, s.auth_user_id, coalesce(seller_name, 'Vendedora'), coalesce(seller_role, 'seller'), 'Venta en ' || l.name, 'offline_sale', sale.id::text)
      RETURNING id INTO v_event;
    FOR ci IN SELECT v.id, v.sku, v.size_label, p.name AS product_name, c.name AS color, p.category_key,
                     coalesce(p.sale_price, p.regular_price) AS price, CASE WHEN p.sale_price IS NOT NULL THEN 'f360_master_sale_price' ELSE 'f360_master_price' END AS price_source,
                     (req->>v.id::text)::int AS qty
              FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
              WHERE v.id IN (SELECT x::uuid FROM jsonb_object_keys(req) x) ORDER BY v.id LOOP
      n := n + 1;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, variant_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, NULL, ci.id, ci.sku, ci.product_name, ci.size_label, ci.color, ci.qty, ci.price, ci.price * ci.qty, ci.price_source);
      PERFORM f360.ledger_move(v_event, ci.id, l.id, NULL, ci.qty);                             -- never negative (guarded update)
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('sku', ci.sku, 'product_name', ci.product_name, 'size', ci.size_label,
        'color', ci.color, 'category', ci.category_key, 'quantity', ci.qty, 'unit_price', ci.price);
      items_compat := items_compat || jsonb_build_object('variant_id', ci.id, 'product_name', ci.product_name, 'size', ci.size_label, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);
    END LOOP;
    UPDATE public.offline_sales SET sale_event_id = v_event WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    FOR ci IN SELECT c.*, (req->>c.id::text)::int AS qty FROM public.channel_inventory c WHERE c.id IN (SELECT (jsonb_object_keys(req))::uuid) ORDER BY c.id LOOP
      n := n + 1;
      INSERT INTO public.offline_sale_items (sale_id, line_no, channel_inventory_id, sku, product_name, size, color, quantity, unit_price, line_total, price_source)
        VALUES (sale.id, n, ci.id, ci.sku, ci.product_name, ci.size, ci.color, ci.qty, ci.price, ci.price * ci.qty, 'legacy_channel_inventory');
      UPDATE public.channel_inventory SET sold = coalesce(sold, 0) + ci.qty, updated_at = now() WHERE id = ci.id;   -- relative, under the lock
      lines_for_loyalty := lines_for_loyalty || jsonb_build_object('channel_inventory_id', ci.id, 'sku', ci.sku, 'product_name', ci.product_name,
        'size', ci.size, 'color', ci.color, 'quantity', ci.qty, 'unit_price', ci.price);
      items_compat := items_compat || jsonb_build_object('inventory_id', ci.id, 'product_name', ci.product_name, 'size', ci.size, 'color', ci.color,
        'quantity', ci.qty, 'unit_price', ci.price);   -- same shape the existing app screens read
    END LOOP;
  END IF;

  -- 6 · customer (optional, never required to discount stock). Unknown QR → the WHOLE sale is refused (rollback).
  IF nullif(btrim(p_customer_qr), '') IS NOT NULL THEN
    SELECT * INTO card FROM public.loyalty_cards WHERE qr_code = btrim(p_customer_qr);
    IF card.id IS NULL THEN RAISE EXCEPTION 'No encontramos esa tarjeta de clienta. Vuelve a escanear o registra la venta sin clienta.'; END IF;
    loy := public.loyalty_apply(card.id, lines_for_loyalty, v_total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
      jsonb_build_object('type', 'seller', 'auth_user_id', s.auth_user_id, 'name', seller_name, 'location_id', l.id, 'session_id', s.id));
    UPDATE public.offline_sales SET customer_id = card.customer_id, claimed_at = now(), items = items_compat,
      points_earned = coalesce((loy->>'points')::int, 0), self_sale = coalesce((loy->>'self_sale')::boolean, false),
      loyalty_transaction_id = nullif(loy->>'transaction_id', '')::uuid
      WHERE id = sale.id RETURNING * INTO sale;
  ELSE
    UPDATE public.offline_sales SET items = items_compat WHERE id = sale.id RETURNING * INTO sale;
  END IF;

  RETURN jsonb_build_object('ok', true, 'replayed', false, 'sale_id', sale.id, 'code', CASE WHEN sale.claimed_at IS NULL THEN sale.code END,
    'total', sale.total, 'lines', n, 'points', sale.points_earned, 'self_sale', sale.self_sale, 'claimed', sale.claimed_at IS NOT NULL,
    'location', l.name, 'seller', seller_name, 'payment_method', sale.payment_method, 'ledger', CASE WHEN is_f360 THEN 'f360' ELSE 'legacy' END);
END $$;
REVOKE ALL ON f360.reservations FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.reservations TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_store_availability(uuid, int), public.f360_reserve(uuid, uuid), public.f360_reserve_for_phone(text, uuid, uuid),
  public.f360_my_reservations(), public.f360_reservation_cancel(uuid, text), public.f360_reservations(uuid, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_store_availability(uuid, int) TO anon, authenticated, service_role;   -- store names only, no quantities
GRANT EXECUTE ON FUNCTION public.f360_reserve(uuid, uuid), public.f360_my_reservations(), public.f360_reservation_cancel(uuid, text),
  public.f360_reservations(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_reserve_for_phone(text, uuid, uuid) TO service_role;
