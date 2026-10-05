-- Fuxia 360 · Panel ejecutivo (centro de control) — ONE read-only aggregate RPC for the admin dashboard. STAGING.
-- Decision: Mario 2026-10-05 (internal view + presentation view; real data, never invented).
-- Sources (no new source of truth): f360.commerce_orders / commerce_order_lines (G1, financial truth), f360.historical_sales_active
-- (Carolina's pre-F360 summaries), reservations, online_store_shipments, made_to_order, customer_cases (pay links),
-- loyalty_holds, customers / loyalty_cards (CRM C1), inventory_balances, commerce_source_health.
-- Rules:
--   * Money: net product sales (product net − product refunds) in the ORIGINAL currency. The headline is MXN; COP/USD are
--     returned apart and never summed with MXN. Historical summaries are MXN and only count in periods they cover.
--   * Test orders (sales_targets.is_test) are excluded — EXCEPT in a database with no production target (staging), where they
--     are included and the response says so (`includes_test_data`). Decided server-side; the client cannot ask for it.
--   * No personal data in the aggregate. Birthday names (first name + initial) only for customer_pii_viewers and never in
--     the presentation view.
--   * owner/operator only (same as Ventas / Growth).
-- Rollback: supabase/rollbacks/20261010000300_f360_exec_dashboard.down.sql

CREATE FUNCTION public.f360_exec_dashboard(p_period text DEFAULT 'mes', p_presentation boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
  r f360.user_roles := f360.require_role('operator');
  tz text := 'America/Mexico_City';
  today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  incl_test boolean := NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE is_production);
  per text := CASE WHEN p_period IN ('hoy', 'semana', 'mes', 'anio') THEN p_period ELSE 'mes' END;
  d0 date; d1 date; p0 date; p1 date; ndays int;
  pii boolean := EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid()) AND NOT coalesce(p_presentation, false);
  res jsonb;
