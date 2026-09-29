-- Fuxia 360 P2.3A — stock authority + Woo order ingestion + reconciliation (STAGING / local Woo only).
-- Additive. The existing ledger tables are reused (SALE events/movements); nothing existing is altered except
-- f360.event_json (adds the business reference so history can say "Pedido #123").
--
--   f360.stock_sync_queue      one pending "push Bodega stock to Woo" per (target, variant) — filled by a trigger
--   f360.stock_sync_log        every push attempt (append-only) — operator history
--   f360.woo_orders            last known state of each Woo order (for out-of-order protection)
--   f360.woo_order_lines       each order line → exactly one outcome (sold / oversold / legacy / unknown…)
--   f360.woo_webhook_deliveries every webhook received, with its result (append-only; no customer PII stored)
--   f360.sync_exceptions       "Avisos de sincronización": oversell, unknown SKU, drift, failed pushes, pending decisions
--   f360.reconciliation_runs   each Fuxia ↔ Woo stock comparison
--
-- Rules (approved): Bodega CDMX = source of truth of online stock (P-STOCK, no reserve); never negative stock;
-- oversell is an alert, not a negative balance; cancellation/refund after a sale is recorded as a pending decision
-- (DW4) — NO automatic restock policy is invented here.
-- Rollback: supabase/rollbacks/20260928000100_f360_p23a_stock_sync_orders.down.sql

-- ── Exceptions ("Avisos de sincronización") ─────────────────────────────────
CREATE TABLE f360.sync_exceptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  kind            text NOT NULL CHECK (kind IN ('oversell', 'unknown_sku', 'sku_mismatch', 'stock_drift', 'push_failed',
                    'cancel_after_sale', 'refund_after_sale', 'webhook_rejected')),
  status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  dedupe_key      text NOT NULL,
  message         text NOT NULL,
  product_id      uuid REFERENCES f360.products(id) ON DELETE RESTRICT,
  variant_id      uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  woo_order_id    bigint,
  detail          jsonb,
  occurrences     integer NOT NULL DEFAULT 1,
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  resolved_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  resolved_by_name text,
  resolution_note text
);
CREATE UNIQUE INDEX sync_exceptions_open_dedupe ON f360.sync_exceptions (target_id, dedupe_key) WHERE status = 'open';
CREATE INDEX sync_exceptions_status_idx ON f360.sync_exceptions (status, created_at DESC);

