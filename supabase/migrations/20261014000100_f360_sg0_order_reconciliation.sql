-- Fuxia 360 · S-G0 Measurement Truth · D2 ORDER RECONCILIATION (Mario 2026-10-08, P0: "Woo order exists BUT Fuxia 360 order
-- missing" must be detected and recovered idempotently, with logging, health, last successful run, detected, recovered, errors).
-- Spec: docs/fuxia360/growth/09_GROWTH_IMPLEMENTATION_PLAN.md §S-G0 (1)(2); delivery: docs/fuxia360/growth/S-G0_DELIVERY.md.
-- ADDITIVE / compatible:
--   · f360.sg0_order_target(key): the order-path guard of 20261012001100 (f360.orders_target) written so it ALSO works on a
--     database where that migration is not applied yet (staging): production only when orders_mode = 'on' (read through
--     to_jsonb, no hard column reference); every other channel exactly as f360.target_by_key.
--   · commerce_sync_runs.kind gains 'reconcile' (CHECK widened; existing rows untouched).
--   · public.f360_commerce_reconcile_begin(key, lookback_hours): opens a reconcile run. Window: explicit lookback (deep check)
--     → else the cursor − 10 min (incremental) → else from the cutover order's creation − 1 day (first run in production)
--     → else the last 72 h.
--   · public.f360_commerce_reconcile_diff(key, orders[{id, date_modified_gmt}]): READ-ONLY comparison of a Woo page with Fuxia 360:
--     missing (Woo has it, F360 not, after the cutover) / outdated (Woo modified later than F360's version) /
--     before_cutover_missing (belongs to the history import, never recovered as "realtime") / current.
--     The capture itself stays the ONE existing writer (public.f360_capture_order_economics, key (target, woo_order_id)):
--     a duplicate order cannot exist.
--   · f360.commerce_source_health: production now appears when its order path is on (was hidden: `active AND NOT is_production`,
--     20261008000100:455). Same columns.
--   · public.f360_channel_mode also returns orders_mode / orders_since_id (when the column exists) so the sync function can
--     gate the reconciliation by ORDERS, not by stock (f360-woo-sync/handler.ts:59-60).
-- Nothing here touches inventory (woo_orders / inventory_events), order_shipping, loyalty or prices.
-- Rollback: supabase/rollbacks/20261014000100_f360_sg0_order_reconciliation.down.sql

CREATE FUNCTION f360.sg0_order_target(p_key text) RETURNS f360.sales_targets
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda % no configurada.', p_key; END IF;
  IF t.is_production THEN
    IF coalesce(to_jsonb(t)->>'orders_mode', 'off') <> 'on' THEN RAISE EXCEPTION 'Los pedidos de la tienda de producción no están encendidos.'; END IF;
    RETURN t;
  END IF;
  RETURN f360.target_by_key(p_key);   -- every non-production channel: exactly as before (active, not production)
END $$;
REVOKE ALL ON FUNCTION f360.sg0_order_target(text) FROM PUBLIC, anon, authenticated;

-- Does this channel feed orders to Fuxia 360? (staging: active test channels; production: orders_mode = 'on')
CREATE FUNCTION f360.sg0_orders_path_on(t f360.sales_targets) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (t.active AND NOT t.is_production) OR (t.is_production AND coalesce(to_jsonb(t)->>'orders_mode', 'off') = 'on') $$;
REVOKE ALL ON FUNCTION f360.sg0_orders_path_on(f360.sales_targets) FROM PUBLIC, anon, authenticated;

ALTER TABLE f360.commerce_sync_runs DROP CONSTRAINT commerce_sync_runs_kind_check;
ALTER TABLE f360.commerce_sync_runs ADD CONSTRAINT commerce_sync_runs_kind_check CHECK (kind IN ('poll', 'backfill', 'reconcile'));

CREATE FUNCTION public.f360_commerce_reconcile_begin(p_target_key text, p_lookback_hours integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; s f360.commerce_sync_state; v_id bigint; v_after timestamptz; v_since bigint; v_mode text;
BEGIN
  t := f360.sg0_order_target(p_target_key);
  IF p_lookback_hours IS NOT NULL AND (p_lookback_hours < 1 OR p_lookback_hours > 24 * 800) THEN
    RAISE EXCEPTION 'La ventana de revisión debe ser de 1 hora a 800 días.';
  END IF;
  v_since := nullif(to_jsonb(t)->>'orders_since_id', '')::bigint;
  INSERT INTO f360.commerce_sync_state (target_id) VALUES (t.id) ON CONFLICT (target_id) DO NOTHING;
  SELECT * INTO s FROM f360.commerce_sync_state WHERE target_id = t.id FOR UPDATE;
  IF p_lookback_hours IS NOT NULL THEN
    v_after := clock_timestamp() - make_interval(hours => p_lookback_hours); v_mode := 'deep';
  ELSIF s.cursor_modified IS NOT NULL THEN
    v_after := s.cursor_modified - interval '10 minutes'; v_mode := 'incremental';
  ELSE
    -- first run: from the cutover order (production) so nothing between the cutover and the first run is skipped
    SELECT o.woo_created_at - interval '1 day' INTO v_after FROM f360.commerce_woo_orders o
      WHERE o.target_id = t.id AND v_since IS NOT NULL AND o.woo_order_id = v_since;
    v_after := coalesce(v_after, clock_timestamp() - interval '72 hours'); v_mode := 'first_run';
  END IF;
  INSERT INTO f360.commerce_sync_runs (target_id, kind, modified_after) VALUES (t.id, 'reconcile', v_after) RETURNING id INTO v_id;
  UPDATE f360.commerce_sync_state SET last_attempt_at = clock_timestamp() WHERE target_id = t.id;
  RETURN jsonb_build_object('run_id', v_id, 'modified_after', v_after, 'orders_since_id', v_since, 'mode', v_mode);
END $$;

CREATE FUNCTION public.f360_commerce_reconcile_diff(p_target_key text, p_orders jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; v_since bigint; res jsonb;
BEGIN
  t := f360.sg0_order_target(p_target_key);
  IF jsonb_typeof(p_orders) IS DISTINCT FROM 'array' OR jsonb_array_length(p_orders) > 500 THEN
    RAISE EXCEPTION 'Lista de pedidos no válida (máximo 500 por página).';
  END IF;
  v_since := nullif(to_jsonb(t)->>'orders_since_id', '')::bigint;
  WITH w AS (
    SELECT DISTINCT ON ((x->>'id')::bigint) (x->>'id')::bigint AS id, f360.commerce_ts(x->>'date_modified_gmt') AS m
    FROM jsonb_array_elements(p_orders) x WHERE (x->>'id') ~ '^[1-9][0-9]{0,17}$'),
  c AS (
    SELECT w.id, w.m, o.woo_order_id IS NOT NULL AS known, o.woo_modified_at
    FROM w LEFT JOIN f360.commerce_woo_orders o ON o.target_id = t.id AND o.woo_order_id = w.id)
  SELECT jsonb_build_object(
    'missing', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE NOT c.known AND (v_since IS NULL OR c.id > v_since)), '[]'),
    'before_cutover_missing', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE NOT c.known AND v_since IS NOT NULL AND c.id <= v_since), '[]'),
    'outdated', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE c.known AND c.m IS NOT NULL AND c.m > c.woo_modified_at), '[]'),
    'current', count(*) FILTER (WHERE c.known AND NOT (c.m IS NOT NULL AND c.m > c.woo_modified_at)),
    'orders_since_id', v_since)
  INTO res FROM c;
  RETURN res;
