-- Rollback of 20261022000200_f360_growth_exclusions.sql: restores the S-G1 cockpit (20261021000100) and drops the helper.
CREATE OR REPLACE FUNCTION public.f360_growth_cockpit(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
  d_to date := coalesce(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date);
  d_from date := coalesce(p_from, d_to - 29);
  len int; f timestamptz; t timestamptz; pf timestamptz; pt timestamptz; blocks jsonb := '[]'; m text; b jsonb; findings jsonb := '[]';
  fresh record; stale boolean;
BEGIN
  IF d_from > d_to THEN RAISE EXCEPTION 'El periodo no es válido.'; END IF;
  len := d_to - d_from + 1;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  pf := (d_from - len)::timestamp AT TIME ZONE 'America/Mexico_City'; pt := f;
  SELECT max(last_success_at) AS last_ok, bool_or(freshness = 'STALE') AS any_stale INTO fresh FROM f360.commerce_source_health;
  stale := coalesce(fresh.any_stale, false) OR fresh.last_ok IS NULL OR fresh.last_ok < now() - interval '2 hours';

  FOREACH m IN ARRAY ARRAY['MX', 'CO', 'ROW'] LOOP
    b := f360.growth_market_block(m, f, t, pf, pt);
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
DROP FUNCTION IF EXISTS f360.growth_adjustments(text, timestamptz, timestamptz, boolean);