-- Opens (or re-touches) one alert per dedupe key while it is open.
CREATE FUNCTION f360.open_exception(p_target uuid, p_kind text, p_key text, p_message text, p_detail jsonb,
  p_product uuid DEFAULT NULL, p_variant uuid DEFAULT NULL, p_order bigint DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
  UPDATE f360.sync_exceptions SET occurrences = occurrences + 1, last_seen_at = now(), detail = coalesce(p_detail, detail), message = p_message
    WHERE target_id = p_target AND dedupe_key = p_key AND status = 'open' RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    INSERT INTO f360.sync_exceptions (target_id, kind, dedupe_key, message, detail, product_id, variant_id, woo_order_id)
      VALUES (p_target, p_kind, p_key, p_message, p_detail, p_product, p_variant, p_order) RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END $$;

CREATE FUNCTION f360.auto_resolve(p_target uuid, p_key text, p_note text) RETURNS void LANGUAGE sql AS $$
  UPDATE f360.sync_exceptions SET status = 'resolved', resolved_at = now(), resolved_by_name = 'Automático', resolution_note = p_note
  WHERE target_id = p_target AND dedupe_key = p_key AND status = 'open'
$$;

CREATE FUNCTION f360.variant_label(p_variant uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT p.name || ' · ' || c.name || ' · ' || v.size_label FROM f360.product_variants v
  JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id WHERE v.id = p_variant
$$;

-- ── Stock push queue (Fuxia → Woo) ──────────────────────────────────────────
CREATE TABLE f360.stock_sync_queue (
  target_id        uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  variant_id       uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  requested_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  next_attempt_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  claimed_at       timestamptz,
  attempts         integer NOT NULL DEFAULT 0,
  last_error       text,
  reason           text,
  PRIMARY KEY (target_id, variant_id)
);

CREATE TABLE f360.stock_sync_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id   uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  variant_id  uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  ok          boolean NOT NULL,
  ats         integer,            -- Bodega CDMX sellable stock at push time
  expected    integer,            -- what Fuxia believed Woo had
  woo_before  integer,            -- what Woo actually had
  pushed      integer,            -- what was written
  error       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX stock_sync_log_idx ON f360.stock_sync_log (target_id, created_at DESC);

-- Any balance change at a target's fulfillment location, for a variant linked to that target → queue a push.
CREATE FUNCTION f360.enqueue_stock_sync() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
    SELECT t.id, NEW.variant_id, 'Cambio de existencias'
    FROM f360.sales_targets t JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = NEW.variant_id
    WHERE t.active AND t.fulfillment_location_id = NEW.location_id
  ON CONFLICT (target_id, variant_id) DO UPDATE SET requested_at = clock_timestamp(), next_attempt_at = clock_timestamp(), reason = EXCLUDED.reason;
  RETURN NULL;
END $$;
CREATE TRIGGER inventory_balances_enqueue_stock_sync AFTER INSERT OR UPDATE OF on_hand ON f360.inventory_balances
  FOR EACH ROW EXECUTE FUNCTION f360.enqueue_stock_sync();

-- ── Woo orders (sales back into the ledger) ─────────────────────────────────
CREATE TABLE f360.woo_orders (
  target_id        uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_order_id     bigint NOT NULL,
  woo_status       text NOT NULL,
  woo_modified_at  timestamptz NOT NULL,
  currency         text,
  refund_ids       bigint[] NOT NULL DEFAULT '{}',
  first_seen_at    timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, woo_order_id)
);

CREATE TABLE f360.woo_order_lines (
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_order_id    bigint NOT NULL,
  woo_line_id     bigint NOT NULL,
  woo_product_id  bigint,
  woo_variation_id bigint,
  sku             text,
  quantity        integer NOT NULL CHECK (quantity > 0),
  variant_id      uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  outcome         text NOT NULL CHECK (outcome IN ('sold', 'oversold', 'legacy', 'unknown_sku', 'sku_mismatch')),
  sale_event_id   uuid REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_id, woo_order_id, woo_line_id),
  FOREIGN KEY (target_id, woo_order_id) REFERENCES f360.woo_orders (target_id, woo_order_id) ON DELETE RESTRICT
);

