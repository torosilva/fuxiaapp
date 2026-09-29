-- ROLLBACK for 20261004000100_f360_c3_cutover_and_f360_sale.sql (STAGING).
-- REFUSES to run if any cutover exists or any F360 store sale was recorded: a migrated location never returns to legacy,
-- and history is never deleted by a rollback. Restores the exact previous definitions (dumped from staging before applying).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.location_cutovers) OR EXISTS (SELECT 1 FROM public.offline_sales WHERE sale_event_id IS NOT NULL)
     OR EXISTS (SELECT 1 FROM f360.inventory_events WHERE event_type = 'OPENING_PHYSICAL_COUNT') THEN
    RAISE EXCEPTION 'Rollback refused: cutovers / F360 store sales exist.';
  END IF;
END $$;
DROP FUNCTION public.f360_start_cutover(uuid, uuid, text), public.f360_cutover_count(uuid, jsonb), public.f360_cutover_finish_count(uuid),
  public.f360_cutover_verify(uuid, jsonb), public.f360_cancel_cutover(uuid, text), public.f360_complete_cutover(uuid, uuid), public.f360_get_cutover(uuid),
  public.f360_shift_catalog(text);
DROP FUNCTION f360.cutover_do_complete(uuid, f360.location_cutovers, f360.user_roles), f360.cutover_json(uuid, f360.user_roles),
  f360.cutover_log(f360.location_cutovers, text, text, jsonb, text, f360.user_roles), f360.require_counter(uuid), f360.cutover_required_variants(uuid);
DROP TRIGGER legacy_inventory_map_guard ON f360.legacy_inventory_map;  DROP FUNCTION f360.guard_legacy_map();
DROP TRIGGER offline_sales_client_guard ON public.offline_sales;       DROP FUNCTION public.offline_sales_client_guard();
DROP TRIGGER channel_inventory_freeze ON public.channel_inventory;      DROP FUNCTION public.channel_inventory_freeze_guard();
DROP TRIGGER locations_guard_ledger_authority ON f360.locations;       DROP FUNCTION f360.guard_ledger_authority();
CREATE OR REPLACE FUNCTION f360.assert_ledger_location(p_location uuid)
 RETURNS f360.locations
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location AND status = 'active';
  IF l.id IS NULL OR l.type = 'transit' THEN RAISE EXCEPTION 'Elige una ubicación válida.'; END IF;
  IF l.ledger_authority <> 'f360' THEN
    RAISE EXCEPTION '% todavía lleva su inventario en el sistema anterior. Se podrá operar aquí cuando se migre.', l.name;
  END IF;
  RETURN l;
END $function$
;

CREATE OR REPLACE FUNCTION f360.online_location()
 RETURNS f360.locations
 LANGUAGE sql
 STABLE
AS $function$
  SELECT * FROM f360.locations WHERE status = 'active' AND is_authoritative AND type IN ('warehouse', 'receiving')
  ORDER BY sort, created_at LIMIT 1
$function$
;

CREATE OR REPLACE FUNCTION public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text, p_payment_reference text DEFAULT NULL::text, p_customer_qr text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE s f360.seller_sessions; l f360.locations; seller_name text; prior public.offline_sales; sale public.offline_sales;
  li jsonb; k text; v_id uuid; v_qty int; ci record; v_total numeric := 0; n int := 0; v_code text; card public.loyalty_cards;
  loy jsonb; lines_for_loyalty jsonb := '[]'; items_compat jsonb := '[]'; req jsonb := '{}';
