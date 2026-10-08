-- Fuxia 360 · pase D7 (2026-10-08) — online orders reach Fuxia 360 in production (same as migration 20261012001100) + turn on the
-- order path only: orders_mode='on', cutover mark orders_since_id=5351 (every order up to the test #5351 is ignored).
-- active / stock_sync_mode / storefront_enabled / stock_policy are NOT touched (no stock is pushed to the store).
-- Rehearsed in production with ROLLBACK 2026-10-08: Bodega sale, store sale + shipment task, sobre pedido, before_cutover, not_paid, duplicate.
-- Apply ONLY with scripts/f360/prod_sql.sh. Rollback: supabase/rollbacks/20261012001100_f360_orders_production.down.sql
BEGIN;
-- Fuxia 360 · online orders reach Fuxia 360 in PRODUCTION (Mario 2026-10-08: "yes sync please it is very important").
-- A paid order on fuxiaballerinas.com did not appear in Fuxia 360 and its pair kept counting as available: the order functions
-- refuse every production channel (f360.target_by_key, built for staging). This turns on ONLY the order path, nothing else:
--   · sales_targets.orders_mode ('off' | 'on', default off) + orders_since_id (cutover mark: orders up to that id are recorded
--     as 'before_cutover' and never move inventory — no double deduction of pairs sold before the opening count);
--   · f360.orders_target(key): production only when orders_mode = 'on' (does NOT need `active`, which would also expose the
--     catalog, fill the stock queue and change online scarcity); every other channel exactly as before (target_by_key);
--   · used ONLY by f360_ingest_woo_order, f360_record_webhook_rejection, f360_capture_order_economics, f360_commerce_run_begin
--     (taken from the live definitions; only the gate changes). Stock push to Woo stays off (stock_sync_mode untouched);
--   · ingestion also recognises an old store product not merged yet through Carolina's confirmed homologation (legacy_woo_map).
-- What a paid order does (unchanged rules): Bodega CDMX if it has the pair, else a store that has it free (sale from that store +
-- "Envíos en línea" task, Mario 2026-10-03), else sobre pedido (made_to_order) or an oversell alert. Never negative; each line
-- once; cancellations/refunds after a sale open an exception (no automatic restock, DW4).
-- Rollback: supabase/rollbacks/20261012001100_f360_orders_production.down.sql (and pause the Woo webhooks).
ALTER TABLE f360.sales_targets ADD COLUMN orders_mode text NOT NULL DEFAULT 'off' CHECK (orders_mode IN ('off', 'on')),
  ADD COLUMN orders_since_id bigint;

CREATE FUNCTION f360.orders_target(p_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $f$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda % no configurada.', p_key; END IF;
  IF t.is_production THEN
    IF t.orders_mode <> 'on' THEN RAISE EXCEPTION 'Los pedidos de la tienda de producción no están encendidos.'; END IF;
    RETURN t;
  END IF;
  RETURN f360.target_by_key(p_key);   -- every non-production channel: exactly as before
END $f$;
REVOKE ALL ON FUNCTION f360.orders_target(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.f360_ingest_woo_order(p_target_key text, p_delivery jsonb, p_order jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  t f360.sales_targets; prev f360.woo_orders;
  v_order bigint := (p_order->>'id')::bigint;
  v_status text := p_order->>'status';
  v_mod timestamptz := ((p_order->>'date_modified_gmt')::timestamp AT TIME ZONE 'UTC');
  v_delivery text := nullif(p_delivery->>'delivery_id', '');
  v_paid boolean; li jsonb; v_line bigint; v_var bigint; v_sku text; v_qty int; v_variant uuid; v_vsku text; v_product uuid; v_origin text;
  v_on_hand int; v_event uuid; v_store uuid; v_outcome text; lines jsonb := '[]'; v_result text; v_sold_any boolean; r jsonb; v_label text; v_seen_refunds bigint[];
BEGIN
  t := f360.orders_target(p_target_key);
  IF v_order IS NULL OR v_status IS NULL OR v_mod IS NULL THEN RAISE EXCEPTION 'Pedido incompleto.'; END IF;
  -- Cutover mark (2026-10-08): orders up to this id were placed before Fuxia 360 recorded online sales (and before the opening
  -- count). Recorded, never applied: a later processing→completed of an old order can never deduct a pair a second time.
  IF t.orders_since_id IS NOT NULL AND v_order <= t.orders_since_id THEN
    INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, woo_order_id, woo_status, woo_modified_at, result)
      VALUES (t.id, v_delivery, p_delivery->>'topic', v_order, v_status, v_mod, 'before_cutover');
    RETURN jsonb_build_object('result', 'before_cutover', 'order_id', v_order);
  END IF;
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
  -- TEST store (Mario 2026-10-05): its orders are recorded so the flow can be tested, but they never touch real inventory,
  -- never ask a store to ship and never queue a pair to be made.
  IF v_paid AND t.is_test THEN
    FOR li IN SELECT * FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) LOOP
      v_line := (li->>'id')::bigint; v_var := nullif(li->>'variation_id', '')::bigint; v_sku := nullif(li->>'sku', ''); v_qty := (li->>'quantity')::int;
      IF v_line IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;
      v_variant := NULL;
      SELECT vl.variant_id INTO v_variant FROM f360.woo_variant_links vl WHERE vl.target_id = t.id AND vl.woo_variation_id = v_var;
      IF v_variant IS NULL THEN SELECT rl.variant_id INTO v_variant FROM f360.retired_woo_links rl WHERE rl.target_id = t.id AND rl.woo_variation_id = v_var; END IF;
      INSERT INTO f360.woo_order_lines (target_id, woo_order_id, woo_line_id, woo_product_id, woo_variation_id, sku, quantity, variant_id, outcome, sale_event_id)
        VALUES (t.id, v_order, v_line, (li->>'product_id')::bigint, v_var, v_sku, v_qty, v_variant, 'test', NULL)
        ON CONFLICT DO NOTHING;
      lines := lines || jsonb_build_object('line', v_line, 'sku', v_sku, 'qty', v_qty, 'outcome', 'test');
    END LOOP;
    v_paid := false;   -- skip the real sale path below
    v_result := 'test_order';
  END IF;
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
      IF v_variant IS NULL THEN   -- an old store product not merged yet: Carolina's confirmed homologation in this channel (2026-10-08)
        SELECT m.confirmed_variant_id, v.sku, v.product_id, 'legacy_adopted' INTO v_variant, v_vsku, v_product, v_origin FROM f360.legacy_woo_map m
          JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE m.target_id = t.id AND m.woo_variation_id = v_var AND m.status = 'confirmado';
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

  v_result := CASE WHEN v_result = 'test_order' THEN 'test_order' WHEN v_paid THEN 'applied' ELSE 'not_paid' END;
  INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, woo_order_id, woo_status, woo_modified_at, result, detail)
    VALUES (t.id, v_delivery, p_delivery->>'topic', v_order, v_status, v_mod, v_result, jsonb_build_object('lines', lines));
  RETURN jsonb_build_object('result', v_result, 'order_id', v_order, 'status', v_status, 'lines', lines);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_record_webhook_rejection(p_target_key text, p_delivery jsonb, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets;
BEGIN
  t := f360.orders_target(p_target_key);
  INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, result, detail)
    VALUES (t.id, left(p_delivery->>'delivery_id', 100), left(p_delivery->>'topic', 100), 'rejected_signature', jsonb_build_object('reason', left(p_reason, 200)));
  PERFORM f360.open_exception(t.id, 'webhook_rejected', 'webhook_rejected',
    'Llegaron avisos de la tienda con firma inválida y se rechazaron. Si se repite, revisar el secreto del webhook.', jsonb_build_object('reason', left(p_reason, 200)));
END $function$;

CREATE OR REPLACE FUNCTION public.f360_capture_order_economics(p_target_key text, p_order jsonb, p_via text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE
  t f360.sales_targets; prev f360.commerce_woo_orders;
  v_order bigint := nullif(p_order->>'id', '')::bigint;
  v_status text := nullif(p_order->>'status', '');
  v_mod timestamptz := f360.commerce_ts(p_order->>'date_modified_gmt');
  v_currency text := upper(nullif(p_order->>'currency', ''));
  v_paid_at timestamptz := f360.commerce_ts(p_order->>'date_paid_gmt');
  v_hash text; v_result text; v_ever boolean; v_class text; v_market text; v_path_market text; v_entry text;
  li jsonb; rf jsonb; a jsonb; v_units int := 0; v_lines int := 0; v_sub numeric := 0; v_tot numeric := 0; v_refunds int := 0; v_attr boolean := false;
BEGIN
  IF p_via NOT IN ('webhook', 'poll', 'backfill', 'test') THEN RAISE EXCEPTION 'Origen de captura no válido.'; END IF;
  t := f360.orders_target(p_target_key);                       -- refuses unknown / inactive / production targets
  IF v_order IS NULL OR v_status IS NULL OR v_mod IS NULL OR v_currency IS NULL THEN RAISE EXCEPTION 'Pedido incompleto.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('commerce:' || t.id::text || ':' || v_order, 0));

  FOR li IN SELECT * FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) LOOP
    v_lines := v_lines + 1; v_units := v_units + coalesce((li->>'quantity')::int, 0);
    v_sub := v_sub + f360.commerce_amount(li, 'subtotal'); v_tot := v_tot + f360.commerce_amount(li, 'total');
  END LOOP;
  -- the hash covers every economic field (not refunds/attribution, which have their own idempotent paths)
  v_hash := md5(jsonb_build_object('s', v_status, 'p', p_order->'date_paid_gmt', 'c', p_order->'date_completed_gmt', 'cur', v_currency,
    'a', jsonb_build_array(p_order->'discount_total', p_order->'discount_tax', p_order->'shipping_total', p_order->'shipping_tax', p_order->'cart_tax',
                           p_order->'fees_total', p_order->'fees_tax', p_order->'total_tax', p_order->'total', p_order->'payment_method',
                           p_order->'woo_customer_id', p_order->'billing_country', p_order->'coupon_count'),
    'l', coalesce(p_order->'line_items', '[]'))::text);

  SELECT * INTO prev FROM f360.commerce_woo_orders WHERE target_id = t.id AND woo_order_id = v_order FOR UPDATE;
  v_ever := coalesce(prev.ever_paid, false) OR v_paid_at IS NOT NULL OR v_status IN ('processing', 'completed', 'refunded');
  v_class := f360.commerce_status_class(v_status, v_ever);
  v_market := f360.commerce_market(v_currency);
  v_entry := nullif(p_order->'attribution'->>'session_entry_path', '');
  v_path_market := CASE WHEN v_entry ~ '^/co(/|$)' THEN 'CO' WHEN v_entry ~ '^/mx(/|$)' THEN 'MX' END;

  IF prev.woo_order_id IS NOT NULL AND v_mod < prev.woo_modified_at THEN
    v_result := 'stale';                                         -- an older version never overwrites a newer one
  ELSIF prev.woo_order_id IS NOT NULL AND prev.economics_hash = v_hash THEN
    v_result := 'unchanged';
    UPDATE f360.commerce_woo_orders SET woo_modified_at = greatest(woo_modified_at, v_mod), last_captured_via = p_via
      WHERE target_id = t.id AND woo_order_id = v_order;
  ELSE
    v_result := CASE WHEN prev.woo_order_id IS NULL THEN 'inserted' ELSE 'updated' END;
    INSERT INTO f360.commerce_woo_orders AS o (target_id, woo_order_id, woo_status, woo_modified_at, economics_hash, created_via, business_origin,
        woo_created_at, paid_at, completed_at, ever_paid, first_paid_at, currency, prices_include_tax,
        items_subtotal, discount_total, discount_tax, items_total, cart_tax, shipping_total, shipping_tax, fees_total, fees_tax, total_tax, order_total,
        units, line_count, coupon_count, paid_items_total, paid_order_total, payment_method, payment_category, woo_customer_id, billing_country,
        market, market_source, market_conflict, first_captured_via, last_captured_via)
      VALUES (t.id, v_order, v_status, v_mod, v_hash, nullif(p_order->>'created_via', ''), f360.commerce_business_origin(nullif(p_order->>'created_via', '')),
        f360.commerce_ts(p_order->>'date_created_gmt'), v_paid_at, f360.commerce_ts(p_order->>'date_completed_gmt'), v_ever,
        CASE WHEN v_ever THEN coalesce(v_paid_at, f360.commerce_ts(p_order->>'date_created_gmt')) END, v_currency, (p_order->>'prices_include_tax')::boolean,
        v_sub, f360.commerce_amount(p_order, 'discount_total'), f360.commerce_amount(p_order, 'discount_tax'), v_tot,
        f360.commerce_amount(p_order, 'cart_tax'), f360.commerce_amount(p_order, 'shipping_total'), f360.commerce_amount(p_order, 'shipping_tax'),
        f360.commerce_amount(p_order, 'fees_total'), f360.commerce_amount(p_order, 'fees_tax'), f360.commerce_amount(p_order, 'total_tax'),
        f360.commerce_amount(p_order, 'total'), v_units, v_lines, coalesce((p_order->>'coupon_count')::int, 0),
        CASE WHEN v_class = 'countable' THEN v_tot END, CASE WHEN v_class = 'countable' THEN f360.commerce_amount(p_order, 'total') END,
        nullif(p_order->>'payment_method', ''), f360.commerce_payment_category(p_order->>'payment_method'),
        nullif(nullif(p_order->>'woo_customer_id', ''), '0')::bigint, upper(nullif(p_order->>'billing_country', '')),
        v_market, 'currency', v_path_market IS NOT NULL AND v_path_market <> v_market, p_via, p_via)
    ON CONFLICT (target_id, woo_order_id) DO UPDATE SET
      woo_status = EXCLUDED.woo_status, woo_modified_at = EXCLUDED.woo_modified_at, economics_hash = EXCLUDED.economics_hash,
      -- created_via / business_origin are immutable: the first capture wins
      paid_at = EXCLUDED.paid_at, completed_at = EXCLUDED.completed_at, ever_paid = EXCLUDED.ever_paid,
      first_paid_at = coalesce(o.first_paid_at, EXCLUDED.first_paid_at), currency = EXCLUDED.currency, prices_include_tax = EXCLUDED.prices_include_tax,
      items_subtotal = EXCLUDED.items_subtotal, discount_total = EXCLUDED.discount_total, discount_tax = EXCLUDED.discount_tax, items_total = EXCLUDED.items_total,
      cart_tax = EXCLUDED.cart_tax, shipping_total = EXCLUDED.shipping_total, shipping_tax = EXCLUDED.shipping_tax, fees_total = EXCLUDED.fees_total,
      fees_tax = EXCLUDED.fees_tax, total_tax = EXCLUDED.total_tax, order_total = EXCLUDED.order_total, units = EXCLUDED.units, line_count = EXCLUDED.line_count,
      coupon_count = EXCLUDED.coupon_count,
      paid_items_total = coalesce(EXCLUDED.paid_items_total, o.paid_items_total), paid_order_total = coalesce(EXCLUDED.paid_order_total, o.paid_order_total),
      payment_method = EXCLUDED.payment_method, payment_category = EXCLUDED.payment_category, woo_customer_id = EXCLUDED.woo_customer_id,
      billing_country = EXCLUDED.billing_country, market = EXCLUDED.market, market_source = EXCLUDED.market_source, market_conflict = EXCLUDED.market_conflict,
      last_captured_via = EXCLUDED.last_captured_via, last_changed_at = clock_timestamp();
    DELETE FROM f360.commerce_woo_order_lines WHERE target_id = t.id AND woo_order_id = v_order;
    INSERT INTO f360.commerce_woo_order_lines (target_id, woo_order_id, woo_line_id, woo_product_id, woo_variation_id, sku, quantity,
        subtotal, subtotal_tax, total, total_tax, list_price_hint, list_price_source)
      SELECT t.id, v_order, (x->>'id')::bigint, nullif(nullif(x->>'product_id', ''), '0')::bigint, nullif(nullif(x->>'variation_id', ''), '0')::bigint,
             nullif(x->>'sku', ''), coalesce((x->>'quantity')::int, 0), f360.commerce_amount(x, 'subtotal'), f360.commerce_amount(x, 'subtotal_tax'),
             f360.commerce_amount(x, 'total'), f360.commerce_amount(x, 'total_tax'),
             nullif(x->>'list_price_hint', '')::numeric, nullif(x->>'list_price_source', '')
      FROM jsonb_array_elements(coalesce(p_order->'line_items', '[]')) x WHERE nullif(x->>'id', '') IS NOT NULL;
    IF prev.woo_order_id IS NULL OR prev.woo_status IS DISTINCT FROM v_status THEN
      INSERT INTO f360.commerce_woo_status_log (target_id, woo_order_id, from_status, to_status, woo_modified_at, via)
        VALUES (t.id, v_order, prev.woo_status, v_status, v_mod, p_via);
    END IF;
  END IF;

  -- Refunds: independent and idempotent by refund id, whatever the order version. A detailed refund is never
  -- downgraded to header-only. When this payload is the current version, refunds Woo no longer lists are marked removed.
  FOR rf IN SELECT * FROM jsonb_array_elements(coalesce(p_order->'refunds', '[]')) LOOP
    CONTINUE WHEN nullif(rf->>'id', '') IS NULL;
    v_refunds := v_refunds + 1;
    INSERT INTO f360.commerce_woo_refunds AS r (target_id, woo_order_id, woo_refund_id, amount, currency, refunded_at, detail_status,
        product_amount, shipping_amount, tax_amount, lines, provenance)
      VALUES (t.id, v_order, (rf->>'id')::bigint, abs(f360.commerce_amount(rf, 'amount')), v_currency, f360.commerce_ts(rf->>'created_at'),
        CASE WHEN (rf->>'detail')::boolean THEN 'detailed' ELSE 'header_only' END,
        CASE WHEN (rf->>'detail')::boolean THEN abs(f360.commerce_amount(rf, 'product_amount')) END,
        CASE WHEN (rf->>'detail')::boolean THEN abs(f360.commerce_amount(rf, 'shipping_amount')) END,
        CASE WHEN (rf->>'detail')::boolean THEN abs(f360.commerce_amount(rf, 'tax_amount')) END,
        CASE WHEN (rf->>'detail')::boolean THEN rf->'lines' END,
        CASE WHEN p_via = 'test' THEN 'test' WHEN (rf->>'detail')::boolean THEN 'woo_refunds_endpoint' ELSE 'woo_order_refunds_array' END)
    ON CONFLICT (target_id, woo_order_id, woo_refund_id) DO UPDATE SET
      amount = EXCLUDED.amount,
      refunded_at = coalesce(EXCLUDED.refunded_at, r.refunded_at),
      detail_status = CASE WHEN r.detail_status = 'detailed' THEN 'detailed' ELSE EXCLUDED.detail_status END,
      product_amount = CASE WHEN EXCLUDED.detail_status = 'detailed' THEN EXCLUDED.product_amount ELSE r.product_amount END,
      shipping_amount = CASE WHEN EXCLUDED.detail_status = 'detailed' THEN EXCLUDED.shipping_amount ELSE r.shipping_amount END,
      tax_amount = CASE WHEN EXCLUDED.detail_status = 'detailed' THEN EXCLUDED.tax_amount ELSE r.tax_amount END,
      lines = CASE WHEN EXCLUDED.detail_status = 'detailed' THEN EXCLUDED.lines ELSE r.lines END,
      provenance = CASE WHEN EXCLUDED.detail_status = 'detailed' THEN EXCLUDED.provenance ELSE r.provenance END,
      removed_at = NULL, updated_at = clock_timestamp();
  END LOOP;
  IF v_result IN ('inserted', 'updated', 'unchanged') THEN
    UPDATE f360.commerce_woo_refunds SET removed_at = clock_timestamp(), updated_at = clock_timestamp()
      WHERE target_id = t.id AND woo_order_id = v_order AND removed_at IS NULL
        AND woo_refund_id NOT IN (SELECT (x->>'id')::bigint FROM jsonb_array_elements(coalesce(p_order->'refunds', '[]')) x WHERE nullif(x->>'id', '') IS NOT NULL);
  END IF;

  -- Attribution: first capture wins (later wp-admin edits add an "admin" source and must not rewrite history).
  a := p_order->'attribution';
  IF jsonb_typeof(a) = 'object' AND v_result <> 'stale' THEN
    INSERT INTO f360.commerce_woo_attribution (target_id, woo_order_id, provenance, model, source_type, utm_source, utm_medium, utm_campaign,
        utm_content, utm_term, utm_id, referrer_host, session_entry_path, session_start_at, session_pages, session_count, device_type, browser_class, os_class)
      VALUES (t.id, v_order, 'first_party_observed', 'woo_order_attribution_last_click_session',
        left(nullif(a->>'source_type', ''), 40), left(nullif(a->>'utm_source', ''), 200), left(nullif(a->>'utm_medium', ''), 200),
        left(nullif(a->>'utm_campaign', ''), 200), left(nullif(a->>'utm_content', ''), 200), left(nullif(a->>'utm_term', ''), 200), left(nullif(a->>'utm_id', ''), 200),
        left(nullif(a->>'referrer_host', ''), 200), left(v_entry, 300), f360.commerce_ts(a->>'session_start_at'),
        nullif(a->>'session_pages', '')::int, nullif(a->>'session_count', '')::int, left(nullif(a->>'device_type', ''), 20),
        left(nullif(a->>'browser_class', ''), 30), left(nullif(a->>'os_class', ''), 20))
      ON CONFLICT (target_id, woo_order_id) DO NOTHING;
    v_attr := FOUND;
  END IF;

  RETURN jsonb_build_object('result', v_result, 'order_id', v_order, 'status_class', v_class, 'refunds', v_refunds, 'attribution_captured', v_attr);
END $function$;

CREATE OR REPLACE FUNCTION public.f360_commerce_run_begin(p_target_key text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE t f360.sales_targets; s f360.commerce_sync_state; v_id bigint; v_after timestamptz;
BEGIN
  t := f360.orders_target(p_target_key);
  INSERT INTO f360.commerce_sync_state (target_id) VALUES (t.id) ON CONFLICT (target_id) DO NOTHING;
  SELECT * INTO s FROM f360.commerce_sync_state WHERE target_id = t.id FOR UPDATE;
  -- poll: from the cursor with a 10-minute overlap (captures are idempotent); backfill: everything
  v_after := CASE WHEN p_kind = 'poll' AND s.cursor_modified IS NOT NULL THEN s.cursor_modified - interval '10 minutes' END;
  INSERT INTO f360.commerce_sync_runs (target_id, kind, modified_after) VALUES (t.id, p_kind, v_after) RETURNING id INTO v_id;
  UPDATE f360.commerce_sync_state SET last_attempt_at = clock_timestamp() WHERE target_id = t.id;
  RETURN jsonb_build_object('run_id', v_id, 'modified_after', v_after);
END $function$;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012001100', 'f360_orders_production', '{}');
UPDATE f360.sales_targets SET orders_mode = 'on', orders_since_id = 5351 WHERE key = 'woo_production' AND is_production;
SELECT jsonb_build_object('canal', (SELECT jsonb_build_object('key', key, 'orders_mode', orders_mode, 'orders_since_id', orders_since_id, 'active', active, 'stock_sync_mode', stock_sync_mode) FROM f360.sales_targets WHERE key = 'woo_production'));
COMMIT;
