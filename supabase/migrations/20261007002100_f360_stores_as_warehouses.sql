-- Fuxia 360 — stores are warehouses too, for the online store (STAGING). Decision: Mario 2026-10-03: "para nosotros las
-- tiendas también son bodegas… o el cliente se lo prueba en la tienda porque está en inventario o lo pide para envío;
-- tiene que ser lo más fácil para el usuario". Supersedes INVENTORY_MODEL "Woo México se alimenta solo de Bodega CDMX".
--   * Online stock (what Woo shows) = Bodega CDMX + every active selling STORE on the Fuxia 360 ledger (not in a count,
--     within its dates), minus pairs held for Gold customers. Bazaars are not included (temporary points of sale).
--   * A paid online order is taken from Bodega when it has the pair; otherwise from a store that has it free (lowest
--     sort first). The store gets a "ship this pair" notice (push to its team) and the shipment is listed for the team.
--   * Any change in a store's stock or a reservation re-sends that size to the store(s) online.
-- Rollback: supabase/rollbacks/20261007002100_f360_stores_as_warehouses.down.sql

CREATE FUNCTION f360.online_store_locations() RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT l.id FROM f360.locations l
  WHERE l.status = 'active' AND l.sellable AND l.type = 'store' AND l.ledger_authority = 'f360' AND NOT f360.location_in_cutover(l.id)
    AND (l.starts_on IS NULL OR l.starts_on <= current_date) AND (l.ends_on IS NULL OR l.ends_on >= current_date)
$$;

-- Same signature as before (every caller — push, reconcile, publisher — now sees Bodega + stores).
CREATE OR REPLACE FUNCTION f360.online_ats(p_variant_id uuid, p_location_id uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = p_variant_id AND location_id = p_location_id), 0)
       + coalesce((SELECT sum(greatest(0, b.on_hand - f360.reserved_qty(p_variant_id, b.location_id)))::int FROM f360.inventory_balances b
                   WHERE b.variant_id = p_variant_id AND b.location_id IN (SELECT f360.online_store_locations()) AND b.location_id <> p_location_id), 0)
$$;

-- The store that ships an online order when Bodega does not have it: a free pair (not held for a Gold customer).
CREATE FUNCTION f360.store_for_online(p_variant uuid, p_qty int) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT b.location_id FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id
  WHERE b.variant_id = p_variant AND b.location_id IN (SELECT f360.online_store_locations())
    AND b.on_hand - f360.reserved_qty(p_variant, b.location_id) >= p_qty
  ORDER BY l.sort, l.name LIMIT 1
$$;

CREATE TABLE f360.online_store_shipments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id     uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_order_id  bigint NOT NULL,
  woo_line_id   bigint NOT NULL,
  variant_id    uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  location_id   uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  quantity      int NOT NULL CHECK (quantity > 0),
  sale_event_id uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  status        text NOT NULL DEFAULT 'por_enviar' CHECK (status IN ('por_enviar', 'enviado')),
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  shipped_at    timestamptz, shipped_by text,
  UNIQUE (target_id, woo_order_id, woo_line_id)
);

CREATE FUNCTION f360.notify_store_shipment() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  INSERT INTO f360.push_outbox (auth_user_id, title, body, data)
    SELECT u, 'Pedido en línea · envíalo hoy',
           'Pedido #' || NEW.woo_order_id || ': ' || NEW.quantity || ' × ' || f360.variant_label(NEW.variant_id) || '. Prepáralo para envío.',
           jsonb_build_object('type', 'f360_online_shipment', 'shipment_id', NEW.id, 'location_id', NEW.location_id)
    FROM f360.location_team(NEW.location_id) u;
  BEGIN PERFORM f360.push_tick(); EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END $$;
CREATE TRIGGER online_store_shipments_notify AFTER INSERT ON f360.online_store_shipments FOR EACH ROW EXECUTE FUNCTION f360.notify_store_shipment();

