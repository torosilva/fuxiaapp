-- Rollback of 20261007001100_f360_reservations.sql: restores ledger_move (20261003000100) and the store sale
-- (20261004000100) exactly, drops reservations (export them first if needed) and the expiry job.
SELECT cron.unschedule('f360-reservations-expire');
CREATE OR REPLACE FUNCTION f360.ledger_move(p_event uuid, p_variant uuid, p_from uuid, p_to uuid, p_qty int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_left int;
BEGIN
  IF p_qty <= 0 THEN RETURN; END IF;
  INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity) VALUES (p_event, p_variant, p_from, p_to, p_qty);
  IF p_from IS NOT NULL THEN
    UPDATE f360.inventory_balances SET on_hand = on_hand - p_qty, last_event_id = p_event, updated_at = now()
      WHERE variant_id = p_variant AND location_id = p_from AND on_hand >= p_qty RETURNING on_hand INTO v_left;
    IF v_left IS NULL THEN
      RAISE EXCEPTION 'No hay suficientes pares de % en %.', f360.variant_label(p_variant), (SELECT name FROM f360.locations WHERE id = p_from);
    END IF;
  END IF;
  IF p_to IS NOT NULL THEN
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at) VALUES (p_variant, p_to, p_qty, p_event, now())
      ON CONFLICT (variant_id, location_id) DO UPDATE SET on_hand = f360.inventory_balances.on_hand + EXCLUDED.on_hand, last_event_id = p_event, updated_at = now();
  END IF;
END $$;

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

DROP FUNCTION IF EXISTS public.f360_reservations(uuid, int);
DROP FUNCTION IF EXISTS public.f360_reservation_cancel(uuid, text);
DROP FUNCTION IF EXISTS public.f360_my_reservations();
DROP FUNCTION IF EXISTS public.f360_reserve_for_phone(text, uuid, uuid);
DROP FUNCTION IF EXISTS public.f360_reserve(uuid, uuid);
DROP FUNCTION IF EXISTS f360.reserve(uuid, uuid, uuid, text, text);
DROP FUNCTION IF EXISTS public.f360_store_availability(uuid, int);
DROP FUNCTION IF EXISTS f360.store_availability(uuid);
DROP FUNCTION IF EXISTS f360.expire_reservations();
DROP FUNCTION IF EXISTS f360.reserved_qty(uuid, uuid, uuid);
DROP TABLE IF EXISTS f360.reservations;
