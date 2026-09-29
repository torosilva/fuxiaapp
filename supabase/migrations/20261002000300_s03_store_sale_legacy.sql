-- S0.3 — Atomic in-store sale for LEGACY locations (P0-2, P0-4). STAGING. Additive; the legacy client path keeps
-- working during the compatibility window (its cutover S0.3c is a separate unit).
-- Decisions: D-E1 RPC only (no Edge Function) · D-X1 no public.inventory_events, no second ledger · D-P2 legacy price
-- (channel_inventory.price) recorded as price_source · D-PM payment method (+ optional reference, never card data) ·
-- D-S1 never negative · D-S2 self_sale = 0 loyalty, audited · D-R1 no referral bonus · Q7 loyalty only via loyalty_apply.
-- The server derives seller, location and price; the client sends ONLY {channel_inventory_id, quantity}, an optional
-- customer QR, the payment method and an idempotency key.
-- The f360-ledger branch (C3) is DORMANT: an f360 location is refused here.
-- Rollback: supabase/rollbacks/20261002000300_s03_store_sale_legacy.down.sql

-- ── Legacy tables: additive columns / constraints ───────────────────────────
ALTER TABLE public.offline_sales
  ADD COLUMN idempotency_key       uuid,
  ADD COLUMN seller_auth_user_id   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN location_id           uuid REFERENCES f360.locations(id) ON DELETE RESTRICT,
  ADD COLUMN session_id            uuid,
  ADD COLUMN payment_method        text CHECK (payment_method IN ('cash', 'card', 'transfer', 'other')),
  ADD COLUMN payment_reference     text CHECK (payment_reference IS NULL OR (length(payment_reference) <= 64 AND payment_reference !~ '[0-9]{12,}')),
  ADD COLUMN price_source          text,
  ADD COLUMN self_sale             boolean NOT NULL DEFAULT false,
  ADD COLUMN loyalty_transaction_id uuid,
  ADD COLUMN created_by_rpc        boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX offline_sales_idempotency_key_key ON public.offline_sales (idempotency_key) WHERE idempotency_key IS NOT NULL;
COMMENT ON COLUMN public.offline_sales.payment_reference IS 'Optional operator reference (e.g. terminal folio). Never card numbers: 12+ consecutive digits are refused.';

CREATE TABLE public.offline_sale_items (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id               uuid NOT NULL REFERENCES public.offline_sales(id) ON DELETE RESTRICT,
  line_no               integer NOT NULL,
  channel_inventory_id  uuid,                       -- no FK: legacy rows can be deleted; the snapshot survives
  sku                   text,
  product_name          text NOT NULL,
  size                  text,
  color                 text,
  quantity              integer NOT NULL CHECK (quantity > 0),
  unit_price            numeric(10,2) NOT NULL,
  line_total            numeric(12,2) NOT NULL,
  price_source          text NOT NULL,
  UNIQUE (sale_id, line_no)
);
ALTER TABLE public.offline_sale_items ENABLE ROW LEVEL SECURITY;   -- no policies: written/read only through definer RPCs / service
REVOKE ALL ON public.offline_sale_items FROM PUBLIC, anon, authenticated;
CREATE TRIGGER offline_sale_items_append_only BEFORE UPDATE OR DELETE ON public.offline_sale_items FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- never negative / never oversold on the legacy stock table (aggregate check on staging: 0 violating rows)
ALTER TABLE public.channel_inventory ADD CONSTRAINT channel_inventory_stock_sane CHECK (stock >= 0 AND sold >= 0 AND sold <= stock) NOT VALID;
ALTER TABLE public.channel_inventory VALIDATE CONSTRAINT channel_inventory_stock_sane;

-- ── The sale ────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_record_store_sale(p_token text, p_idempotency_key uuid, p_lines jsonb, p_payment_method text,
  p_payment_reference text DEFAULT NULL, p_customer_qr text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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
END $$;

-- ── Claim later: the customer's OWN session; customer = auth.uid(); atomic single claim ──
CREATE FUNCTION public.f360_claim_store_sale(p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); cust public.customers; card public.loyalty_cards; sale public.offline_sales; loy jsonb; lines jsonb;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Inicia sesión para reclamar tus puntos.' USING ERRCODE = 'insufficient_privilege'; END IF;
  SELECT * INTO cust FROM public.customers WHERE auth_user_id = uid;
  IF cust.id IS NULL THEN RAISE EXCEPTION 'Tu cuenta no tiene perfil de clienta.'; END IF;
  SELECT * INTO card FROM public.loyalty_cards WHERE customer_id = cust.id;
  IF card.id IS NULL THEN RAISE EXCEPTION 'Tu cuenta no tiene tarjeta de lealtad.'; END IF;
  -- only sales created by the RPC (new path); a code can be claimed exactly once (single atomic UPDATE)
  UPDATE public.offline_sales SET claimed_at = now(), customer_id = cust.id
    WHERE code = upper(btrim(p_code)) AND claimed_at IS NULL AND created_by_rpc
    RETURNING * INTO sale;
  IF sale.id IS NULL THEN RAISE EXCEPTION 'Código no válido o ya utilizado.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('channel_inventory_id', i.channel_inventory_id, 'sku', i.sku, 'product_name', i.product_name,
      'size', i.size, 'color', i.color, 'quantity', i.quantity, 'unit_price', i.unit_price) ORDER BY i.line_no), '[]') INTO lines
    FROM public.offline_sale_items i WHERE i.sale_id = sale.id;
  -- D-S2 is decided inside loyalty_apply: the actor is the SELLER of the sale; if she claims her own sale → 0 points
  loy := public.loyalty_apply(card.id, lines, sale.total, 'store', 'offline_sale', sale.id::text, 'offline_sale:' || sale.id,
    jsonb_build_object('type', 'claim', 'auth_user_id', sale.seller_auth_user_id, 'claimer_auth_user_id', uid, 'location_id', sale.location_id));
  UPDATE public.offline_sales SET points_earned = coalesce((loy->>'points')::int, 0), self_sale = coalesce((loy->>'self_sale')::boolean, false),
    loyalty_transaction_id = nullif(loy->>'transaction_id', '')::uuid WHERE id = sale.id;
  RETURN jsonb_build_object('ok', true, 'points', coalesce((loy->>'points')::int, 0), 'self_sale', coalesce((loy->>'self_sale')::boolean, false));
END $$;

-- ── One fact per sale for Customer 360 / Growth (C3 will UNION f360.store_sales here) ──
CREATE VIEW f360.store_sale_facts AS
  SELECT s.id AS sale_id, 'store_legacy' AS source, s.location_id, s.channel_id AS legacy_channel_id, s.seller_auth_user_id, s.customer_id,
         s.total, s.payment_method, s.price_source, s.self_sale, s.points_earned, s.claimed_at, s.created_at,
         (SELECT coalesce(sum(i.quantity), 0) FROM public.offline_sale_items i WHERE i.sale_id = s.id) AS units
  FROM public.offline_sales s WHERE s.created_by_rpc;
REVOKE ALL ON f360.store_sale_facts FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.f360_record_store_sale(text, uuid, jsonb, text, text, text), public.f360_claim_store_sale(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_record_store_sale(text, uuid, jsonb, text, text, text), public.f360_claim_store_sale(text) TO authenticated, service_role;
