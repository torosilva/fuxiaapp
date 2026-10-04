-- Fuxia 360 G1-B — Commerce Facts (STAGING). Design: docs/fuxia360/growth/G1_COMMERCE_FACTS_DESIGN.md (G1-A, accepted 2026-10-04).
-- One commercial truth for online orders and physical store sales, WITHOUT copying store sales and WITHOUT touching
-- inventory:
--   * Online: Woo order economics are captured into their OWN tables (header, lines, refunds, first-party attribution),
--     keyed by (target, woo_order_id). f360.woo_orders / woo_order_lines stay the inventory-processing state, untouched:
--     a backfill that wrote there would make a later webhook look "duplicate" and skip the stock movement.
--   * Store: no copy. public.offline_sales (+ items) remains the record; the views read it.
--   * f360.commerce_orders / f360.commerce_order_lines: one row per sale from either source, original currency only.
-- Amounts are ALWAYS in the original currency; nothing here converts or sums MXN + COP + USD (D-G1-03).
-- Meta "purchase" signals are NOT read or stored (DQ-01). Attribution = Woo first-party order attribution (last click,
-- session-scoped), stored as opaque values with explicit provenance (never "Meta attribution").
-- Freshness (STALE) comes from the health of the Woo poll (heartbeat), never from "no orders lately" (G1-Q3).
-- Access: owner / operator only (D-G1-05); the growth plan read moves from viewer to operator.
-- Rollback: supabase/rollbacks/20261008000100_f360_g1_commerce_facts.down.sql

-- ── Online order header (latest version) ───────────────────────────────────
CREATE TABLE f360.commerce_woo_orders (
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  woo_order_id       bigint NOT NULL CHECK (woo_order_id > 0),
  woo_status         text NOT NULL,
  woo_modified_at    timestamptz NOT NULL,                 -- version guard (date_modified_gmt)
  economics_hash     text NOT NULL,                        -- detects "same version, nothing changed"
  created_via        text,                                 -- Woo created_via, raw and immutable (Woo docs)
  business_origin    text NOT NULL CHECK (business_origin IN ('storefront', 'manual_admin', 'api_integration', 'unknown')),
  woo_created_at     timestamptz,
  paid_at            timestamptz,                          -- current date_paid
  completed_at       timestamptz,
  ever_paid          boolean NOT NULL DEFAULT false,       -- sticky: once paid evidence is seen it is never lost
  first_paid_at      timestamptz,
  currency           text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  prices_include_tax boolean,
  items_subtotal     numeric(14,2) NOT NULL,               -- Σ line.subtotal  (after price rules e.g. WDR, before coupons)
  discount_total     numeric(14,2) NOT NULL,               -- = Σ coupon discounts = Σ(line.subtotal − line.total)
  discount_tax       numeric(14,2) NOT NULL,
  items_total        numeric(14,2) NOT NULL,               -- Σ line.total     (after coupons, without tax) = PRODUCT SALES
  cart_tax           numeric(14,2) NOT NULL,
  shipping_total     numeric(14,2) NOT NULL,
  shipping_tax       numeric(14,2) NOT NULL,
  fees_total         numeric(14,2) NOT NULL,
  fees_tax           numeric(14,2) NOT NULL,
  total_tax          numeric(14,2) NOT NULL,
  order_total        numeric(14,2) NOT NULL,               -- Woo "Grand total"
  units              integer NOT NULL,
  line_count         integer NOT NULL,
  coupon_count       integer NOT NULL DEFAULT 0,
  paid_items_total   numeric(14,2),                        -- economics of the LAST countable version: a paid order that is later
  paid_order_total   numeric(14,2),                        --   cancelled / edited to 0 keeps what was sold (G1-Q4)
  payment_method     text,                                 -- Woo payment_method id (never the title: it can lie, DQ-03)
  payment_category   text NOT NULL,
  woo_customer_id    bigint CHECK (woo_customer_id > 0),   -- registered Woo account id (no PII); NULL = guest
  billing_country    text CHECK (billing_country ~ '^[A-Z]{2}$'),
  market             text NOT NULL CHECK (market IN ('MX', 'CO', 'ROW', 'UNKNOWN')),
  market_source      text NOT NULL,
  market_conflict    boolean NOT NULL DEFAULT false,
  first_captured_via text NOT NULL CHECK (first_captured_via IN ('webhook', 'poll', 'backfill', 'test')),
  last_captured_via  text NOT NULL CHECK (last_captured_via IN ('webhook', 'poll', 'backfill', 'test')),
  first_captured_at  timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_changed_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (target_id, woo_order_id)
);
CREATE INDEX commerce_woo_orders_paid_idx ON f360.commerce_woo_orders (target_id, first_paid_at);

