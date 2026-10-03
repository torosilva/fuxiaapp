-- Rollback of 20261007002100. Refuses if an online order was already shipped from a store.
DO $$ BEGIN IF EXISTS (SELECT 1 FROM f360.online_store_shipments) THEN RAISE EXCEPTION 'Hay envíos desde tienda registrados.'; END IF; END $$;
DROP FUNCTION IF EXISTS public.f360_online_store_shipment_sent(uuid);
DROP FUNCTION IF EXISTS public.f360_online_store_shipments(int);
DROP TRIGGER IF EXISTS reservations_enqueue_stock_sync ON f360.reservations;
DROP FUNCTION IF EXISTS f360.enqueue_stock_sync_reservation();
CREATE OR REPLACE FUNCTION f360.enqueue_stock_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, NEW.variant_id, 'Cambio de existencias'
    FROM f360.sales_targets t JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = NEW.variant_id
    WHERE t.active AND t.fulfillment_location_id = NEW.location_id
  ON CONFLICT (target_id, variant_id) DO UPDATE SET requested_at = clock_timestamp(), next_attempt_at = clock_timestamp(), reason = EXCLUDED.reason;
  RETURN NULL;
END $$;
CREATE OR REPLACE FUNCTION public.f360_ingest_woo_order(p_target_key text, p_delivery jsonb, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; prev f360.woo_orders;
  v_order bigint := (p_order->>'id')::bigint;
  v_status text := p_order->>'status';
  v_mod timestamptz := ((p_order->>'date_modified_gmt')::timestamp AT TIME ZONE 'UTC');
  v_delivery text := nullif(p_delivery->>'delivery_id', '');
  v_paid boolean; li jsonb; v_line bigint; v_var bigint; v_sku text; v_qty int; v_variant uuid; v_vsku text; v_product uuid; v_origin text;
  v_on_hand int; v_event uuid; v_outcome text; lines jsonb := '[]'; v_result text; v_sold_any boolean; r jsonb; v_label text; v_seen_refunds bigint[];
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
CREATE OR REPLACE FUNCTION f360.online_ats(p_variant_id uuid, p_location_id uuid) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = p_variant_id AND location_id = p_location_id), 0)
$$;
DROP TRIGGER IF EXISTS online_store_shipments_notify ON f360.online_store_shipments;
DROP FUNCTION IF EXISTS f360.notify_store_shipment();
DROP TABLE IF EXISTS f360.online_store_shipments;
DROP FUNCTION IF EXISTS f360.store_for_online(uuid, int);
DROP FUNCTION IF EXISTS f360.online_store_locations();
