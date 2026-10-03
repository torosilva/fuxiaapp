-- Fuxia 360 — one store product per MODEL (STAGING). Decision: Mario 2026-10-03 ("Los 16 de una vez"): the models that
-- the current store sells as one product PER COLOUR (16 models → 70 Woo products) become ONE store product each, with
-- colour + size, like Fuxia 360. Supersedes, for staging, "No consolidar todavía los 129 productos" (Track D).
--   1. f360_consolidate_start (owner): records the merge, moves the model's legacy links to f360.retired_woo_links
--      (so an order that still arrives for an old per-colour product is recognised: same pair, Bodega is discounted)
--      and requests a normal F360 publish (one variable product, pa_color × pa_medida, photos per colour, price).
--   2. The publisher (f360-woo-publish) creates it as a DRAFT, as always (DW3).
--   3. f360_consolidate_finish (owner, after the publish succeeded): shows the new product, hides (private, never
--      deleted) the old per-colour products, and re-sends stock (5–7 días rule included). Old URLs: a redirect list.
--   Guards: production targets refused; a merged model can never be re-linked to the old products; models not ready
--   (e.g. a colour without photos) are skipped with the reason.
-- Rollback: supabase/rollbacks/20261007001900_f360_legacy_consolidation.down.sql

CREATE TABLE f360.legacy_consolidations (
  target_id        uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  product_id       uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  status           text NOT NULL DEFAULT 'publicando' CHECK (status IN ('publicando', 'publicada')),
  legacy_products  jsonb NOT NULL DEFAULT '[]',     -- [{woo_product_id, name, path}] (path read before hiding, for redirects)
  new_woo_product_id integer,
  job_id           uuid,
  requested_by     text NOT NULL, requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_by      text, finished_at timestamptz,
  PRIMARY KEY (target_id, product_id)
);
CREATE TABLE f360.retired_woo_links (
  target_id        uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_variation_id integer NOT NULL,
  woo_product_id   integer,
  variant_id       uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  retired_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason           text NOT NULL,
  PRIMARY KEY (target_id, woo_variation_id)
);

CREATE FUNCTION f360.is_consolidated(p_target uuid, p_product uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM f360.legacy_consolidations WHERE target_id = p_target AND product_id = p_product)
$$;

-- Owner: start merging these models (or, without ids, every model split over 2+ store products). Returns publish jobs.
CREATE FUNCTION public.f360_consolidate_start(p_target_key text, p_product_ids uuid[] DEFAULT NULL, p_legacy_paths jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; x record; ready jsonb; job jsonb; out jsonb := '[]'; skipped jsonb := '[]'; legacy jsonb;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  IF t.is_production THEN RAISE EXCEPTION 'Unir productos en la tienda de producción no está aprobado.'; END IF;
  FOR x IN SELECT v.product_id, p.name, count(DISTINCT m.woo_product_id) AS n
           FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id JOIN f360.products p ON p.id = v.product_id
           WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
             AND (p_product_ids IS NULL OR v.product_id = ANY (p_product_ids))
           GROUP BY v.product_id, p.name ORDER BY p.name LOOP
    IF p_product_ids IS NULL AND x.n < 2 THEN CONTINUE; END IF;
    IF f360.is_consolidated(t.id, x.product_id) THEN
      SELECT jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job_id, 'status', status) INTO job
        FROM f360.legacy_consolidations WHERE target_id = t.id AND product_id = x.product_id;
      out := out || job; CONTINUE;
    END IF;
    ready := f360.product_readiness(x.product_id);
    IF NOT (ready->>'ready')::boolean THEN
      skipped := skipped || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'missing', ready->'missing'); CONTINUE;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', w.woo_product_id, 'name', w.name, 'path', p_legacy_paths->>(w.woo_product_id::text)) ORDER BY w.woo_product_id), '[]')
      INTO legacy FROM (SELECT DISTINCT m.woo_product_id, min(m.woo_product_name) AS name FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
                        WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id GROUP BY m.woo_product_id) w;
    INSERT INTO f360.legacy_consolidations (target_id, product_id, legacy_products, requested_by) VALUES (t.id, x.product_id, legacy, r.display_name);
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT vl.target_id, vl.woo_variation_id, vl.woo_product_id, vl.variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    -- also every confirmed legacy variation that was never linked (orders can still name it)
    INSERT INTO f360.retired_woo_links (target_id, woo_variation_id, woo_product_id, variant_id, reason)
      SELECT m.target_id, m.woo_variation_id, m.woo_product_id, m.confirmed_variant_id, 'Unido en un solo producto de la tienda'
      FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
      WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = x.product_id
    ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
    DELETE FROM f360.stock_sync_queue q USING f360.woo_variant_links vl, f360.product_variants v
      WHERE q.target_id = t.id AND q.variant_id = vl.variant_id AND vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    DELETE FROM f360.woo_variant_links vl USING f360.product_variants v
      WHERE vl.target_id = t.id AND vl.origin = 'legacy_adopted' AND v.id = vl.variant_id AND v.product_id = x.product_id;
    job := public.f360_request_publish(x.product_id, gen_random_uuid(), p_target_key);
    UPDATE f360.legacy_consolidations SET job_id = (job->>'id')::uuid WHERE target_id = t.id AND product_id = x.product_id;
    out := out || jsonb_build_object('product_id', x.product_id, 'name', x.name, 'job_id', job->>'id', 'status', 'publicando');
  END LOOP;
  RETURN jsonb_build_object('items', out, 'skipped', skipped);
