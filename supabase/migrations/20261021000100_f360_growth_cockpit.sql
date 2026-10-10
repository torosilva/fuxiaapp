-- Fuxia 360 · S-G1 Growth Cockpit — "Growth War Room" (Mario 2026-10-10: "identificar por qué el ecommerce recibe tráfico pero
-- convierte pocas ventas"). ADDITIVE, read-only: two functions, no tables, no data changes.
-- Truth rules (docs/fuxia360/growth/02_MEASUREMENT_TRUTH.md):
--   · money = PAID online-store orders from Commerce Facts (f360.commerce_orders, source_system 'woo', status_class
--     'countable'); revenue basis = net product revenue (net_product, after discounts and product refunds), original currency;
--   · markets never mixed (MX = MXN, CO = COP, ROW = USD); no consolidated total without approved FX (none today);
--   · GA4 / Meta never replace paid orders; sessions, product views, add-to-cart come only from GA4 (NOT_CONFIGURED today);
--   · spend only from f360.marketing_spend_daily (S-G0); without it CPC/CTR/CPM/CPA/ROAS/MER are NOT_CONFIGURED, never 0;
--   · channel / campaign = WooCommerce Order Attribution (first-party, last touch, per order) — the only attribution with
--     evidence today; coverage is reported so a gap is visible.
-- Each KPI: {value, prev, status (OK | DATA_INCOMPLETE | NOT_CONFIGURED | STALE), source, note}. Findings carry evidence and a
-- confidence level; none recommends raising ad spend.
-- Rollback: supabase/rollbacks/20261021000100_f360_growth_cockpit.down.sql

-- Channel from Woo Order Attribution (v1). Deterministic, documented, testable.
CREATE FUNCTION f360.classify_channel_v1(p_source_type text, p_utm_source text, p_utm_medium text, p_referrer text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_source_type IS NULL THEN 'Sin atribución'
    WHEN p_source_type = 'utm' AND lower(coalesce(p_utm_source, '')) IN ('ig', 'instagram', 'fb', 'facebook', 'meta', 'an', 'msg', 'th')
         AND lower(coalesce(p_utm_medium, '')) IN ('paid', 'cpc', 'ppc', 'paid_social', 'paidsocial', 'ads', '') THEN 'Meta pagado'
    WHEN p_source_type = 'utm' AND lower(coalesce(p_utm_source, '')) IN ('ig', 'instagram', 'fb', 'facebook', 'meta') THEN 'Meta (UTM no pagado)'
    WHEN p_source_type = 'utm' AND lower(coalesce(p_utm_source, '')) IN ('google', 'adwords') AND lower(coalesce(p_utm_medium, '')) IN ('cpc', 'ppc', 'paid') THEN 'Google pagado'
    WHEN p_source_type = 'utm' AND lower(coalesce(p_utm_source, '')) IN ('whatsapp', 'wa') THEN 'WhatsApp'
    WHEN p_source_type = 'utm' AND lower(coalesce(p_utm_medium, '')) IN ('email', 'e-mail', 'newsletter') THEN 'Email'
    WHEN p_source_type = 'utm' THEN 'Otra campaña (UTM)'
    WHEN p_source_type = 'organic' THEN 'Búsqueda orgánica'
    WHEN p_source_type = 'referral' AND (p_referrer ~* '(instagram|facebook|fb\.|threads)') THEN 'Instagram / Facebook orgánico'
    WHEN p_source_type = 'referral' AND (p_referrer ~* 'whatsapp|wa\.me') THEN 'WhatsApp'
    WHEN p_source_type = 'referral' THEN 'Otro sitio'
    WHEN p_source_type = 'typein' THEN 'Directo'
    WHEN p_source_type = 'admin' THEN 'Creado en admin'
    ELSE 'Otro' END
$$;

-- One period × one market (internal).
CREATE FUNCTION f360.growth_market_block(p_market text, p_from timestamptz, p_to timestamptz, p_pfrom timestamptz, p_pto timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE cur text := CASE p_market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END;
  rev numeric; rev_p numeric; paid int; paid_p int; created int; created_p int; never int; n_units int;
  sp numeric; sp_p numeric; imp bigint; clk bigint; sp_cur_ok boolean; attributed int;
  ga4 text := (SELECT config_status FROM f360.measurement_sources WHERE key = 'ga4');
  k jsonb := '{}'; spend_status text; ga4_status text;
BEGIN
  SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0), count(*) FILTER (WHERE status_class = 'countable'),
         count(*), count(*) FILTER (WHERE payment_state = 'never_paid'), coalesce(sum(units) FILTER (WHERE status_class = 'countable'), 0)
    INTO rev, paid, created, never, n_units
    FROM f360.commerce_orders WHERE source_system = 'woo' AND market = p_market AND occurred_at >= p_from AND occurred_at < p_to;
  SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0), count(*) FILTER (WHERE status_class = 'countable'), count(*)
    INTO rev_p, paid_p, created_p
    FROM f360.commerce_orders WHERE source_system = 'woo' AND market = p_market AND occurred_at >= p_pfrom AND occurred_at < p_pto;
  SELECT sum(spend), sum(impressions), sum(clicks), bool_and(currency = cur) INTO sp, imp, clk, sp_cur_ok
    FROM f360.marketing_spend_daily WHERE market = p_market AND date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND date < (p_to AT TIME ZONE 'America/Mexico_City')::date;
  SELECT sum(spend) INTO sp_p FROM f360.marketing_spend_daily
    WHERE market = p_market AND date >= (p_pfrom AT TIME ZONE 'America/Mexico_City')::date AND date < (p_pto AT TIME ZONE 'America/Mexico_City')::date;
  spend_status := CASE WHEN sp IS NULL THEN 'NOT_CONFIGURED' WHEN NOT sp_cur_ok THEN 'DATA_INCOMPLETE' ELSE 'OK' END;
  ga4_status := CASE WHEN ga4 IN ('HEALTHY', 'CONFIGURED') THEN 'DATA_INCOMPLETE' ELSE 'NOT_CONFIGURED' END;   -- ingestion arrives in S-G2
  SELECT count(*) INTO attributed FROM f360.commerce_orders o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.market = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.source_type IS NOT NULL;

  k := jsonb_build_object(
    'revenue', jsonb_build_object('value', rev, 'prev', rev_p, 'currency', cur, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados (venta neta de producto)'),
    'paid_orders', jsonb_build_object('value', paid, 'prev', paid_p, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados'),
    'aov', jsonb_build_object('value', CASE WHEN paid > 0 THEN round(rev / paid, 2) END, 'prev', CASE WHEN paid_p > 0 THEN round(rev_p / paid_p, 2) END,
                              'currency', cur, 'status', CASE WHEN paid > 0 THEN 'OK' ELSE 'DATA_INCOMPLETE' END, 'source', 'ingresos ÷ pedidos pagados',
                              'note', CASE WHEN paid = 0 THEN 'Sin pedidos pagados en el periodo' END),
    'units', jsonb_build_object('value', n_units, 'status', 'OK', 'source', 'Commerce Facts · pares pagados'),
    'cvr_session', jsonb_build_object('value', NULL, 'status', ga4_status, 'source', 'pedidos pagados ÷ sesiones (GA4)', 'note', 'Requiere sesiones de GA4'),
    'cvr_click', jsonb_build_object('value', CASE WHEN clk > 0 THEN round(paid::numeric / clk * 100, 2) END,
                              'status', CASE WHEN clk IS NULL THEN 'NOT_CONFIGURED' WHEN clk = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'pedidos pagados ÷ clics de anuncios', 'note', 'Conversión por clic, no por sesión'),
    'spend', jsonb_build_object('value', sp, 'prev', sp_p, 'currency', cur, 'status', spend_status, 'source', 'Gasto publicitario (CSV / API)',
                              'note', CASE spend_status WHEN 'NOT_CONFIGURED' THEN 'Sin gasto cargado para este mercado y periodo' WHEN 'DATA_INCOMPLETE' THEN 'Gasto en otra moneda: falta tipo de cambio aprobado' END),
    'cpc', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND clk > 0 THEN round(sp / clk, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(clk, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'gasto ÷ clics'),
    'ctr', jsonb_build_object('value', CASE WHEN imp > 0 THEN round(clk::numeric / imp * 100, 2) END,
                              'status', CASE WHEN imp IS NULL THEN 'NOT_CONFIGURED' WHEN imp = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'clics ÷ impresiones'),
    'cpm', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND imp > 0 THEN round(sp / imp * 1000, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(imp, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'gasto ÷ impresiones × 1000'),
    'cpa', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND paid > 0 THEN round(sp / paid, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN paid = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'gasto ÷ pedidos pagados (todos los canales)'),
    'roas', jsonb_build_object('value', NULL, 'status', CASE WHEN spend_status <> 'OK' THEN spend_status ELSE 'DATA_INCOMPLETE' END,
                              'source', 'ingresos atribuidos a anuncios ÷ gasto',
                              'note', 'Requiere unir campañas del gasto con la atribución de pedidos (S-G2)'),
    'mer', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND sp > 0 THEN round(rev / sp, 2) END,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(sp, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'ingresos pagados totales ÷ gasto total'));

  RETURN jsonb_build_object('market', p_market, 'currency', cur, 'kpis', k,
    'attribution_coverage', jsonb_build_object('attributed', attributed, 'paid', paid),
    'funnel', jsonb_build_array(
      jsonb_build_object('stage', 'Sesiones', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Vieron un producto', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Agregaron al carrito', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Hicieron pedido (checkout enviado)', 'value', created, 'status', 'OK', 'source', 'WooCommerce · pedidos creados'),
      jsonb_build_object('stage', 'Pagaron', 'value', paid, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados')),
    'checkout', jsonb_build_object('created', created, 'paid', paid, 'never_paid', never,
      'by_payment', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'created' DESC), '[]') FROM (
        SELECT jsonb_build_object('method', coalesce(nullif(payment_method, ''), 'sin método'), 'created', count(*),
                 'paid', count(*) FILTER (WHERE status_class = 'countable'), 'never_paid', count(*) FILTER (WHERE payment_state = 'never_paid')) x
        FROM f360.commerce_orders WHERE source_system = 'woo' AND market = p_market AND occurred_at >= p_from AND occurred_at < p_to
        GROUP BY coalesce(nullif(payment_method, ''), 'sin método')) q)),
    'by_channel', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('channel', f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host),
                 'orders_created', count(*), 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0)) x
        FROM f360.commerce_orders o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host)) q),
    'by_campaign', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('campaign', a.utm_campaign, 'source', a.utm_source, 'orders_created', count(*),
                 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0),
                 'spend', (SELECT sum(d.spend) FROM f360.marketing_spend_daily d WHERE d.market = p_market AND d.campaign_id = a.utm_campaign
                            AND d.date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND d.date < (p_to AT TIME ZONE 'America/Mexico_City')::date)) x
        FROM f360.commerce_orders o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.utm_campaign IS NOT NULL
        GROUP BY a.utm_campaign, a.utm_source) q),
    'by_product', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('product', nm.name, 'paid_units', sum(l.quantity), 'revenue', sum(l.total)) x
        FROM f360.commerce_orders o JOIN f360.commerce_woo_order_lines l ON l.target_id = o.target_id AND l.woo_order_id = o.woo_order_id
        CROSS JOIN LATERAL (SELECT coalesce(
            (SELECT p.name FROM f360.woo_product_links wl JOIN f360.products p ON p.id = wl.product_id WHERE wl.woo_product_id = l.woo_product_id LIMIT 1),
            (SELECT p.name FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.sku = l.sku LIMIT 1),
            (SELECT m.woo_product_name FROM f360.legacy_woo_map m WHERE m.woo_product_id = l.woo_product_id AND m.woo_product_name IS NOT NULL LIMIT 1),
            'SKU ' || coalesce(l.sku, '?')) AS name) nm
        WHERE o.source_system = 'woo' AND o.market = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY nm.name LIMIT 15) q));
END $$;
REVOKE ALL ON FUNCTION f360.growth_market_block(text, timestamptz, timestamptz, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.f360_growth_cockpit(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
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
REVOKE ALL ON FUNCTION public.f360_growth_cockpit(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_growth_cockpit(date, date) TO authenticated, service_role;