-- Stock push queue: also when a store's balance changes, or a reservation opens/closes (it changes what is free).
CREATE OR REPLACE FUNCTION f360.enqueue_stock_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, NEW.variant_id, 'Cambio de existencias'
    FROM f360.sales_targets t JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = NEW.variant_id
    WHERE t.active AND (t.fulfillment_location_id = NEW.location_id OR NEW.location_id IN (SELECT f360.online_store_locations()))
  ON CONFLICT (target_id, variant_id) DO UPDATE SET requested_at = clock_timestamp(), next_attempt_at = clock_timestamp(), reason = EXCLUDED.reason;
  RETURN NULL;
END $$;
CREATE FUNCTION f360.enqueue_stock_sync_reservation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, NEW.variant_id, 'Apartado Gold'
    FROM f360.sales_targets t JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = NEW.variant_id WHERE t.active
  ON CONFLICT (target_id, variant_id) DO UPDATE SET requested_at = clock_timestamp(), next_attempt_at = clock_timestamp(), reason = EXCLUDED.reason;
  RETURN NULL;
END $$;
CREATE TRIGGER reservations_enqueue_stock_sync AFTER INSERT OR UPDATE OF status ON f360.reservations
  FOR EACH ROW EXECUTE FUNCTION f360.enqueue_stock_sync_reservation();

-- Team: online orders a store has to ship, and "ya se envió" (operator; the seller app can use the shift version later).
CREATE FUNCTION public.f360_online_store_shipments(p_days int DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'order', s.woo_order_id, 'store', l.name, 'label', f360.variant_label(s.variant_id),
      'quantity', s.quantity, 'status', s.status, 'created_at', s.created_at, 'shipped_at', s.shipped_at, 'shipped_by', s.shipped_by)
      ORDER BY (s.status = 'por_enviar') DESC, s.created_at DESC), '[]')
    FROM f360.online_store_shipments s JOIN f360.locations l ON l.id = s.location_id WHERE s.created_at > now() - make_interval(days => greatest(1, least(p_days, 365))));