END $$;

-- Owner, after the publish succeeded: new product visible, old per-colour products hidden, stock re-sent.
CREATE FUNCTION public.f360_consolidate_finish(p_target_key text, p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; t f360.sales_targets; c f360.legacy_consolidations; l f360.woo_product_links; x jsonb; v_name text;
BEGIN
  r := f360.require_role('owner');
  t := f360.target_by_key(p_target_key);
  SELECT * INTO c FROM f360.legacy_consolidations WHERE target_id = t.id AND product_id = p_product_id FOR UPDATE;
  IF c.product_id IS NULL THEN RAISE EXCEPTION 'Ese modelo no se está uniendo.'; END IF;
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  IF l.woo_product_id IS NULL OR NOT EXISTS (SELECT 1 FROM f360.sync_jobs WHERE id = c.job_id AND status = 'succeeded') THEN
    RAISE EXCEPTION 'Todavía no se publica el producto nuevo.';
  END IF;
  SELECT name INTO v_name FROM f360.products WHERE id = p_product_id;
  IF c.status <> 'publicada' THEN
    INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
      VALUES (t.id, l.woo_product_id, v_name, 'mostrar', 'Producto único del modelo (unión de colores)', auth.uid(), r.display_name)
      ON CONFLICT DO NOTHING;
    FOR x IN SELECT * FROM jsonb_array_elements(c.legacy_products) LOOP
      INSERT INTO f360.woo_visibility_requests (target_id, woo_product_id, woo_product_name, kind, reason, requested_by, requested_by_name)
        VALUES (t.id, (x->>'woo_product_id')::int, x->>'name', 'ocultar', 'Unido en “' || v_name || '”', auth.uid(), r.display_name)
        ON CONFLICT DO NOTHING;
    END LOOP;
    INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
      SELECT t.id, vl.variant_id, 'Unión de colores' FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
      WHERE vl.target_id = t.id AND v.product_id = p_product_id
    ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = EXCLUDED.reason;
    UPDATE f360.legacy_consolidations SET status = 'publicada', new_woo_product_id = l.woo_product_id, finished_by = r.display_name, finished_at = clock_timestamp()
      WHERE target_id = t.id AND product_id = p_product_id RETURNING * INTO c;
  END IF;
  RETURN jsonb_build_object('product_id', c.product_id, 'name', v_name, 'status', c.status, 'new_woo_product_id', c.new_woo_product_id,
    'new_path', '/producto/' || (SELECT slug FROM f360.products WHERE id = p_product_id) || '/', 'legacy_products', c.legacy_products);
END $$;

CREATE FUNCTION public.f360_consolidations(p_target_key text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  PERFORM f360.require_role('viewer');
  t := f360.target_by_key(p_target_key);
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('product_id', c.product_id, 'name', p.name, 'status', c.status, 'job_status', j.status, 'job_error', j.error_message,
      'new_woo_product_id', c.new_woo_product_id, 'new_path', '/producto/' || p.slug || '/', 'legacy_products', c.legacy_products,
      'requested_at', c.requested_at, 'finished_at', c.finished_at) ORDER BY p.name), '[]')
    FROM f360.legacy_consolidations c JOIN f360.products p ON p.id = c.product_id LEFT JOIN f360.sync_jobs j ON j.id = c.job_id WHERE c.target_id = t.id);