-- Lines of the latest version (replaced as a whole when a newer version arrives). Product resolution is NOT stored:
-- the views resolve variant/product live through the existing links, so later homologation improves old facts.
CREATE TABLE f360.commerce_woo_order_lines (
  target_id         uuid NOT NULL,
  woo_order_id      bigint NOT NULL,
  woo_line_id       bigint NOT NULL,
  woo_product_id    bigint,
  woo_variation_id  bigint,
  sku               text,
  quantity          integer NOT NULL,
  subtotal          numeric(14,2) NOT NULL,
  subtotal_tax      numeric(14,2) NOT NULL,
  total             numeric(14,2) NOT NULL,
  total_tax         numeric(14,2) NOT NULL,
  list_price_hint   numeric(14,2),                          -- SECONDARY, PARTIAL: unit price before an implicit price rule
  list_price_source text CHECK (list_price_source IN ('wdr_initial_price')),
  PRIMARY KEY (target_id, woo_order_id, woo_line_id),
  FOREIGN KEY (target_id, woo_order_id) REFERENCES f360.commerce_woo_orders (target_id, woo_order_id) ON DELETE CASCADE
);

-- Refunds: one row per Woo refund id, independent and idempotent. Amounts stored POSITIVE.
CREATE TABLE f360.commerce_woo_refunds (
  target_id        uuid NOT NULL,
  woo_order_id     bigint NOT NULL,
  woo_refund_id    bigint NOT NULL CHECK (woo_refund_id > 0),
  amount           numeric(14,2) NOT NULL CHECK (amount >= 0),
  currency         text NOT NULL,
  refunded_at      timestamptz,
  detail_status    text NOT NULL CHECK (detail_status IN ('detailed', 'header_only')),
  product_amount   numeric(14,2),                           -- Σ refunded line totals (without tax)    [detailed only]
  shipping_amount  numeric(14,2),
  tax_amount       numeric(14,2),
  lines            jsonb,                                   -- [{woo_line_id, quantity, total, total_tax}] — never the reason text
  provenance       text NOT NULL CHECK (provenance IN ('woo_refunds_endpoint', 'woo_order_refunds_array', 'test')),
  removed_at       timestamptz,                             -- refund no longer listed by Woo (deleted) → excluded from sums
  first_seen_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (target_id, woo_order_id, woo_refund_id),
  FOREIGN KEY (target_id, woo_order_id) REFERENCES f360.commerce_woo_orders (target_id, woo_order_id) ON DELETE CASCADE
);

-- COMMERCE ATTRIBUTION V1 = Woo first-party order attribution (NOT Meta). Captured once, immutable afterwards.
CREATE TABLE f360.commerce_woo_attribution (
  target_id          uuid NOT NULL,
  woo_order_id       bigint NOT NULL,
  provenance         text NOT NULL CHECK (provenance IN ('first_party_observed')),
  model              text NOT NULL CHECK (model IN ('woo_order_attribution_last_click_session')),
  source_type        text, utm_source text, utm_medium text,
  utm_campaign       text, utm_content text, utm_term text, utm_id text,     -- opaque external values (Campaign 360 decides later)
  referrer_host      text, session_entry_path text, session_start_at timestamptz,
  session_pages      integer, session_count integer,
  device_type        text, browser_class text, os_class text,               -- classes only, never the raw user agent
  captured_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (target_id, woo_order_id),
  FOREIGN KEY (target_id, woo_order_id) REFERENCES f360.commerce_woo_orders (target_id, woo_order_id) ON DELETE CASCADE
);