CREATE TABLE f360.woo_webhook_deliveries (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  delivery_id     text,
  topic           text,
  woo_order_id    bigint,
  woo_status      text,
  woo_modified_at timestamptz,
  result          text NOT NULL,     -- applied | duplicate_delivery | duplicate | stale | not_paid | rejected_signature | error
  detail          jsonb,
  received_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX woo_webhook_deliveries_idx ON f360.woo_webhook_deliveries (target_id, delivery_id);
CREATE INDEX woo_webhook_deliveries_recent ON f360.woo_webhook_deliveries (target_id, received_at DESC);

CREATE TABLE f360.reconciliation_runs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_id   uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  checked     integer NOT NULL,
  in_sync     integer NOT NULL,
  drifted     integer NOT NULL,
  missing     integer NOT NULL,
  items       jsonb,              -- only the variants that did NOT match
  requested_by_name text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER stock_sync_log_append_only BEFORE UPDATE OR DELETE ON f360.stock_sync_log FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER woo_webhook_deliveries_append_only BEFORE UPDATE OR DELETE ON f360.woo_webhook_deliveries FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
CREATE TRIGGER reconciliation_runs_append_only BEFORE UPDATE OR DELETE ON f360.reconciliation_runs FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE FUNCTION f360.target_by_key(p_key text) RETURNS f360.sales_targets LANGUAGE plpgsql STABLE AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key AND active;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda % no configurada.', p_key; END IF;
  IF t.is_production THEN RAISE EXCEPTION 'La tienda de producción no está habilitada (P2.3A).'; END IF;
  RETURN t;
END $$;

-- ── Order ingestion (service_role only; called by the f360-woo-orders webhook) ─
-- p_delivery: {delivery_id, topic}. p_order: MINIMIZED order {id, status, date_modified_gmt, currency,
--   refunds:[{id}], line_items:[{id, product_id, variation_id, sku, quantity}]} — no customer data.
-- Atomic per call. Idempotent per delivery, per order version and per line. Serialized per order.
CREATE FUNCTION public.f360_ingest_woo_order(p_target_key text, p_delivery jsonb, p_order jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  t f360.sales_targets; prev f360.woo_orders;
  v_order bigint := (p_order->>'id')::bigint;
  v_status text := p_order->>'status';
  v_mod timestamptz := ((p_order->>'date_modified_gmt')::timestamp AT TIME ZONE 'UTC');
  v_delivery text := nullif(p_delivery->>'delivery_id', '');
  v_paid boolean; li jsonb; v_line bigint; v_var bigint; v_sku text; v_qty int; v_variant uuid; v_vsku text; v_product uuid;
  v_on_hand int; v_event uuid; v_outcome text; lines jsonb := '[]'; v_result text; v_sold_any boolean; r jsonb; v_label text;
BEGIN
  t := f360.target_by_key(p_target_key);
  IF v_order IS NULL OR v_status IS NULL OR v_mod IS NULL THEN RAISE EXCEPTION 'Pedido incompleto.'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(t.id::text || ':' || v_order, 0));   -- same order: one at a time

  IF v_delivery IS NOT NULL AND EXISTS (SELECT 1 FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.delivery_id = v_delivery
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
      v_variant := NULL; v_event := NULL; v_product := NULL;
      SELECT vl.variant_id, v.sku, v.product_id INTO v_variant, v_vsku, v_product FROM f360.woo_variant_links vl
        JOIN f360.product_variants v ON v.id = vl.variant_id WHERE vl.target_id = t.id AND vl.woo_variation_id = v_var;
      IF v_variant IS NULL THEN
        IF coalesce(v_sku, '') LIKE 'F360-%' OR EXISTS (SELECT 1 FROM f360.woo_product_links WHERE target_id = t.id AND woo_product_id = (li->>'product_id')::bigint) THEN
          v_outcome := 'unknown_sku';
          PERFORM f360.open_exception(t.id, 'unknown_sku', 'unknown_sku:' || v_order || ':' || v_line,
            format('Venta en línea de un artículo que Fuxia 360 no reconoce (SKU %s, pedido #%s). No se descontó inventario.', coalesce(v_sku, 'sin SKU'), v_order),
            jsonb_build_object('sku', v_sku, 'woo_variation_id', v_var, 'quantity', v_qty), NULL, NULL, v_order);
        ELSE
          v_outcome := 'legacy';   -- product not managed by Fuxia 360: ignored on purpose (legacy catalog)
        END IF;
      ELSIF v_sku IS DISTINCT FROM v_vsku THEN
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
    FOR r IN SELECT x FROM jsonb_array_elements(coalesce(p_order->'refunds', '[]')) x LOOP
      IF NOT ((r->>'id')::bigint = ANY ((SELECT refund_ids FROM f360.woo_orders WHERE target_id = t.id AND woo_order_id = v_order))) THEN
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

CREATE FUNCTION public.f360_record_webhook_rejection(p_target_key text, p_delivery jsonb, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  t := f360.target_by_key(p_target_key);
  INSERT INTO f360.woo_webhook_deliveries (target_id, delivery_id, topic, result, detail)
    VALUES (t.id, left(p_delivery->>'delivery_id', 100), left(p_delivery->>'topic', 100), 'rejected_signature', jsonb_build_object('reason', left(p_reason, 200)));
  PERFORM f360.open_exception(t.id, 'webhook_rejected', 'webhook_rejected',
    'Llegaron avisos de la tienda con firma inválida y se rechazaron. Si se repite, revisar el secreto del webhook.', jsonb_build_object('reason', left(p_reason, 200)));
END $$;

-- ── Stock push worker (service_role only) ───────────────────────────────────
CREATE FUNCTION public.f360_sync_claim_stock(p_target_key text, p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; out jsonb;
BEGIN
  t := f360.target_by_key(p_target_key);
  WITH picked AS (
    SELECT q.target_id, q.variant_id FROM f360.stock_sync_queue q
    WHERE q.target_id = t.id AND q.next_attempt_at <= clock_timestamp() AND (q.claimed_at IS NULL OR q.claimed_at < clock_timestamp() - interval '2 minutes')
    ORDER BY q.requested_at LIMIT greatest(1, least(p_limit, 500)) FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE f360.stock_sync_queue q SET claimed_at = clock_timestamp() FROM picked
    WHERE q.target_id = picked.target_id AND q.variant_id = picked.variant_id RETURNING q.variant_id, q.claimed_at, q.attempts
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('variant_id', c.variant_id, 'claimed_at', c.claimed_at, 'attempts', c.attempts,
      'sku', v.sku, 'woo_product_id', pl.woo_product_id, 'woo_variation_id', vl.woo_variation_id,
      'ats', f360.online_ats(v.id, t.fulfillment_location_id), 'expected', vl.last_pushed_stock)), '[]')
    INTO out
  FROM claimed c JOIN f360.product_variants v ON v.id = c.variant_id
  JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = v.id
  JOIN f360.woo_product_links pl ON pl.target_id = t.id AND pl.product_id = v.product_id;
  RETURN out;
END $$;

-- p_results: [{variant_id, claimed_at, ok, ats, expected, woo_before, pushed, error}]
CREATE FUNCTION public.f360_sync_stock_result(p_target_key text, p_results jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; r jsonb; v uuid; q f360.stock_sync_queue; ok_n int := 0; fail_n int := 0;
BEGIN
  t := f360.target_by_key(p_target_key);
  FOR r IN SELECT * FROM jsonb_array_elements(p_results) LOOP
    v := (r->>'variant_id')::uuid;
    INSERT INTO f360.stock_sync_log (target_id, variant_id, ok, ats, expected, woo_before, pushed, error)
      VALUES (t.id, v, (r->>'ok')::boolean, (r->>'ats')::int, (r->>'expected')::int, (r->>'woo_before')::int, (r->>'pushed')::int, left(r->>'error', 500));
    SELECT * INTO q FROM f360.stock_sync_queue WHERE target_id = t.id AND variant_id = v FOR UPDATE;
    IF (r->>'ok')::boolean THEN
      ok_n := ok_n + 1;
      UPDATE f360.woo_variant_links SET last_pushed_stock = (r->>'pushed')::int, last_pushed_at = now() WHERE target_id = t.id AND variant_id = v;
      -- only remove the request if nothing changed after we claimed it (otherwise push again)
      DELETE FROM f360.stock_sync_queue WHERE target_id = t.id AND variant_id = v AND requested_at <= (r->>'claimed_at')::timestamptz;
      UPDATE f360.stock_sync_queue SET claimed_at = NULL, attempts = 0, last_error = NULL WHERE target_id = t.id AND variant_id = v;
      PERFORM f360.auto_resolve(t.id, 'push_failed:' || v, 'Se sincronizó correctamente.');
    ELSE
      fail_n := fail_n + 1;
      UPDATE f360.stock_sync_queue SET claimed_at = NULL, attempts = attempts + 1, last_error = left(r->>'error', 500),
        next_attempt_at = clock_timestamp() + least(interval '10 minutes', interval '10 seconds' * power(2, attempts))
        WHERE target_id = t.id AND variant_id = v RETURNING * INTO q;
      IF q.attempts >= 3 THEN
        PERFORM f360.open_exception(t.id, 'push_failed', 'push_failed:' || v,
          format('No se ha podido actualizar el stock en la tienda de %s (%s intentos). Se sigue reintentando.', f360.variant_label(v), q.attempts),
          jsonb_build_object('error', left(r->>'error', 300)), (SELECT product_id FROM f360.product_variants WHERE id = v), v);
      END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('ok', ok_n, 'failed', fail_n);
END $$;

-- ── Reconciliation (service_role only) ──────────────────────────────────────
CREATE FUNCTION public.f360_reconcile_snapshot(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  t := f360.target_by_key(p_target_key);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('variant_id', v.id, 'sku', v.sku, 'label', f360.variant_label(v.id),
      'woo_product_id', pl.woo_product_id, 'woo_variation_id', vl.woo_variation_id, 'ats', f360.online_ats(v.id, t.fulfillment_location_id),
      'expected', vl.last_pushed_stock) ORDER BY v.sku), '[]')
    FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id AND v.status = 'active'
    JOIN f360.woo_product_links pl ON pl.target_id = t.id AND pl.product_id = v.product_id
    WHERE vl.target_id = t.id);
END $$;

-- p_run: {requested_by_name, items:[{variant_id, sku, label, ats, woo_stock, state: in_sync|drift|missing}]}
CREATE FUNCTION public.f360_reconcile_finish(p_target_key text, p_run jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; i jsonb; n int := 0; ok int := 0; dr int := 0; mi int := 0; bad jsonb := '[]'; v uuid; run_id uuid;
BEGIN
  t := f360.target_by_key(p_target_key);
  FOR i IN SELECT * FROM jsonb_array_elements(coalesce(p_run->'items', '[]')) LOOP
    n := n + 1; v := (i->>'variant_id')::uuid;
    IF i->>'state' = 'in_sync' THEN
      ok := ok + 1;
      PERFORM f360.auto_resolve(t.id, 'stock_drift:' || v, 'La revisión encontró la tienda al día.');
    ELSE
      IF i->>'state' = 'missing' THEN mi := mi + 1; ELSE dr := dr + 1; END IF;
      bad := bad || i;
      PERFORM f360.open_exception(t.id, 'stock_drift', 'stock_drift:' || v,
        CASE WHEN i->>'state' = 'missing' THEN format('%s no existe en la tienda.', i->>'label')
             ELSE format('%s: la tienda muestra %s y Bodega CDMX tiene %s. Se programó una corrección automática.', i->>'label', coalesce(i->>'woo_stock', '—'), i->>'ats') END,
        i, (SELECT product_id FROM f360.product_variants WHERE id = v), v);
      INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason) VALUES (t.id, v, 'Revisión: diferencia con la tienda')
        ON CONFLICT (target_id, variant_id) DO UPDATE SET requested_at = clock_timestamp(), next_attempt_at = clock_timestamp(), reason = EXCLUDED.reason;
    END IF;
  END LOOP;
  INSERT INTO f360.reconciliation_runs (target_id, checked, in_sync, drifted, missing, items, requested_by_name)
    VALUES (t.id, n, ok, dr, mi, bad, left(p_run->>'requested_by_name', 100)) RETURNING id INTO run_id;
  RETURN jsonb_build_object('id', run_id, 'checked', n, 'in_sync', ok, 'drifted', dr, 'missing', mi);
END $$;

-- ── User RPCs ───────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_list_sync_issues(p_status text DEFAULT 'open') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'issues', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'status', e.status, 'message', e.message,
        'product_id', e.product_id, 'product_name', p.name, 'variant_label', CASE WHEN e.variant_id IS NULL THEN NULL ELSE f360.variant_label(e.variant_id) END,
        'woo_order_id', e.woo_order_id, 'occurrences', e.occurrences, 'created_at', e.created_at, 'last_seen_at', e.last_seen_at,
        'resolved_at', e.resolved_at, 'resolved_by_name', e.resolved_by_name, 'resolution_note', e.resolution_note, 'target', t.name)
        ORDER BY e.created_at DESC), '[]')
      FROM (SELECT * FROM f360.sync_exceptions WHERE (p_status = 'all' OR status = p_status) ORDER BY created_at DESC LIMIT 100) e
      JOIN f360.sales_targets t ON t.id = e.target_id LEFT JOIN f360.products p ON p.id = e.product_id),
    'open_count', (SELECT count(*) FROM f360.sync_exceptions WHERE status = 'open'),
    'last_reconciliation', (SELECT jsonb_build_object('checked', checked, 'in_sync', in_sync, 'drifted', drifted, 'missing', missing,
        'at', created_at, 'by', requested_by_name, 'target', t.name)
      FROM f360.reconciliation_runs rr JOIN f360.sales_targets t ON t.id = rr.target_id ORDER BY rr.created_at DESC LIMIT 1),
    'queue', jsonb_build_object('pending', (SELECT count(*) FROM f360.stock_sync_queue), 'failing', (SELECT count(*) FROM f360.stock_sync_queue WHERE attempts > 0),
      'oldest', (SELECT min(requested_at) FROM f360.stock_sync_queue)),
    'recent_pushes', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', l.created_at, 'label', f360.variant_label(l.variant_id), 'ok', l.ok,
        'ats', l.ats, 'woo_before', l.woo_before, 'pushed', l.pushed, 'error', l.error) ORDER BY l.id DESC), '[]')
      FROM (SELECT * FROM f360.stock_sync_log ORDER BY id DESC LIMIT 15) l),
    'recent_orders', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', d.received_at, 'order', d.woo_order_id, 'status', d.woo_status, 'result', d.result,
        'lines', d.detail->'lines') ORDER BY d.id DESC), '[]')
      FROM (SELECT * FROM f360.woo_webhook_deliveries ORDER BY id DESC LIMIT 15) d));