END $$;

-- ── Guards: unchanged from 20261007000200 except a merged model (marked lines) ──
CREATE OR REPLACE FUNCTION f360.woo_variant_link_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.origin = 'legacy_adopted' AND NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map m
       WHERE m.target_id = NEW.target_id AND m.woo_variation_id = NEW.woo_variation_id AND m.woo_product_id = NEW.woo_product_id
         AND m.status = 'confirmado' AND m.confirmed_variant_id = NEW.variant_id) THEN
    RAISE EXCEPTION 'Un vínculo legacy solo se crea desde una homologación confirmada por una persona (variación Woo %).', NEW.woo_variation_id;
  END IF;
  IF NEW.origin = 'legacy_adopted' AND f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Este modelo ya se unió en un solo producto de la tienda: ya no se liga a los productos anteriores.';
  END IF;
  IF NEW.origin = 'f360_published' AND EXISTS (SELECT 1 FROM f360.legacy_woo_map m WHERE m.confirmed_variant_id = NEW.variant_id)
     AND NOT f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Esta variante viene del catálogo Woo anterior: no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION f360.sync_job_legacy_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF f360.is_consolidated(NEW.target_id, NEW.product_id) THEN RETURN NEW; END IF;   -- approved merge (20261007001900)
  IF EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE v.product_id = NEW.product_id)
     OR EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                WHERE vl.origin = 'legacy_adopted' AND v.product_id = NEW.product_id) THEN
    RAISE EXCEPTION 'Este modelo viene del catálogo Woo anterior: ya existe en la tienda y no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;

-- ── Content push list: unchanged from 20261007001400 except merged models are left out ──
CREATE OR REPLACE FUNCTION public.f360_legacy_content_list(p_target_key text, p_product_ids uuid[] DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.content_target(p_target_key);
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('woo_product_id', x.woo_product_id, 'product_id', x.product_id, 'name', x.name,
      'last_push', (SELECT max(at) FROM f360.legacy_content_pushes cp WHERE cp.target_id = t.id AND cp.woo_product_id = x.woo_product_id AND cp.ok))
      ORDER BY x.name, x.woo_product_id), '[]')
    FROM (SELECT DISTINCT m.woo_product_id, v.product_id, p.name
          FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id JOIN f360.products p ON p.id = v.product_id
          WHERE m.target_id = t.id AND m.status = 'confirmado' AND p.status = 'active'
            AND (p_product_ids IS NULL OR v.product_id = ANY (p_product_ids))
            AND NOT f360.is_consolidated(t.id, v.product_id)) x);   -- merged models: content goes with the new product
END $$;

-- ── Order ingestion: unchanged from 20261007001500 except the retired-link lookup ──
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

REVOKE ALL ON f360.legacy_consolidations, f360.retired_woo_links FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.legacy_consolidations, f360.retired_woo_links TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_consolidate_start(text, uuid[], jsonb), public.f360_consolidate_finish(text, uuid), public.f360_consolidations(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_consolidate_start(text, uuid[], jsonb), public.f360_consolidate_finish(text, uuid), public.f360_consolidations(text) TO authenticated, service_role;