-- Status transitions (append-only): never paid / paid / paid→cancelled / paid→refunded stay distinguishable forever.
CREATE TABLE f360.commerce_woo_status_log (
  id              bigserial PRIMARY KEY,
  target_id       uuid NOT NULL,
  woo_order_id    bigint NOT NULL,
  from_status     text,
  to_status       text NOT NULL,
  woo_modified_at timestamptz NOT NULL,
  via             text NOT NULL,
  at              timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX commerce_woo_status_log_order_idx ON f360.commerce_woo_status_log (target_id, woo_order_id, id);
CREATE TRIGGER commerce_woo_status_log_append_only BEFORE UPDATE OR DELETE ON f360.commerce_woo_status_log
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Source health (heartbeat) + run log: freshness is measured by successful polls, not by order activity.
CREATE TABLE f360.commerce_sync_state (
  target_id        uuid PRIMARY KEY REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  cursor_modified  timestamptz,                             -- highest Woo date_modified_gmt fully processed
  last_attempt_at  timestamptz,
  last_success_at  timestamptz,
  last_error       text,
  last_error_at    timestamptz
);
CREATE TABLE f360.commerce_sync_runs (
  id           bigserial PRIMARY KEY,
  target_id    uuid NOT NULL REFERENCES f360.sales_targets(id) ON DELETE RESTRICT,
  kind         text NOT NULL CHECK (kind IN ('poll', 'backfill')),
  started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at  timestamptz,
  ok           boolean,
  modified_after timestamptz,
  stats        jsonb,                                       -- fetched / inserted / updated / unchanged / stale / refunds / errors
  error        text
);

-- ── Pure helpers ────────────────────────────────────────────────────────────
CREATE FUNCTION f360.commerce_amount(p jsonb, p_key text) RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT round(coalesce(nullif(p->>p_key, '')::numeric, 0), 2) $$;
CREATE FUNCTION f360.commerce_ts(p text) RETURNS timestamptz LANGUAGE sql STABLE AS   -- Woo *_gmt: no zone → UTC
$$ SELECT CASE WHEN nullif(p, '') IS NULL THEN NULL WHEN p ~ '(Z|[+-]\d\d:?\d\d)$' THEN p::timestamptz ELSE (p::timestamp AT TIME ZONE 'UTC') END $$;

-- Woo created_via → business origin. "admin" in attribution source_type does NOT make an order manual: an order edited
-- later in wp-admin keeps the origin of its creation (created_via is immutable in Woo).
CREATE FUNCTION f360.commerce_business_origin(p_created_via text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_created_via IN ('store-api', 'checkout') THEN 'storefront'
              WHEN p_created_via = 'admin' THEN 'manual_admin'
              WHEN p_created_via = 'rest-api' THEN 'api_integration'
              ELSE 'unknown' END $$;

CREATE FUNCTION f360.commerce_payment_category(p_method text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN coalesce(p_method, '') = '' THEN 'unknown'
              WHEN p_method LIKE 'woo-mercado-pago%' OR p_method IN ('epayco', 'ppcp-card-button-gateway', 'stripe', 'ppcp-credit-card-gateway') THEN 'card'
              WHEN p_method LIKE 'ppcp%' OR p_method LIKE 'paypal%' THEN 'paypal'
              WHEN p_method = 'bacs' THEN 'transfer'
              WHEN p_method = 'cod' THEN 'cash'
              WHEN p_method LIKE '%prueba%' OR p_method LIKE '%test%' THEN 'test'
              ELSE 'other' END $$;

-- Which orders count as sales (G1-A §G). Paid evidence = processing / completed / refunded (Woo docs) or date_paid.
CREATE FUNCTION f360.commerce_status_class(p_status text, p_ever_paid boolean) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_status IN ('processing', 'completed', 'refunded') THEN 'countable'
              WHEN p_status IN ('pending', 'on-hold') THEN 'pending_payment'
              WHEN p_status IN ('failed', 'checkout-draft') THEN 'not_paid'
              WHEN p_status = 'cancelled' AND p_ever_paid THEN 'reversed'
              WHEN p_status = 'cancelled' THEN 'cancelled'
              WHEN p_status = 'trash' THEN 'excluded'
              ELSE 'unknown' END $$;

CREATE FUNCTION f360.commerce_market(p_currency text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_currency WHEN 'MXN' THEN 'MX' WHEN 'COP' THEN 'CO' WHEN 'USD' THEN 'ROW' ELSE 'UNKNOWN' END $$;

-- ── Capture (service role only): webhook, poll, backfill and tests all go through here ──
-- p_order is the WHITELISTED economics payload built by commerce.ts (orderEconomics): no names, emails, phones,
-- addresses, IPs, raw user agents, notes, refund reasons or Meta metadata ever reach this function.
CREATE FUNCTION public.f360_capture_order_economics(p_target_key text, p_order jsonb, p_via text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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
  t := f360.target_by_key(p_target_key);                       -- refuses unknown / inactive / production targets
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
END $$;

-- Poll / backfill bookkeeping (service role). The poll is the heartbeat: STALE = no successful poll recently.
CREATE FUNCTION public.f360_commerce_run_begin(p_target_key text, p_kind text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; s f360.commerce_sync_state; v_id bigint; v_after timestamptz;
BEGIN
  t := f360.target_by_key(p_target_key);
  INSERT INTO f360.commerce_sync_state (target_id) VALUES (t.id) ON CONFLICT (target_id) DO NOTHING;
  SELECT * INTO s FROM f360.commerce_sync_state WHERE target_id = t.id FOR UPDATE;
  -- poll: from the cursor with a 10-minute overlap (captures are idempotent); backfill: everything
  v_after := CASE WHEN p_kind = 'poll' AND s.cursor_modified IS NOT NULL THEN s.cursor_modified - interval '10 minutes' END;
  INSERT INTO f360.commerce_sync_runs (target_id, kind, modified_after) VALUES (t.id, p_kind, v_after) RETURNING id INTO v_id;
  UPDATE f360.commerce_sync_state SET last_attempt_at = clock_timestamp() WHERE target_id = t.id;
  RETURN jsonb_build_object('run_id', v_id, 'modified_after', v_after);
END $$;

CREATE FUNCTION public.f360_commerce_run_end(p_run_id bigint, p_ok boolean, p_stats jsonb, p_error text, p_cursor timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE run f360.commerce_sync_runs;
BEGIN
  UPDATE f360.commerce_sync_runs SET finished_at = clock_timestamp(), ok = p_ok, stats = p_stats, error = left(p_error, 500)
    WHERE id = p_run_id AND finished_at IS NULL RETURNING * INTO run;
  IF run.id IS NULL THEN RAISE EXCEPTION 'Corrida no encontrada o ya cerrada.'; END IF;
  IF p_ok THEN
    UPDATE f360.commerce_sync_state SET last_success_at = clock_timestamp(),
      cursor_modified = CASE WHEN p_cursor IS NULL THEN cursor_modified ELSE greatest(coalesce(cursor_modified, p_cursor), p_cursor) END
      WHERE target_id = run.target_id;
  ELSE
    UPDATE f360.commerce_sync_state SET last_error = left(p_error, 500), last_error_at = clock_timestamp() WHERE target_id = run.target_id;
  END IF;
  RETURN jsonb_build_object('run_id', run.id, 'ok', p_ok);
END $$;

-- ── Unified views (one row per sale, original currency) ─────────────────────
CREATE VIEW f360.commerce_woo_refund_totals AS
  SELECT target_id, woo_order_id, count(*) AS refunds,
         sum(amount) AS refund_total,
         sum(coalesce(product_amount, amount)) AS refund_product,             -- header-only refunds assumed product (PARTIAL)
         bool_or(detail_status = 'header_only') AS has_header_only,
         max(refunded_at) AS last_refund_at
  FROM f360.commerce_woo_refunds WHERE removed_at IS NULL GROUP BY target_id, woo_order_id;

CREATE VIEW f360.commerce_orders AS
  SELECT 'woo'::text AS source_system, o.business_origin, o.created_via, 'online'::text AS channel,
         t.key || ':' || o.woo_order_id AS external_ref, o.target_id, o.woo_order_id, NULL::uuid AS store_sale_id, NULL::uuid AS location_id,
         o.woo_created_at AS occurred_at, coalesce(o.first_paid_at, o.paid_at) AS paid_at, o.woo_status AS status,
         f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class,
         CASE WHEN NOT o.ever_paid THEN 'never_paid'
              WHEN o.woo_status = 'cancelled' THEN 'paid_cancelled'
              WHEN o.woo_status = 'refunded' OR coalesce(rt.refund_total, 0) >= coalesce(o.paid_order_total, o.order_total) AND coalesce(rt.refund_total, 0) > 0 THEN 'paid_refunded_full'
              WHEN coalesce(rt.refund_total, 0) > 0 THEN 'paid_refunded_partial'
              ELSE 'paid' END AS payment_state,
         o.market, o.currency AS currency_original, o.payment_method, o.payment_category,
         o.woo_customer_id, tx.customer_id AS loyalty_customer_id,
         CASE WHEN tx.customer_id IS NOT NULL THEN 'loyalty_member' WHEN o.woo_customer_id IS NOT NULL THEN 'registered' ELSE 'guest' END AS customer_link_status,
         o.units, o.items_subtotal AS product_gross, o.discount_total AS discount, o.items_total AS product_net,
         o.shipping_total AS shipping, o.total_tax AS tax, o.fees_total + o.fees_tax AS fees, o.order_total,
         coalesce(rt.refund_total, 0) AS refund_total, coalesce(rt.refund_product, 0) AS refund_product,
         o.items_total - least(coalesce(rt.refund_product, 0), o.items_total) AS net_product,
         o.order_total - least(coalesce(rt.refund_total, 0), o.order_total) AS net_order_total,
         o.paid_items_total, o.paid_order_total,
         CASE WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01
                OR abs((o.items_subtotal - o.items_total) - o.discount_total) > 0.01 THEN 'UNVERIFIED'
              WHEN coalesce(rt.has_header_only, false) OR o.market_conflict OR o.business_origin = 'unknown' THEN 'PARTIAL'
              ELSE 'VERIFIED' END AS data_quality,
         array_remove(ARRAY[
           CASE WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 THEN 'total_does_not_reconcile' END,
           CASE WHEN abs((o.items_subtotal - o.items_total) - o.discount_total) > 0.01 THEN 'discount_does_not_reconcile' END,
           CASE WHEN coalesce(rt.has_header_only, false) THEN 'refund_without_line_detail' END,
           CASE WHEN o.market_conflict THEN 'market_conflict_currency_vs_path' END,
           CASE WHEN o.business_origin = 'unknown' THEN 'origin_unknown' END], NULL) AS data_quality_reasons,
         'woo_order:' || o.last_captured_via AS provenance
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN LATERAL (SELECT lc.customer_id FROM public.transactions x JOIN public.loyalty_cards lc ON lc.id = x.loyalty_card_id
                     WHERE x.wc_order_id = o.woo_order_id ORDER BY x.created_at LIMIT 1) tx ON true
  UNION ALL
  -- Physical store sales: read from the authoritative record, never copied. Store sales are MXN by construction
  -- (stores are in Mexico; the store sale stores no currency) and have no discount / shipping / tax / refunds today (DW4).
  SELECT 'f360_store', 'physical_store', 'f360_rpc', 'store',
         'store_sale:' || s.id, NULL, NULL, s.id, s.location_id,
         s.created_at, s.created_at, 'completed', 'countable', 'paid',
         'MX', 'MXN', s.payment_method, CASE s.payment_method WHEN 'cash' THEN 'cash' WHEN 'card' THEN 'card' WHEN 'transfer' THEN 'transfer' ELSE 'other' END,
         NULL, s.customer_id, CASE WHEN s.customer_id IS NOT NULL THEN 'loyalty_member' ELSE 'anonymous' END,
         li.units, li.gross, 0, li.gross, 0, 0, 0, s.total, 0, 0, li.gross, s.total, li.gross, s.total,
         CASE WHEN abs(s.total - li.gross) > 0.01 THEN 'UNVERIFIED' ELSE 'VERIFIED' END,
         array_remove(ARRAY[CASE WHEN abs(s.total - li.gross) > 0.01 THEN 'total_does_not_match_lines' END, 'currency_implied_mxn'], NULL),
         'offline_sales:created_by_rpc'
  FROM public.offline_sales s
  JOIN LATERAL (SELECT coalesce(sum(i.quantity), 0)::int AS units, coalesce(sum(i.line_total), 0) AS gross FROM public.offline_sale_items i WHERE i.sale_id = s.id) li ON true
  WHERE s.created_by_rpc;
COMMENT ON VIEW f360.commerce_orders IS 'G1 Commerce Facts: one row per sale (online Woo + physical store), original currency. ACTUAL only.';

CREATE VIEW f360.commerce_order_lines AS
  SELECT 'woo'::text AS source_system, t.key || ':' || l.woo_order_id AS external_ref, l.woo_line_id::text AS line_ref,
         coalesce(vl.variant_id, rl.variant_id, lm.confirmed_variant_id) AS variant_id, v.product_id, p.category_key,
         CASE WHEN vl.variant_id IS NOT NULL THEN 'woo_variant_link' WHEN rl.variant_id IS NOT NULL THEN 'retired_woo_link'
              WHEN lm.confirmed_variant_id IS NOT NULL THEN 'legacy_homologation' ELSE 'unresolved' END AS product_resolution,
         l.sku, l.woo_product_id, l.woo_variation_id, l.quantity,
         CASE WHEN l.quantity > 0 THEN round(l.total / l.quantity, 2) END AS unit_net,
         l.subtotal AS gross, l.subtotal - l.total AS discount, l.total AS net, l.total_tax AS tax,
         l.list_price_hint, l.list_price_source, o.currency AS currency_original
  FROM f360.commerce_woo_order_lines l
  JOIN f360.commerce_woo_orders o ON o.target_id = l.target_id AND o.woo_order_id = l.woo_order_id
  JOIN f360.sales_targets t ON t.id = l.target_id
  LEFT JOIN f360.woo_variant_links vl ON vl.target_id = l.target_id AND vl.woo_variation_id = l.woo_variation_id
  LEFT JOIN f360.retired_woo_links rl ON rl.target_id = l.target_id AND rl.woo_variation_id = l.woo_variation_id
  LEFT JOIN f360.legacy_woo_map lm ON lm.target_id = l.target_id AND lm.woo_variation_id = l.woo_variation_id AND lm.status = 'confirmado'
  LEFT JOIN f360.product_variants v ON v.id = coalesce(vl.variant_id, rl.variant_id, lm.confirmed_variant_id)
  LEFT JOIN f360.products p ON p.id = v.product_id
  UNION ALL
  SELECT 'f360_store', 'store_sale:' || i.sale_id, i.line_no::text, i.variant_id, v.product_id, p.category_key,
         CASE WHEN i.variant_id IS NOT NULL THEN 'f360_variant' ELSE 'legacy_store_item' END,
         i.sku, NULL, NULL, i.quantity, i.unit_price, i.line_total, 0, i.line_total, 0, NULL, NULL, 'MXN'
  FROM public.offline_sale_items i JOIN public.offline_sales s ON s.id = i.sale_id AND s.created_by_rpc
  LEFT JOIN f360.product_variants v ON v.id = i.variant_id LEFT JOIN f360.products p ON p.id = v.product_id;

-- Freshness per online source. Poll every 15 min (cron below) → STALE after 60 min without a successful poll.
CREATE VIEW f360.commerce_source_health AS
  SELECT t.key AS target_key, s.last_attempt_at, s.last_success_at, s.last_error, s.last_error_at, s.cursor_modified,
         (SELECT max(d.received_at) FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.result IN ('applied', 'not_paid', 'duplicate')) AS last_webhook_at,
         CASE WHEN s.last_success_at IS NULL THEN 'UNVERIFIED'
              WHEN s.last_success_at < now() - interval '60 minutes' THEN 'STALE'
              ELSE 'VERIFIED' END AS freshness
  FROM f360.sales_targets t LEFT JOIN f360.commerce_sync_state s ON s.target_id = t.id
  WHERE t.active AND NOT t.is_production;

-- ── Read surface (owner / operator) ─────────────────────────────────────────
-- Metrics per currency × market × origin × channel, over COUNTABLE sales only (never_paid / cancelled never inflate).
-- product_sales = Σ line.total (after coupons, no shipping, no tax); aov_product = product_sales ÷ orders;
-- average_order_total = Σ order_total ÷ orders. Never summed across currencies.
CREATE FUNCTION public.f360_commerce_summary(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_from timestamptz; v_to timestamptz;
BEGIN
  r := f360.require_role('operator');
  v_from := CASE WHEN p_from IS NULL THEN '-infinity'::timestamptz ELSE p_from::timestamp AT TIME ZONE 'America/Mexico_City' END;
  v_to := CASE WHEN p_to IS NULL THEN 'infinity'::timestamptz ELSE (p_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City' END;
  RETURN jsonb_build_object(
    'from', p_from, 'to', p_to, 'kind', 'ACTUAL',
    'groups', (SELECT coalesce(jsonb_agg(g ORDER BY g->>'currency', g->>'market', g->>'origin', g->>'channel'), '[]'::jsonb) FROM (
      SELECT jsonb_build_object('currency', c.currency_original, 'market', c.market, 'origin', c.business_origin, 'channel', c.channel,
        'orders', count(*), 'units', sum(c.units),
        'product_gross', sum(c.product_gross), 'discounts', sum(c.discount), 'product_sales', sum(c.product_net),
        'shipping', sum(c.shipping), 'tax', sum(c.tax), 'fees', sum(c.fees), 'order_total', sum(c.order_total),
        'refunds', sum(c.refund_total), 'net_product_sales', sum(c.net_product),
        'aov_product', round(sum(c.product_net) / count(*), 2), 'average_order_total', round(sum(c.order_total) / count(*), 2),
        'quality', jsonb_build_object('VERIFIED', count(*) FILTER (WHERE c.data_quality = 'VERIFIED'), 'PARTIAL', count(*) FILTER (WHERE c.data_quality = 'PARTIAL'),
                                      'UNVERIFIED', count(*) FILTER (WHERE c.data_quality = 'UNVERIFIED'))) AS g
      FROM f360.commerce_orders c
      WHERE c.status_class = 'countable' AND c.paid_at >= v_from AND c.paid_at < v_to
      GROUP BY c.currency_original, c.market, c.business_origin, c.channel) q),
    'not_counted', (SELECT coalesce(jsonb_agg(jsonb_build_object('currency', x.currency_original, 'payment_state', x.payment_state, 'status_class', x.status_class,
                      'orders', x.n, 'order_total', x.tot, 'paid_order_total', x.paid_tot) ORDER BY x.currency_original, x.payment_state), '[]'::jsonb) FROM (
      SELECT c.currency_original, c.payment_state, c.status_class, count(*) AS n, sum(c.order_total) AS tot, sum(c.paid_order_total) AS paid_tot
      FROM f360.commerce_orders c WHERE c.status_class <> 'countable' AND c.occurred_at >= v_from AND c.occurred_at < v_to
      GROUP BY 1, 2, 3) x),
    'payment_states', (SELECT coalesce(jsonb_object_agg(ps, n), '{}'::jsonb) FROM (SELECT payment_state AS ps, count(*) AS n FROM f360.commerce_orders c
                        WHERE coalesce(c.paid_at, c.occurred_at) >= v_from AND coalesce(c.paid_at, c.occurred_at) < v_to GROUP BY 1) y),
    'sources', (SELECT coalesce(jsonb_agg(jsonb_build_object('target', h.target_key, 'freshness', h.freshness, 'last_success_at', h.last_success_at,
                  'last_attempt_at', h.last_attempt_at, 'last_error', h.last_error, 'last_webhook_at', h.last_webhook_at)), '[]'::jsonb) FROM f360.commerce_source_health h),
    'meta_purchase_signal', 'UNVERIFIED_CONFLICTED (DQ-01): not used for orders, revenue, AOV, CPA or ROAS');
END $$;

-- Technical list for validation (no PII: ids, states, amounts, origin, first-party source).
CREATE FUNCTION public.f360_commerce_facts(p_limit int DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x->>'occurred_at' DESC), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('ref', c.external_ref, 'channel', c.channel, 'origin', c.business_origin, 'created_via', c.created_via,
      'occurred_at', c.occurred_at, 'paid_at', c.paid_at, 'status', c.status, 'status_class', c.status_class, 'payment_state', c.payment_state,
      'market', c.market, 'currency', c.currency_original, 'units', c.units, 'product_sales', c.product_net, 'order_total', c.order_total,
      'refunds', c.refund_total, 'customer_link', c.customer_link_status, 'quality', c.data_quality, 'quality_reasons', to_jsonb(c.data_quality_reasons),
      'source_type', a.source_type, 'utm_source', a.utm_source, 'utm_medium', a.utm_medium) AS x
    FROM f360.commerce_orders c
    LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = c.target_id AND a.woo_order_id = c.woo_order_id
    ORDER BY c.occurred_at DESC NULLS LAST LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) q);
END $$;

-- ── D-G1-05: financial planning is owner/operator only (was viewer, which included sellers) ──
CREATE OR REPLACE FUNCTION public.f360_growth_plan(p_year integer) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; gp f360.growth_plans;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO gp FROM f360.growth_plans WHERE plan_year = p_year;
  RETURN jsonb_build_object(
    'year', p_year,
    'plan', CASE WHEN gp.plan_year IS NULL THEN NULL ELSE jsonb_build_object('north_star', gp.north_star, 'note', gp.note, 'updated_by_name', gp.updated_by_name, 'updated_at', gp.updated_at) END,
    'scenarios', (SELECT coalesce(jsonb_object_agg(kind, jsonb_build_object('inputs', inputs, 'updated_by_name', updated_by_name, 'updated_at', updated_at)), '{}')
                  FROM f360.growth_scenarios WHERE plan_year = p_year),
    'reported_figures', (SELECT coalesce(jsonb_agg(to_jsonb(f) - 'currency' ORDER BY f.period DESC, f.created_at DESC), '[]') FROM f360.reported_figures f),
    'changes', (SELECT coalesce(jsonb_agg(jsonb_build_object('what', what, 'by', by_name, 'at', at) ORDER BY id DESC), '[]')
                FROM (SELECT * FROM f360.growth_plan_changes WHERE plan_year = p_year ORDER BY id DESC LIMIT 10) c),
    'can_edit', r.role = 'owner');
END $$;

-- ── Heartbeat poll (every 15 min): POST f360-woo-sync {action:"commerce_poll"}. URL + Bearer from Vault (no-op without). ──
CREATE FUNCTION f360.commerce_poll_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"commerce_poll"}'::jsonb, timeout_milliseconds := 55000);
END $$;
SELECT cron.schedule('f360-commerce-poll', '*/15 * * * *', 'SELECT f360.commerce_poll_tick()');

-- ── Grants: tables/views service-role only; reads through owner/operator RPCs ──
REVOKE ALL ON f360.commerce_woo_orders, f360.commerce_woo_order_lines, f360.commerce_woo_refunds, f360.commerce_woo_attribution,
  f360.commerce_woo_status_log, f360.commerce_sync_state, f360.commerce_sync_runs,
  f360.commerce_woo_refund_totals, f360.commerce_orders, f360.commerce_order_lines, f360.commerce_source_health FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.commerce_woo_orders, f360.commerce_woo_order_lines, f360.commerce_woo_refunds, f360.commerce_woo_attribution,
  f360.commerce_woo_status_log, f360.commerce_sync_state, f360.commerce_sync_runs TO service_role;
GRANT SELECT ON f360.commerce_woo_refund_totals, f360.commerce_orders, f360.commerce_order_lines, f360.commerce_source_health TO service_role;
GRANT USAGE ON SEQUENCE f360.commerce_woo_status_log_id_seq, f360.commerce_sync_runs_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_capture_order_economics(text, jsonb, text), public.f360_commerce_run_begin(text, text),
  public.f360_commerce_run_end(bigint, boolean, jsonb, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_capture_order_economics(text, jsonb, text), public.f360_commerce_run_begin(text, text),
  public.f360_commerce_run_end(bigint, boolean, jsonb, text, timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.f360_commerce_summary(date, date), public.f360_commerce_facts(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_commerce_summary(date, date), public.f360_commerce_facts(int) TO authenticated, service_role;