END $$;

-- Production appears when its ORDER path is on (it was hidden by `active AND NOT is_production`). Same columns.
CREATE OR REPLACE VIEW f360.commerce_source_health AS
  SELECT t.key AS target_key, s.last_attempt_at, s.last_success_at, s.last_error, s.last_error_at, s.cursor_modified,
         (SELECT max(d.received_at) FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.result IN ('applied', 'not_paid', 'duplicate')) AS last_webhook_at,
         CASE WHEN s.last_success_at IS NULL THEN 'UNVERIFIED'
              WHEN s.last_success_at < now() - interval '60 minutes' THEN 'STALE'
              ELSE 'VERIFIED' END AS freshness
  FROM f360.sales_targets t LEFT JOIN f360.commerce_sync_state s ON s.target_id = t.id
  WHERE f360.sg0_orders_path_on(t);

-- + orders_mode / orders_since_id (NULL where the column does not exist yet). Same signature, same callers.
CREATE OR REPLACE FUNCTION public.f360_channel_mode(p_target_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('key', key, 'is_production', is_production, 'active', active, 'catalog_mode', catalog_mode,
    'stock_sync_mode', stock_sync_mode, 'stock_policy', stock_policy,
    'orders_mode', to_jsonb(t)->'orders_mode', 'orders_since_id', to_jsonb(t)->'orders_since_id')
  FROM f360.sales_targets t WHERE key = p_target_key
$$;

REVOKE ALL ON FUNCTION public.f360_commerce_reconcile_begin(text, integer), public.f360_commerce_reconcile_diff(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_commerce_reconcile_begin(text, integer), public.f360_commerce_reconcile_diff(text, jsonb) TO service_role;
REVOKE ALL ON f360.commerce_source_health FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.commerce_source_health TO service_role;
REVOKE ALL ON FUNCTION public.f360_channel_mode(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_channel_mode(text) TO service_role;