END $$;

CREATE FUNCTION public.f360_sync_badge() RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT count(*) FROM f360.sync_exceptions WHERE status = 'open');
END $$;

CREATE FUNCTION public.f360_resolve_sync_issue(p_id uuid, p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('operator');
  IF coalesce(btrim(p_note), '') = '' THEN RAISE EXCEPTION 'Escribe qué se hizo para resolverlo.'; END IF;
  UPDATE f360.sync_exceptions SET status = 'resolved', resolved_at = now(), resolved_by = r.auth_user_id, resolved_by_name = r.display_name,
    resolution_note = left(btrim(p_note), 500) WHERE id = p_id AND status = 'open';
  IF NOT FOUND THEN RAISE EXCEPTION 'Ese aviso ya estaba resuelto o no existe.'; END IF;
  RETURN jsonb_build_object('ok', true);
END $$;

-- History: include the business reference (e.g. the Woo order) in every event.
CREATE OR REPLACE FUNCTION f360.event_json(p_event_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'type', e.event_type, 'actor_name', e.actor_name, 'note', e.note,
    'occurred_at', e.occurred_at, 'reference_type', e.business_reference_type, 'reference_id', e.business_reference_id,
    'total_pairs', (SELECT coalesce(sum(m.quantity), 0) FROM f360.inventory_movements m WHERE m.event_id = e.id),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'product_id', p.id, 'product_name', p.name, 'product_image', coalesce(f360.color_primary_image(c.id), f360.product_primary_image(p.id)),
        'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku, 'quantity', m.quantity,
        'from_location', lf.name, 'to_location', lt.name)
        ORDER BY p.name, c.sort, ps.sort), '[]'::jsonb)
      FROM f360.inventory_movements m
      JOIN f360.product_variants v ON v.id = m.variant_id
      JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id
      JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
      LEFT JOIN f360.locations lf ON lf.id = m.from_location_id
      LEFT JOIN f360.locations lt ON lt.id = m.to_location_id
      WHERE m.event_id = e.id))
  FROM f360.inventory_events e WHERE e.id = p_event_id
$$;

-- ── Grants ──────────────────────────────────────────────────────────────────
REVOKE ALL ON f360.sync_exceptions, f360.stock_sync_queue, f360.stock_sync_log, f360.woo_orders, f360.woo_order_lines,
  f360.woo_webhook_deliveries, f360.reconciliation_runs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_ingest_woo_order(text, jsonb, jsonb), public.f360_record_webhook_rejection(text, jsonb, text),
  public.f360_sync_claim_stock(text, integer), public.f360_sync_stock_result(text, jsonb),
  public.f360_reconcile_snapshot(text), public.f360_reconcile_finish(text, jsonb),
  public.f360_list_sync_issues(text), public.f360_sync_badge(), public.f360_resolve_sync_issue(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_list_sync_issues(text), public.f360_sync_badge(), public.f360_resolve_sync_issue(uuid, text)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_ingest_woo_order(text, jsonb, jsonb), public.f360_record_webhook_rejection(text, jsonb, text),
  public.f360_sync_claim_stock(text, integer), public.f360_sync_stock_result(text, jsonb),
  public.f360_reconcile_snapshot(text), public.f360_reconcile_finish(text, jsonb)
  TO service_role;
