-- Fuxia 360 · Conciliación → Growth War Room (Mario 2026-10-10: STAGING only). ADDITIVE.
-- Authorized analytics exclusions (f360.sales_rec_exclusions, append-only, explicit action + reason + who/when, reversible by a
-- new event) are shown as a SEPARATE adjustment per market. The original WooCommerce KPIs are never changed.
-- Rules:
--   · only the CURRENT exclusion state counts (latest event per order) → an order is subtracted at most once;
--   · a human classification (prueba / duplicado / …) alone never excludes anything;
--   · the effect of an excluded order = what it contributes to the original KPI: a countable (paid) order subtracts its
--     net_product (already net of refunds) and 1 order; an order that is refunded in full / cancelled after payment
--     (status_class 'reversed') or never paid already counts 0 → no effect (no double subtraction);
--   · detail (order ids, reasons, who) only for customer_pii_viewers; operators see totals only.
-- Depends on 20261021000100 (cockpit) and 20261022000100 (reconciliation).
-- Rollback: supabase/rollbacks/20261022000200_f360_growth_exclusions.down.sql

CREATE FUNCTION f360.growth_adjustments(p_market text, p_from timestamptz, p_to timestamptz, p_detail boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH o AS (
    SELECT co.target_id, co.woo_order_id, co.status_class, co.net_product, co.units, co.payment_state
    FROM f360.commerce_orders co WHERE co.source_system = 'woo' AND co.market = p_market AND co.occurred_at >= p_from AND co.occurred_at < p_to
  ), orig AS (
    SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0) AS revenue,
           count(*) FILTER (WHERE status_class = 'countable') AS orders, coalesce(sum(units) FILTER (WHERE status_class = 'countable'), 0) AS units FROM o
  ), x AS (
    SELECT o.*, s.reason, s.decided_by_name, s.decided_at, (o.status_class = 'countable') AS effective
    FROM o JOIN f360.sales_rec_analytics_scope s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id WHERE s.excluded
  ), eff AS (
    SELECT coalesce(sum(net_product) FILTER (WHERE effective), 0) AS revenue, count(*) FILTER (WHERE effective) AS orders,
           coalesce(sum(units) FILTER (WHERE effective), 0) AS units, count(*) FILTER (WHERE NOT effective) AS no_effect FROM x
  ), cls AS (   -- classified as test / duplicate but NOT excluded: they still count (transparency, never silent)
    SELECT count(*) AS n FROM o JOIN LATERAL (SELECT d.decision FROM f360.sales_rec_decisions d WHERE d.target_id = o.target_id AND d.woo_order_id = o.woo_order_id
             ORDER BY d.id DESC LIMIT 1) d ON true
    WHERE d.decision IN ('prueba', 'duplicado') AND o.status_class = 'countable'
      AND NOT EXISTS (SELECT 1 FROM f360.sales_rec_analytics_scope s WHERE s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id AND s.excluded)
  )
  SELECT jsonb_build_object(
    'original', jsonb_build_object('revenue', orig.revenue, 'paid_orders', orig.orders, 'units', orig.units,
                                   'aov', CASE WHEN orig.orders > 0 THEN round(orig.revenue / orig.orders, 2) END),
    'excluded', jsonb_build_object('revenue', eff.revenue, 'paid_orders', eff.orders, 'units', eff.units, 'without_effect', eff.no_effect),
    'adjusted', jsonb_build_object('revenue', orig.revenue - eff.revenue, 'paid_orders', orig.orders - eff.orders, 'units', orig.units - eff.units,
                                   'aov', CASE WHEN orig.orders - eff.orders > 0 THEN round((orig.revenue - eff.revenue) / (orig.orders - eff.orders), 2) END),
    'classified_not_excluded', cls.n,
    'detail', CASE WHEN p_detail THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('target_id', x.target_id, 'woo_order_id', x.woo_order_id,
                 'status_class', x.status_class, 'payment_state', x.payment_state, 'effective', x.effective,
                 'revenue_effect', CASE WHEN x.effective THEN x.net_product ELSE 0 END, 'units_effect', CASE WHEN x.effective THEN x.units ELSE 0 END,
                 'why_no_effect', CASE WHEN x.effective THEN NULL WHEN x.payment_state = 'never_paid' THEN 'Nunca se pagó: no contaba'
                                       ELSE 'Cancelado o reembolsado después del pago: ya no contaba' END,
                 'reason', x.reason, 'by', x.decided_by_name, 'at', x.decided_at) ORDER BY x.woo_order_id), '[]') FROM x) END,
    'source', 'Conciliación de Ventas · exclusiones autorizadas (registro inmutable)')
  FROM orig, eff, cls;