END $$;
CREATE FUNCTION public.f360_online_store_shipment_sent(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; s f360.online_store_shipments;
BEGIN
  r := f360.require_role('operator');
  UPDATE f360.online_store_shipments SET status = 'enviado', shipped_at = clock_timestamp(), shipped_by = r.display_name
    WHERE id = p_id AND status = 'por_enviar' RETURNING * INTO s;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Ese envío no está pendiente.'; END IF;
  RETURN jsonb_build_object('id', s.id, 'status', s.status);
END $$;

-- ── Online order ingestion: unchanged from 20261007001900 except the marked 'store ships it' branch ──
CREATE OR REPLACE FUNCTION public.f360_ingest_woo_order(p_target_key text, p_delivery jsonb, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; prev f360.woo_orders;
  v_order bigint := (p_order->>'id')::bigint;
  v_status text := p_order->>'status';
  v_mod timestamptz := ((p_order->>'date_modified_gmt')::timestamp AT TIME ZONE 'UTC');
  v_delivery text := nullif(p_delivery->>'delivery_id', '');
  v_paid boolean; li jsonb; v_line bigint; v_var bigint; v_sku text; v_qty int; v_variant uuid; v_vsku text; v_product uuid; v_origin text;
  v_on_hand int; v_event uuid; v_store uuid; v_outcome text; lines jsonb := '[]'; v_result text; v_sold_any boolean; r jsonb; v_label text; v_seen_refunds bigint[];
BEGIN
  t := f360.target_by_key(p_target_key);
  IF v_order IS NULL OR v_status IS NULL OR v_mod IS NULL THEN RAISE EXCEPTION 'Pedido incompleto.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(t.id::text || ':' || v_order, 0));   -- same order: one at a time
  -- Woo's X-WC-Webhook-Delivery-ID is hash(webhook id + current SECOND): two orders delivered by the same webhook in the
  -- same second share it. So a delivery is a duplicate only for the same order AND topic (order version + line keys
  -- remain the real idempotency guarantees).
  IF v_delivery IS NOT NULL AND EXISTS (SELECT 1 FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.delivery_id = v_delivery
      AND d.woo_order_id = v_order AND d.topic IS NOT DISTINCT FROM (p_delivery->>'topic')
      AND d.result NOT IN ('error', 'rejected_signature')) THEN
    INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, woo_order_id, woo_status, woo_modified_at, result)
      VALUES (t.id, v_delivery, p_delivery->>'topic', v_order, v_status, v_mod, 'duplicate_delivery');
    RETURN jsonb_build_object('result', 'duplicate_delivery', 'order_id', v_order);
  END IF;

  SELECT * INTO prev FROM f360.woo_orders WHERE target_id = t.id AND woo_order_id = v_order FOR UPDATE;
  IF prev.woo_order_id IS NOT NULL AND v_mod < prev.woo_modified_at THEN
    v_result := 'stale';
  ELSIF prev.woo_order_id IS NOT NULL AND v_mod = prev.woo_modified_at AND v_status = prev.woo_status
        AND coalesce((SELECT array_agg((x->>'id')::bigint ORDER BY (x->>'id')::bigint) FROM jsonb_array_elements(p_order->'refunds') x), '{}') <@ prev.refund_ids THEN
    v_result := 'duplicate';
  END IF;
  IF v_result IS NOT NULL THEN
    INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, woo_order_id, woo_status, woo_modified_at, result, detail)
      VALUES (t.id, v_delivery, p_delivery->>'topic', v_order, v_status, v_mod, v_result,
              CASE WHEN v_result = 'stale' THEN jsonb_build_object('current_status', prev.woo_status, 'current_modified', prev.woo_modified_at) END);
    RETURN jsonb_build_object('result', v_result, 'order_id', v_order);
  END IF;

  INSERT INTO f360.woo_orders (target_id, woo_order_id, woo_status, woo_modified_at, currency)
    VALUES (t.id, v_order, v_status, v_mod, p_order->>'currency')
    ON CONFLICT (target_id, woo_order_id) DO UPDATE SET woo_status = EXCLUDED.woo_status, woo_modified_at = EXCLUDED.woo_modified_at, updated_at = now();

  v_paid := v_status IN ('processing', 'completed');
  IF v_paid THEN
    FOR li IN SELECT * FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) LOOP
      v_line := (li->>'id')::bigint; v_var := nullif(li->>'variation_id', '')::bigint; v_sku := nullif(li->>'sku', ''); v_qty := (li->>'quantity')::int;
      IF v_line IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
      IF EXISTS (SELECT 1 FROM f360.woo_order_lines WHERE target_id = t.id AND woo_order_id = v_order AND woo_line_id = v_line) THEN
        lines := lines || jsonb_build_object('line', v_line, 'sku', v_sku, 'outcome', 'already_recorded');
        CONTINUE;   -- each line affects stock at most once, ever
      END IF;
      v_variant := NULL; v_event := NULL; v_product := NULL; v_origin := NULL;
      SELECT vl.variant_id, v.sku, v.product_id, vl.origin INTO v_variant, v_vsku, v_product, v_origin FROM f360.woo_variant_links vl
        JOIN f360.product_variants v ON v.id = vl.variant_id WHERE vl.target_id = t.id AND vl.woo_variation_id = v_var;
      IF v_variant IS NULL THEN   -- a store product per colour that was merged into one (20261007001900): still the same pair
        SELECT rl.variant_id, v.sku, v.product_id, 'legacy_adopted' INTO v_variant, v_vsku, v_product, v_origin FROM f360.retired_woo_links rl
          JOIN f360.product_variants v ON v.id = rl.variant_id WHERE rl.target_id = t.id AND rl.woo_variation_id = v_var;
      END IF;
      IF v_variant IS NULL THEN
        IF coalesce(v_sku, '') LIKE 'F360-%' OR EXISTS (SELECT 1 FROM f360.woo_product_links WHERE target_id = t.id AND woo_product_id = (li->>'product_id')::bigint)
           -- D2 change 1: a Woo product that F360 adopted, but this variation was not (e.g. "any colour", blocked for cutover)
           OR EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE target_id = t.id AND origin = 'legacy_adopted' AND woo_product_id = (li->>'product_id')::bigint) THEN
          v_outcome := 'unknown_sku';
          PERFORM f360.open_exception(t.id, 'unknown_sku', 'unknown_sku:' || v_order || ':' || v_line,
            format('Venta en línea de un artículo que Fuxia 360 no reconoce (SKU %s, variación Woo %s, pedido #%s). No se descontó inventario.', coalesce(v_sku, 'sin SKU'), coalesce(v_var::text, '—'), v_order),
            jsonb_build_object('sku', v_sku, 'woo_variation_id', v_var, 'quantity', v_qty), NULL, NULL, v_order);
        ELSE
          v_outcome := 'legacy';   -- product not managed by Fuxia 360: ignored on purpose (legacy catalog)
        END IF;
      -- D2 change 2: only F360-published links compare SKUs. A legacy link is resolved by woo_variation_id alone.
      ELSIF v_origin = 'f360_published' AND v_sku IS DISTINCT FROM v_vsku THEN
        v_outcome := 'sku_mismatch';
        PERFORM f360.open_exception(t.id, 'sku_mismatch', 'sku_mismatch:' || v_order || ':' || v_line,
          format('El pedido #%s trae el SKU %s pero esa variación en Fuxia 360 es %s. No se descontó inventario.', v_order, coalesce(v_sku, '—'), v_vsku),
          jsonb_build_object('sku', v_sku, 'expected', v_vsku, 'quantity', v_qty), v_product, v_variant, v_order);
      ELSE
        -- lock this variant's Bodega balance: concurrent sales of the last pair are serialized here
        INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) VALUES (v_variant, t.fulfillment_location_id, 0)
          ON CONFLICT (variant_id, location_id) DO NOTHING;
        SELECT on_hand INTO v_on_hand FROM f360.inventory_balances WHERE variant_id = v_variant AND location_id = t.fulfillment_location_id FOR UPDATE;
        v_label := f360.variant_label(v_variant);
        IF v_on_hand >= v_qty THEN
          INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
            VALUES ('SALE', md5('woo-sale:' || t.key || ':' || v_order || ':' || v_line)::uuid, NULL, 'Tienda en línea', 'system',
                    'Pedido #' || v_order, 'woo_order', t.key || ':' || v_order)
            RETURNING id INTO v_event;
          INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity)
            VALUES (v_event, v_variant, t.fulfillment_location_id, NULL, v_qty);
          UPDATE f360.inventory_balances SET on_hand = on_hand - v_qty, last_event_id = v_event, updated_at = now()
            WHERE variant_id = v_variant AND location_id = t.fulfillment_location_id;
          -- Woo already discounted this sale itself: what Fuxia expects Woo to show drops by the same amount.
          UPDATE f360.woo_variant_links SET last_pushed_stock = greatest(0, coalesce(last_pushed_stock, 0) - v_qty)
            WHERE target_id = t.id AND variant_id = v_variant;
          v_outcome := 'sold';
        ELSIF f360.store_for_online(v_variant, v_qty) IS NOT NULL THEN
          -- Stores are warehouses too (Mario 2026-10-03): not enough in Bodega, but a store has the pair free → it is sold
          -- from that store (never a pair held for a Gold customer) and the store is told to ship it.
          v_store := f360.store_for_online(v_variant, v_qty);
          INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note, business_reference_type, business_reference_id)
            VALUES ('SALE', md5('woo-sale:' || t.key || ':' || v_order || ':' || v_line)::uuid, NULL, 'Tienda en línea', 'system',
                    'Pedido #' || v_order || ' · se envía desde ' || (SELECT name FROM f360.locations WHERE id = v_store), 'woo_order', t.key || ':' || v_order)
            RETURNING id INTO v_event;
          PERFORM f360.ledger_move(v_event, v_variant, v_store, NULL, v_qty);
          UPDATE f360.woo_variant_links SET last_pushed_stock = greatest(0, coalesce(last_pushed_stock, 0) - v_qty)
            WHERE target_id = t.id AND variant_id = v_variant;
          INSERT INTO f360.online_store_shipments (target_id, woo_order_id, woo_line_id, variant_id, location_id, quantity, sale_event_id)
            VALUES (t.id, v_order, v_line, v_variant, v_store, v_qty, v_event) ON CONFLICT DO NOTHING;
          v_outcome := 'sold';
        ELSIF (SELECT make_to_order FROM f360.products WHERE id = v_product) THEN
          -- Sobre pedido (Mario 2026-10-03): the size had no stock but the model can be made to order. Nothing moves;
          -- the pair is queued to be made/sourced and shipped in 5–7 business days. Never negative.
          v_outcome := 'sobre_pedido';
          INSERT INTO f360.made_to_order (target_id, woo_order_id, woo_line_id, variant_id, quantity, on_hand_at_order)
            VALUES (t.id, v_order, v_line, v_variant, v_qty, v_on_hand) ON CONFLICT DO NOTHING;
        ELSE
          v_outcome := 'oversold';   -- never negative: record the alert, move nothing
          PERFORM f360.open_exception(t.id, 'oversell', 'oversell:' || v_order || ':' || v_line,
            format('Venta en línea sin existencia: %s — pedido #%s pidió %s, Bodega CDMX tenía %s. Hay que decidir cómo surtirlo.', v_label, v_order, v_qty, v_on_hand),
            jsonb_build_object('requested', v_qty, 'on_hand', v_on_hand, 'sku', v_sku), v_product, v_variant, v_order);
        END IF;
      END IF;
      INSERT INTO f360.woo_order_lines (target_id, woo_order_id, woo_line_id, woo_product_id, woo_variation_id, sku, quantity, variant_id, outcome, sale_event_id)
        VALUES (t.id, v_order, v_line, (li->>'product_id')::bigint, v_var, v_sku, v_qty, v_variant, v_outcome, v_event);
      lines := lines || jsonb_build_object('line', v_line, 'sku', v_sku, 'qty', v_qty, 'outcome', v_outcome);
    END LOOP;
  END IF;

  -- Cancellation / refund AFTER a sale: DW4 policy is not decided → record it, never restock automatically.
  SELECT EXISTS (SELECT 1 FROM f360.woo_order_lines WHERE target_id = t.id AND woo_order_id = v_order AND outcome = 'sold') INTO v_sold_any;
  IF v_sold_any AND v_status IN ('cancelled', 'refunded', 'failed') THEN
    PERFORM f360.open_exception(t.id, CASE WHEN v_status = 'refunded' THEN 'refund_after_sale' ELSE 'cancel_after_sale' END,
      v_status || ':' || v_order,
      format('El pedido #%s pasó a "%s" después de registrarse la venta. No se regresó inventario: falta la política de cancelaciones/devoluciones (decisión pendiente de Mario, DW4).', v_order, v_status),
      jsonb_build_object('status', v_status), NULL, NULL, v_order);
  END IF;
  IF v_sold_any THEN
    SELECT refund_ids INTO v_seen_refunds FROM f360.woo_orders WHERE target_id = t.id AND woo_order_id = v_order;
    FOR r IN SELECT x FROM jsonb_array_elements(coalesce(p_order->'refunds', '[]')) x LOOP
      IF NOT ((r->>'id')::bigint = ANY (v_seen_refunds)) THEN
        PERFORM f360.open_exception(t.id, 'refund_after_sale', 'refund:' || v_order || ':' || (r->>'id'),
          format('El pedido #%s tiene un reembolso (#%s). Reembolso ≠ devolución física: no se regresó inventario (decisión pendiente, DW4).', v_order, r->>'id'),
          r, NULL, NULL, v_order);
      END IF;
    END LOOP;
  END IF;
  UPDATE f360.woo_orders SET refund_ids = coalesce((SELECT array_agg(DISTINCT (x->>'id')::bigint) FROM jsonb_array_elements(p_order->'refunds') x), '{}') || refund_ids
    WHERE target_id = t.id AND woo_order_id = v_order;

  v_result := CASE WHEN v_paid THEN 'applied' ELSE 'not_paid' END;
  INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, woo_order_id, woo_status, woo_modified_at, result, detail)
    VALUES (t.id, v_delivery, p_delivery->>'topic', v_order, v_status, v_mod, v_result, jsonb_build_object('lines', lines));
  RETURN jsonb_build_object('result', v_result, 'order_id', v_order, 'status', v_status, 'lines', lines);
END $$;

-- Re-send every linked size once so the store shows Bodega + stores now.
INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
  SELECT vl.target_id, vl.variant_id, 'Tiendas como bodega' FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id AND t.active
ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = EXCLUDED.reason;

REVOKE ALL ON f360.online_store_shipments FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.online_store_shipments TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_online_store_shipments(int), public.f360_online_store_shipment_sent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_online_store_shipments(int), public.f360_online_store_shipment_sent(uuid) TO authenticated, service_role;