BEGIN
  -- 1 · WHO and WHERE come from the server: authenticated seller + active shift at an assigned location
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RAISE EXCEPTION 'La venta en % se habilita con la migración de la ubicación (C3).', l.name;   -- f360 branch dormant until C3
  END IF;
  IF l.legacy_channel_id IS NULL THEN RAISE EXCEPTION 'Esta ubicación no tiene inventario del sistema anterior.'; END IF;
  seller_name := (SELECT display_name FROM f360.user_roles WHERE auth_user_id = s.auth_user_id);

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

  -- 4 · input: ONLY {channel_inventory_id, quantity}. Any price/total/points/location/seller key is refused.
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 OR jsonb_array_length(p_lines) > 50 THEN
    RAISE EXCEPTION 'La venta necesita entre 1 y 50 productos.';
  END IF;
  FOR li IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(li) <> 'object' THEN RAISE EXCEPTION 'Línea no válida.'; END IF;
    FOR k IN SELECT jsonb_object_keys(li) LOOP
      IF k NOT IN ('channel_inventory_id', 'quantity') THEN
        RAISE EXCEPTION 'Solo se aceptan producto y cantidad: el precio, la ubicación y la vendedora los pone el sistema (campo "%").', k;
      END IF;
    END LOOP;
    v_qty := (li->>'quantity')::int;
    IF v_qty IS NULL OR v_qty < 1 OR v_qty > 99 THEN RAISE EXCEPTION 'Cantidad no válida.'; END IF;
    v_id := (li->>'channel_inventory_id')::uuid;
    req := jsonb_set(req, ARRAY[v_id::text], to_jsonb(coalesce((req->>v_id::text)::int, 0) + v_qty));   -- same product twice → summed
  END LOOP;

  -- 5 · lock the legacy stock rows in id order; every row must belong to THIS shift's channel; never oversell (D-S1)
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
    v_total := v_total + ci.price * ci.qty;                                                 -- 6 · authoritative price (D-P2)
  END LOOP;

  -- 7 · the sale (claim code from a CSPRNG)
  LOOP
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE code = v_code);
  END LOOP;
  INSERT INTO public.offline_sales (code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned,
      idempotency_key, seller_auth_user_id, location_id, session_id, payment_method, payment_reference, price_source, created_by_rpc)
    VALUES (v_code, l.legacy_channel_id, NULL, NULL, NULL, '[]', v_total, 0,
      p_idempotency_key, s.auth_user_id, l.id, s.id, p_payment_method, nullif(btrim(p_payment_reference), ''), 'legacy_channel_inventory', true)
    RETURNING * INTO sale;

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

  -- 8 · customer (optional, never required to discount stock). Unknown QR → the WHOLE sale is refused (rollback).
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
    'location', l.name, 'seller', seller_name, 'payment_method', sale.payment_method);
END $function$
;
CREATE OR REPLACE VIEW f360.store_sale_facts AS  SELECT id AS sale_id,
    'store_legacy'::text AS source,
    location_id,
    channel_id AS legacy_channel_id,
    seller_auth_user_id,
    customer_id,
    total,
    payment_method,
    price_source,
    self_sale,
    points_earned,
    claimed_at,
    created_at,
    ( SELECT COALESCE(sum(i.quantity), 0::bigint) AS "coalesce"
           FROM offline_sale_items i
          WHERE i.sale_id = s.id) AS units
   FROM offline_sales s
  WHERE created_by_rpc;
;

DROP FUNCTION public.f360_legacy_channel_frozen(uuid), f360.legacy_channel_frozen(uuid);
DROP TABLE f360.cutover_changes, f360.cutover_counts, f360.location_cutovers;
DROP FUNCTION f360.guard_cutover(), f360.guard_cutover_count(), f360.location_in_cutover(uuid);
ALTER TABLE public.offline_sales DROP COLUMN sale_event_id;
ALTER TABLE public.offline_sale_items DROP COLUMN variant_id;
DROP INDEX f360.inventory_events_one_opening_per_location;
ALTER TABLE f360.inventory_events DROP CONSTRAINT inventory_events_event_type_check;
ALTER TABLE f360.inventory_events ADD CONSTRAINT inventory_events_event_type_check CHECK (event_type IN
  ('RECEIPT', 'TRANSFER', 'SALE', 'RETURN', 'ADJUSTMENT', 'RESERVATION', 'RELEASE', 'WRITE_OFF', 'FULFILLMENT', 'PRODUCTION_RECEIPT'));
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON f360.store_sale_facts FROM PUBLIC, anon, authenticated;