$$;
REVOKE ALL ON FUNCTION f360.growth_adjustments(text, timestamptz, timestamptz, boolean) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.f360_growth_cockpit(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
  d_to date := coalesce(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date);
  d_from date := coalesce(p_from, d_to - 29);
  len int; f timestamptz; t timestamptz; pf timestamptz; pt timestamptz; blocks jsonb := '[]'; m text; b jsonb; findings jsonb := '[]';
  fresh record; stale boolean;
  viewer boolean := EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid());
BEGIN
  IF d_from > d_to THEN RAISE EXCEPTION 'El periodo no es válido.'; END IF;
  len := d_to - d_from + 1;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  pf := (d_from - len)::timestamp AT TIME ZONE 'America/Mexico_City'; pt := f;
  SELECT max(last_success_at) AS last_ok, bool_or(freshness = 'STALE') AS any_stale INTO fresh FROM f360.commerce_source_health;
  stale := coalesce(fresh.any_stale, false) OR fresh.last_ok IS NULL OR fresh.last_ok < now() - interval '2 hours';

  FOREACH m IN ARRAY ARRAY['MX', 'CO', 'ROW'] LOOP
    b := f360.growth_market_block(m, f, t, pf, pt);
    -- Conciliación: authorized analytics exclusions, shown APART; the original KPIs above stay untouched.
    b := b || jsonb_build_object('adjustments', f360.growth_adjustments(m, f, t, viewer));
    IF stale THEN b := jsonb_set(b, '{kpis,revenue,status}', '"STALE"'); b := jsonb_set(b, '{kpis,paid_orders,status}', '"STALE"'); END IF;
    blocks := blocks || b;
    -- F1 · checkout sent but never paid (Woo statuses: high confidence)
    IF (b->'checkout'->>'created')::int >= 3 AND (b->'checkout'->>'never_paid')::int > 0 THEN
      findings := findings || jsonb_build_object('market', m, 'kind', 'checkout_sin_pago', 'confidence', 'ALTA',
        'title', 'Pedidos que llegaron al pago y nunca se pagaron',
        'evidence', format('%s de %s pedidos creados (%s%%) quedaron sin pago en %s.', b->'checkout'->>'never_paid', b->'checkout'->>'created',
                    round((b->'checkout'->>'never_paid')::numeric / (b->'checkout'->>'created')::numeric * 100), m),
        'detail', b->'checkout'->'by_payment', 'source', 'WooCommerce · estados de pedido');
    END IF;
    -- F2 · paid orders without attribution (coverage)
    IF (b->'attribution_coverage'->>'paid')::int > 0 AND (b->'attribution_coverage'->>'attributed')::int < (b->'attribution_coverage'->>'paid')::int THEN
      findings := findings || jsonb_build_object('market', m, 'kind', 'sin_atribucion', 'confidence', 'ALTA',
        'title', 'Ventas pagadas sin origen registrado',
        'evidence', format('%s de %s pedidos pagados no traen origen (canal/campaña) en %s.',
                    (b->'attribution_coverage'->>'paid')::int - (b->'attribution_coverage'->>'attributed')::int, b->'attribution_coverage'->>'paid', m),
        'source', 'WooCommerce Order Attribution');
    END IF;
  END LOOP;
  -- F3 · upper funnel unknown without GA4; F4 · spend without sales unknown without spend
  findings := findings || jsonb_build_object('market', 'TODOS', 'kind', 'funnel_sin_datos', 'confidence', 'SIN DATOS',
      'title', 'No se puede saber dónde se cae el tráfico antes del pedido',
      'evidence', 'Sesiones → vista de producto → carrito → checkout requieren GA4 (no conectado). Hoy solo se mide del pedido creado al pago.',
      'source', 'GA4 · NOT_CONFIGURED')
    || jsonb_build_object('market', 'TODOS', 'kind', 'gasto_sin_datos', 'confidence', 'SIN DATOS',
      'title', 'No se puede saber qué campañas gastan sin vender',
      'evidence', 'No hay gasto publicitario cargado (Meta / Google). Las campañas que sí aparecen en pedidos vienen de la atribución de WooCommerce.',
      'source', 'Gasto publicitario · NOT_CONFIGURED');

  RETURN jsonb_build_object('from', d_from, 'to', d_to, 'prev_from', d_from - len, 'prev_to', d_from - 1, 'generated_at', now(),
    'freshness', jsonb_build_object('last_success_at', fresh.last_ok, 'status', CASE WHEN stale THEN 'STALE' ELSE 'OK' END),
    'consolidated', jsonb_build_object('status', CASE WHEN EXISTS (SELECT 1 FROM f360.fx_rates WHERE approved_at IS NOT NULL) THEN 'DATA_INCOMPLETE' ELSE 'NOT_CONFIGURED' END,
                                       'note', 'MXN, COP y USD no se suman sin tipo de cambio aprobado'),
    'markets', blocks, 'findings', findings);
END $$;
REVOKE ALL ON FUNCTION public.f360_growth_cockpit(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_growth_cockpit(date, date) TO authenticated, service_role;