BEGIN
  -- period [d0, d1] and the previous period of the same length [p0, p1]
  IF per = 'hoy' THEN d0 := today; d1 := today; p0 := today - 7; p1 := today - 7;                       -- vs same weekday last week
  ELSIF per = 'semana' THEN d0 := today - 6; d1 := today; p0 := today - 13; p1 := today - 7;
  ELSIF per = 'mes' THEN d0 := date_trunc('month', today)::date; d1 := today; ndays := today - d0;
        p0 := (date_trunc('month', today) - interval '1 month')::date; p1 := least(p0 + ndays, d0 - 1);
  ELSE  d0 := date_trunc('year', today)::date; d1 := today; ndays := today - d0;
        p0 := (date_trunc('year', today) - interval '1 year')::date; p1 := p0 + ndays;
  END IF;

  WITH
  ord AS (
    SELECT o.*, (o.paid_at AT TIME ZONE tz)::date AS d FROM f360.commerce_orders o
    LEFT JOIN f360.sales_targets t ON t.id = o.target_id
    WHERE o.status_class = 'countable' AND o.paid_at IS NOT NULL AND (incl_test OR coalesce(t.is_test, false) = false)),
  cur AS (SELECT * FROM ord WHERE d BETWEEN d0 AND d1),
  prv AS (SELECT * FROM ord WHERE d BETWEEN p0 AND p1),
  hist AS (SELECT * FROM f360.historical_sales_active),
  hcur AS (SELECT coalesce(sum(amount), 0) amt, coalesce(sum(pairs), 0) prs FROM hist WHERE period_start >= d0 AND period_end <= d1),
  hprv AS (SELECT coalesce(sum(amount), 0) amt, coalesce(sum(pairs), 0) prs FROM hist WHERE period_start >= p0 AND period_end <= p1),
  k AS (
    SELECT (SELECT coalesce(sum(net_product), 0) FROM cur WHERE currency_original = 'MXN') + (SELECT amt FROM hcur) AS sales,
           (SELECT coalesce(sum(net_product), 0) FROM prv WHERE currency_original = 'MXN') + (SELECT amt FROM hprv) AS sales_prev,
           (SELECT coalesce(sum(units), 0) FROM cur) + (SELECT prs FROM hcur) AS pairs,
           (SELECT coalesce(sum(units), 0) FROM prv) + (SELECT prs FROM hprv) AS pairs_prev,
           (SELECT count(*) FROM cur WHERE currency_original = 'MXN') AS orders_mxn,
           (SELECT coalesce(sum(net_product), 0) FROM cur WHERE currency_original = 'MXN') AS sales_lines_mxn,
           (SELECT count(*) FROM cur WHERE channel = 'store') AS store_orders,
           (SELECT count(*) FROM cur WHERE channel = 'store' AND loyalty_customer_id IS NOT NULL) AS store_identified,
           (SELECT amt FROM hcur) AS hist_amount)
  SELECT jsonb_build_object(
    'period', per, 'from', d0, 'to', d1, 'prev_from', p0, 'prev_to', p1, 'generated_at', now(),
    'includes_test_data', incl_test, 'presentation', coalesce(p_presentation, false),
    'kpis', (SELECT jsonb_build_object(
        'sales', k.sales, 'sales_prev', k.sales_prev, 'pairs', k.pairs, 'pairs_prev', k.pairs_prev,
        'orders', k.orders_mxn, 'ticket', CASE WHEN k.orders_mxn > 0 THEN round(k.sales_lines_mxn / k.orders_mxn, 2) END,
        'store_identified_pct', CASE WHEN k.store_orders > 0 THEN round(100.0 * k.store_identified / k.store_orders) END,
        'historical_included', k.hist_amount, 'currency', 'MXN') FROM k),
    'other_currencies', coalesce((SELECT jsonb_agg(jsonb_build_object('currency', currency_original, 'sales', s, 'orders', n) ORDER BY currency_original)
        FROM (SELECT currency_original, sum(net_product) s, count(*) n FROM cur WHERE currency_original <> 'MXN' GROUP BY 1) x), '[]'),
    'mix', (SELECT jsonb_build_object(
        'store', coalesce(sum(net_product) FILTER (WHERE channel = 'store'), 0) + (SELECT amt FROM hcur),
        'online', coalesce(sum(net_product) FILTER (WHERE channel <> 'store'), 0)) FROM cur WHERE currency_original = 'MXN'),
    'daily', (SELECT jsonb_agg(jsonb_build_object('d', g::date,
        'store', coalesce((SELECT sum(net_product) FROM ord o WHERE o.d = g::date AND o.channel = 'store' AND o.currency_original = 'MXN'), 0),
        'online', coalesce((SELECT sum(net_product) FROM ord o WHERE o.d = g::date AND o.channel <> 'store' AND o.currency_original = 'MXN'), 0)) ORDER BY g)
      FROM generate_series(today - 29, today, interval '1 day') g),
    'by_location', coalesce((SELECT jsonb_agg(jsonb_build_object('name', name, 'kind', kind, 'sales', s, 'pairs', prs, 'historical', h) ORDER BY s DESC) FROM (
        SELECT coalesce(l.name, 'Tienda') name, 'store' kind, sum(c.net_product) s, sum(c.units) prs, false h
          FROM cur c LEFT JOIN f360.locations l ON l.id = c.location_id WHERE c.channel = 'store' AND c.currency_original = 'MXN' GROUP BY 1
        UNION ALL
        SELECT 'En línea (México)', 'online', sum(net_product), sum(units), false FROM cur WHERE channel <> 'store' AND currency_original = 'MXN' HAVING count(*) > 0
        UNION ALL
        SELECT place, place_type, sum(amount), sum(pairs), true FROM hist WHERE period_start >= d0 AND period_end <= d1 GROUP BY place, place_type) x), '[]'),
    'top_models', coalesce((SELECT jsonb_agg(jsonb_build_object('name', name, 'pairs', u, 'sales', s, 'sizes', sz) ORDER BY u DESC) FROM (
        SELECT p.name, sum(ln.quantity) u, sum(ln.net) FILTER (WHERE ln.currency_original = 'MXN') s,
               (SELECT jsonb_agg(z ORDER BY q DESC) FROM (SELECT v.size_label z, sum(l2.quantity) q FROM f360.commerce_order_lines l2
                  JOIN ord o2 ON o2.source_system = l2.source_system AND o2.external_ref = l2.external_ref
                  JOIN f360.product_variants v ON v.id = l2.variant_id
                  WHERE l2.product_id = p.id AND o2.d >= today - 89 GROUP BY 1 ORDER BY 2 DESC LIMIT 2) zz) sz
        FROM f360.commerce_order_lines ln JOIN ord o ON o.source_system = ln.source_system AND o.external_ref = ln.external_ref
        JOIN f360.products p ON p.id = ln.product_id
        WHERE o.d >= today - 89 GROUP BY p.id, p.name ORDER BY u DESC LIMIT 5) t), '[]'),
    'heatmap', (WITH top AS (
          SELECT ln.product_id, p.name, sum(ln.quantity) u FROM f360.commerce_order_lines ln
          JOIN ord o ON o.source_system = ln.source_system AND o.external_ref = ln.external_ref
          JOIN f360.products p ON p.id = ln.product_id WHERE o.d >= today - 89 GROUP BY 1, 2 ORDER BY u DESC LIMIT 5),
        sold AS (
          SELECT ln.product_id, v.size_label, sum(ln.quantity) q FROM f360.commerce_order_lines ln
          JOIN ord o ON o.source_system = ln.source_system AND o.external_ref = ln.external_ref
          JOIN f360.product_variants v ON v.id = ln.variant_id WHERE o.d >= today - 89 AND ln.product_id IN (SELECT product_id FROM top) GROUP BY 1, 2),
        stock AS (
          SELECT v.product_id, v.size_label, coalesce(sum(b.on_hand) FILTER (WHERE l.id IS NOT NULL), 0) oh FROM f360.product_variants v
          LEFT JOIN f360.inventory_balances b ON b.variant_id = v.id
          LEFT JOIN f360.locations l ON l.id = b.location_id AND l.type <> 'transit'
          WHERE v.product_id IN (SELECT product_id FROM top) AND v.status <> 'archived' GROUP BY 1, 2),
        sizes AS (SELECT DISTINCT size_label FROM stock)
      SELECT jsonb_build_object(
        'sizes', coalesce((SELECT jsonb_agg(size_label ORDER BY nullif(regexp_replace(size_label, '[^0-9.]', '', 'g'), '')::numeric NULLS LAST, size_label) FROM sizes), '[]'),
        'rows', coalesce((SELECT jsonb_agg(jsonb_build_object('name', t.name, 'cells',
            (SELECT jsonb_object_agg(s.size_label, jsonb_build_object('sold', coalesce(so.q, 0), 'on_hand', st.oh))
             FROM sizes s LEFT JOIN sold so ON so.product_id = t.product_id AND so.size_label = s.size_label
             LEFT JOIN stock st ON st.product_id = t.product_id AND st.size_label = s.size_label)) ORDER BY t.u DESC) FROM top t), '[]'))),
    'pipeline', jsonb_build_object(
      'reservations', (SELECT jsonb_build_object('count', count(*), 'value', coalesce(sum(coalesce(nullif(p.sale_price, 0), p.regular_price)), 0),
          'expiring_48h', count(*) FILTER (WHERE rs.expires_at < now() + interval '48 hours'))
        FROM f360.reservations rs JOIN f360.product_variants v ON v.id = rs.variant_id JOIN f360.products p ON p.id = v.product_id
        WHERE rs.status = 'activa' AND rs.expires_at > now()),
      'to_ship', (SELECT jsonb_build_object('orders', count(DISTINCT (s.target_id, s.woo_order_id)), 'pairs', coalesce(sum(s.quantity), 0))
        FROM f360.online_store_shipments s LEFT JOIN f360.sales_targets t ON t.id = s.target_id
        WHERE s.status = 'por_enviar' AND (incl_test OR NOT coalesce(t.is_test, false))),
      'made_to_order', (SELECT jsonb_build_object('count', count(*), 'pairs', coalesce(sum(m.quantity), 0))
        FROM f360.made_to_order m LEFT JOIN f360.sales_targets t ON t.id = m.target_id
        WHERE m.status IN ('pendiente', 'en_proceso') AND (incl_test OR NOT coalesce(t.is_test, false))),
      'pay_links', (SELECT jsonb_build_object('open', count(*)) FROM f360.customer_cases WHERE kind = 'link_pago' AND status IN ('nueva', 'en_atencion')),
      'held_points', (SELECT jsonb_build_object('points', coalesce(sum(public.loyalty_pairs_for_lines(lines)), 0) * public.loyalty_points_per_pair(),
          'customers', count(DISTINCT customer_id)) FROM f360.loyalty_holds WHERE status = 'held')),
    'crm', jsonb_build_object(
      'customers', (SELECT count(*) FROM public.customers WHERE role = 'customer'),
      'new_in_period', (SELECT count(*) FROM public.customers WHERE role = 'customer' AND (created_at AT TIME ZONE tz)::date BETWEEN d0 AND d1),
      'by_source', coalesce((SELECT jsonb_object_agg(source, n) FROM (SELECT source, count(*) n FROM public.customers
          WHERE role = 'customer' AND (created_at AT TIME ZONE tz)::date BETWEEN d0 AND d1 GROUP BY 1) x), '{}'),
      'tiers', (SELECT jsonb_build_object('gold', count(*) FILTER (WHERE lc.tier = 'gold'), 'silver', count(*) FILTER (WHERE lc.tier = 'silver'),
          'bronze', count(*) FILTER (WHERE lc.tier = 'bronze')) FROM public.loyalty_cards lc JOIN public.customers c ON c.id = lc.customer_id WHERE c.role = 'customer'),
      'marketing_consent', (SELECT count(DISTINCT customer_id) FROM f360.customer_consent_state WHERE kind = 'marketing' AND status = 'granted'),
      'birthdays_month', (SELECT count(*) FROM public.customers WHERE role = 'customer' AND birthday_month = extract(month FROM today)),
      'birthdays', CASE WHEN pii THEN coalesce((SELECT jsonb_agg(jsonb_build_object('name', nm, 'day', birthday_day, 'size', shoe_size) ORDER BY birthday_day) FROM (
          SELECT initcap(split_part(btrim(name), ' ', 1)) || coalesce(' ' || upper(left(nullif(split_part(btrim(name), ' ', 2), ''), 1)) || '.', '') nm, birthday_day, shoe_size
          FROM public.customers WHERE role = 'customer' AND birthday_month = extract(month FROM today) AND birthday_day >= extract(day FROM today)
          ORDER BY birthday_day LIMIT 8) b), '[]') END),
    'inventory', coalesce((SELECT jsonb_agg(jsonb_build_object('name', name, 'type', type, 'pairs', prs, 'value', val) ORDER BY val DESC) FROM (
        SELECT l.name, l.type, sum(b.on_hand) prs, sum(b.on_hand * coalesce(nullif(p.sale_price, 0), p.regular_price, 0)) val
        FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id
        JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
        WHERE b.on_hand > 0 GROUP BY l.id, l.name, l.type) x), '[]'),
    'feed', coalesce((SELECT jsonb_agg(jsonb_build_object('at', paid_at, 'channel', channel, 'place', place, 'item', item, 'amount', net_product, 'currency', currency_original) ORDER BY paid_at DESC) FROM (
        SELECT o.paid_at, o.channel, o.net_product, o.currency_original,
               CASE WHEN o.channel = 'store' THEN coalesce(l.name, 'Tienda') ELSE 'En línea' END place,
               (SELECT coalesce(p.name, 'Producto') || coalesce(' ' || v.size_label, '') FROM f360.commerce_order_lines ln
                  LEFT JOIN f360.products p ON p.id = ln.product_id LEFT JOIN f360.product_variants v ON v.id = ln.variant_id
                  WHERE ln.source_system = o.source_system AND ln.external_ref = o.external_ref ORDER BY ln.line_ref LIMIT 1) item
        FROM ord o LEFT JOIN f360.locations l ON l.id = o.location_id ORDER BY o.paid_at DESC LIMIT 8) f), '[]'),
    'trust', jsonb_build_object(
      'sources', coalesce((SELECT jsonb_agg(jsonb_build_object('target', target_key, 'freshness', freshness, 'last_success_at', last_success_at)) FROM f360.commerce_source_health), '[]'),
      'historical_loads', (SELECT count(*) FROM f360.historical_sales_active),
      'unresolved_lines', (SELECT count(*) FROM f360.commerce_order_lines WHERE identity_link_state = 'unresolved'))
  ) INTO res FROM k;
  RETURN res;
END $$;

REVOKE ALL ON FUNCTION public.f360_exec_dashboard(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_exec_dashboard(text, boolean) TO authenticated;
