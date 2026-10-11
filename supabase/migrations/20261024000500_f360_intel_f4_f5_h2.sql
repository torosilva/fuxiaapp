-- Fuxia 360 · Centro de Inteligencia — correcciones F4, F5 y H2 de la evaluación I4 (Mario 2026-10-11: autorización condicionada;
-- este archivo se PRESENTA antes de aplicarse y se aplica SOLO en STAGING tras su aprobación). ADDITIVE / READ-ONLY for business data.
--   F4 · Lists are complete or explicitly truncated: f360.intel_inventory_core keeps its signature and output (cockpit card 6 and the
--        analyst keep working) and ADDS baja_salida_total {modelos, pares, mostrados, limitada, faltan}; the new read-only tool
--        'inventario_baja_salida' (f360.intel_low_sell_page) pages through the WHOLE list (pagina / por_pagina).
--   F5 · Advertising never mixes store sales into a Meta return: f360.intel_marketing_core keeps its keys and ADDS per market
--        venta_en_linea, venta_tienda (no atribuida), venta_combinada, ingresos_atribuidos_meta (WooCommerce order attribution =
--        UTM "Meta pagado", last touch, with coverage), meta_organico_utm (shown apart, not in ROAS), roas_meta (ONLY attributed
--        revenue ÷ Meta spend, MXN with approved FX), eficiencia_combinada / eficiencia_en_linea (ratios that do NOT imply attribution)
--        and cpa_en_linea. The old 'mer' value is kept for compatibility, labelled as combined efficiency (no attribution).
--        'roas_atribuido' (same key the cockpit reads) now carries the attributed ROAS instead of a fixed FALTA.
--   H2 · AI quota is RESERVED atomically: f360.ai_inflight (one row per question in progress, deleted when its audit row is written;
--        stale rows ignored after 10 min) + f360_ai_reserve(user, estimated cost) under an advisory lock; f360_ai_log(p) deletes the
--        reservation named in p.reservation_id. f360.ai_queries (append-only audit) is NOT modified.
-- No table with business data is created or altered; no existing grant changes. Rollback: supabase/rollbacks/20261024000500_f360_intel_f4_f5_h2.down.sql

-- ══ F4 · baja salida: total + paginación ══════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION f360.intel_low_sell_page(p_days int, p_page int DEFAULT 1, p_size int DEFAULT 20) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH prm AS (SELECT least(greatest(coalesce(p_days, 60), 14), 365) AS d, greatest(coalesce(p_page, 1), 1) AS pg, least(greatest(coalesce(p_size, 20), 1), 100) AS sz),
  oh AS (SELECT v.product_id, sum(b.on_hand) pairs FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
         JOIN f360.locations l ON l.id = b.location_id WHERE l.status = 'active' AND l.type <> 'transit' GROUP BY 1),
  sold AS (SELECT ln.product_id, sum(ln.quantity) units FROM f360.commerce_order_lines ln
           JOIN f360.commerce_orders o ON o.source_system = ln.source_system AND o.external_ref = ln.external_ref, prm
           WHERE o.status_class = 'countable' AND o.market = 'MX' AND (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date > f360.intel_today() - prm.d GROUP BY 1),
  low AS (SELECT pr.name, oh.pairs, oh.pairs * pr.regular_price AS retail, row_number() OVER (ORDER BY oh.pairs DESC, pr.name) AS rn
          FROM f360.products pr JOIN oh ON oh.product_id = pr.id LEFT JOIN sold ON sold.product_id = pr.id WHERE oh.pairs > 0 AND coalesce(sold.units, 0) = 0),
  tot AS (SELECT count(*) AS n, coalesce(sum(pairs), 0) AS pairs, coalesce(sum(retail), 0) AS retail FROM low)
  SELECT jsonb_build_object(
    'total_modelos', tot.n, 'total_pares', tot.pairs, 'total_valor_precio_venta', tot.retail,
    'pagina', prm.pg, 'por_pagina', prm.sz, 'paginas', greatest(1, ceil(tot.n::numeric / prm.sz)::int), 'ventana_dias', prm.d,
    'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('modelo', name, 'pares', pairs, 'valor_precio_venta', retail) ORDER BY rn), '[]')
              FROM low WHERE rn > (prm.pg - 1) * prm.sz AND rn <= prm.pg * prm.sz),
    'mostrados', (SELECT count(*) FROM low WHERE rn > (prm.pg - 1) * prm.sz AND rn <= prm.pg * prm.sz),
    'faltan_despues_de_esta_pagina', greatest(0, tot.n - prm.pg * prm.sz))
  FROM prm, tot $$;

-- same output as before + baja_salida_total (never let a capped list look like the total)
CREATE OR REPLACE FUNCTION f360.intel_inventory_core(p_days int) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE d int := least(greatest(coalesce(p_days, 60), 14), 365); since date := f360.intel_today() - least(greatest(coalesce(p_days, 60), 14), 365);
  loc jsonb; prod jsonb; low jsonb; risk jsonb; tot int; hist_from date; cost_cov numeric; upd timestamptz; falt jsonb := '[]'; lp jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('ubicacion', l.name, 'tipo', l.type, 'pares', s) ORDER BY s DESC), '[]'), coalesce(sum(s), 0)::int INTO loc, tot FROM (
    SELECT b.location_id, sum(b.on_hand) s FROM f360.inventory_balances b GROUP BY 1) q JOIN f360.locations l ON l.id = q.location_id
    WHERE l.status = 'active' AND l.type <> 'transit';
  WITH oh AS (SELECT v.product_id, sum(b.on_hand) pairs FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
              JOIN f360.locations l ON l.id = b.location_id WHERE l.status = 'active' AND l.type <> 'transit' GROUP BY 1),
       sold AS (SELECT ln.product_id, sum(ln.quantity) units FROM f360.commerce_order_lines ln
                JOIN f360.commerce_orders o ON o.source_system = ln.source_system AND o.external_ref = ln.external_ref
                WHERE o.status_class = 'countable' AND o.market = 'MX' AND (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date > since GROUP BY 1),
       p AS (SELECT pr.id, pr.name, coalesce(pr.category_key, pr.category) cat, coalesce(oh.pairs, 0) pairs, coalesce(sold.units, 0) units, pr.regular_price
             FROM f360.products pr LEFT JOIN oh ON oh.product_id = pr.id LEFT JOIN sold ON sold.product_id = pr.id WHERE coalesce(oh.pairs, 0) > 0 OR coalesce(sold.units, 0) > 0)
  SELECT
    (SELECT coalesce(jsonb_agg(jsonb_build_object('modelo', name, 'categoria', cat, 'pares', pairs, 'vendidos_periodo', units,
              'dias_cobertura', CASE WHEN units > 0 THEN round(pairs::numeric / (units::numeric / d)) END, 'valor_precio_venta', pairs * regular_price) ORDER BY pairs DESC), '[]') FROM p),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('modelo', name, 'pares', pairs, 'valor_precio_venta', pairs * regular_price) ORDER BY pairs DESC), '[]')
       FROM (SELECT * FROM p WHERE pairs > 0 AND units = 0 ORDER BY pairs DESC, name LIMIT 20) z),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('modelo', name, 'pares', pairs, 'vendidos_periodo', units, 'dias_cobertura', round(pairs::numeric / (units::numeric / d)))
              ORDER BY pairs::numeric / (units::numeric / d)), '[]') FROM p WHERE units > 0 AND pairs::numeric / (units::numeric / d) < 21)
    INTO prod, low, risk;
  lp := f360.intel_low_sell_page(d, 1, 20);
  SELECT min((o.occurred_at AT TIME ZONE 'America/Mexico_City')::date) INTO hist_from FROM f360.commerce_orders o WHERE o.market = 'MX' AND o.status_class = 'countable';
  SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(count(*) FILTER (WHERE EXISTS (SELECT 1 FROM f360.product_cost_effective c WHERE c.product_id = v.product_id AND c.effective_to IS NULL))::numeric / count(*) * 100, 1) END
    INTO cost_cov FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id WHERE b.on_hand > 0;
  SELECT max(updated_at) INTO upd FROM f360.inventory_balances;
  falt := falt || jsonb_build_object('que', 'Inventario a costo', 'por_que', format('Costo aprobado solo para %s%% de los pares', coalesce(cost_cov, 0)), 'quien', 'Carolina (costos por modelo)');
  falt := falt || jsonb_build_object('que', 'Conteo físico y pares de la app anterior', 'por_que', 'Sin conteo físico; 179 pares en la app anterior nunca pasaron a Fuxia 360 (conciliación 2026-10-11)', 'quien', 'Mario / Carolina');
  RETURN jsonb_build_object('data', jsonb_build_object('pares_total', tot, 'por_ubicacion', loc, 'por_modelo', prod, 'baja_salida', low,
      'baja_salida_total', jsonb_build_object('modelos', lp->'total_modelos', 'pares', lp->'total_pares', 'valor_precio_venta', lp->'total_valor_precio_venta',
        'mostrados', jsonb_array_length(low), 'limitada', (lp->>'total_modelos')::int > jsonb_array_length(low),
        'faltan', greatest(0, (lp->>'total_modelos')::int - jsonb_array_length(low)),
        'como_ver_todo', 'herramienta inventario_baja_salida con pagina / por_pagina'),
      'riesgo_agotarse', risk, 'ventana_dias', d, 'historial_ventas_desde', hist_from, 'cobertura_costo_pct', coalesce(cost_cov, 0),
      'formulas', jsonb_build_object('dias_cobertura', 'pares ÷ (vendidos en la ventana ÷ días)', 'baja_salida', 'pares > 0 y 0 vendidos en la ventana', 'riesgo', 'cobertura < 21 días')),
    'meta', f360.intel_meta('Ledger de inventario Fuxia 360 (saldo vivo, sin tránsito) + ventas pagadas México', since, f360.intel_today(), 'pares; valor a precio de venta en MXN',
      'PARCIAL', falt, jsonb_build_array('Ventas de tienda medidas desde el arranque de Fuxia 360; la rotación mejora con más historial (P0E).',
        'La lista "baja_salida" muestra hasta 20 modelos; "baja_salida_total" da el total y cuántos faltan.'), upd));
END $$;

-- ══ F5 · marketing: atribución separada de la eficiencia ══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION f360.intel_marketing_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rows jsonb; camp jsonb; g_exp boolean := (SELECT spend_expected FROM f360.measurement_sources WHERE key = 'google_ads'); upd timestamptz; falt jsonb := '[]';
BEGIN
  WITH sp AS (SELECT market, currency, date_trunc('month', date)::date m, sum(spend) s, sum(clicks) c, sum(impressions) i FROM f360.marketing_spend_daily
              WHERE date BETWEEN p_from AND p_to AND platform = 'meta' GROUP BY 1, 2, 3),
       o AS (SELECT io.*, f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host) AS canal_attr, (a.woo_order_id IS NOT NULL AND a.source_type IS NOT NULL) AS has_attr
             FROM f360.intel_orders(p_from, p_to) io LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = io.target_id AND a.woo_order_id = io.woo_order_id
             WHERE io.status_class = 'countable'),
       firsts AS (SELECT customer_key, min(bdate) AS first_day FROM f360.intel_orders('2000-01-01', p_to) WHERE status_class = 'countable' AND customer_key IS NOT NULL GROUP BY 1),
       mk AS (SELECT DISTINCT market FROM sp WHERE market IN ('MX', 'CO', 'ROW') UNION SELECT DISTINCT market FROM o)
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'mercado'), '[]') INTO rows FROM (
    SELECT jsonb_build_object('mercado', mk.market,
      'inversion', (SELECT jsonb_build_object('monto', sum(s), 'moneda', min(currency), 'clics', sum(c), 'impresiones', sum(i), 'plataforma', 'Meta') FROM sp WHERE sp.market = mk.market),
      'inversion_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', m, 'amount', s)), '[]')) FROM sp WHERE sp.market = mk.market),
      -- ventas, separadas por canal (hechos)
      'venta_en_linea', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'pedidos', count(*), 'moneda', f360.intel_cur(mk.market)) FROM o WHERE o.market = mk.market AND o.channel = 'online'),
      'venta_tienda', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'pedidos', count(*), 'moneda', f360.intel_cur(mk.market),
                        'nota', 'Venta física: NO atribuida a publicidad') FROM o WHERE o.market = mk.market AND o.channel <> 'online'),
      'venta_neta', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'moneda', f360.intel_cur(mk.market), 'incluye', 'en línea + tienda') FROM o WHERE o.market = mk.market),
      'venta_neta_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', mm, 'amount', amt)), '[]'))
                         FROM (SELECT currency, date_trunc('month', bdate)::date mm, sum(net_product) amt FROM o WHERE o.market = mk.market AND NOT suspicious_currency GROUP BY 1, 2) q),
      'venta_en_linea_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', mm, 'amount', amt)), '[]'))
                         FROM (SELECT currency, date_trunc('month', bdate)::date mm, sum(net_product) amt FROM o WHERE o.market = mk.market AND o.channel = 'online' AND NOT suspicious_currency GROUP BY 1, 2) q),
      -- atribución con evidencia (WooCommerce Order Attribution, última interacción)
      'ingresos_atribuidos_meta', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'pedidos', count(*), 'moneda', f360.intel_cur(mk.market),
                        'base', 'Atribución de WooCommerce (última interacción): UTM de Meta pagado') FROM o WHERE o.market = mk.market AND o.channel = 'online' AND o.canal_attr = 'Meta pagado'),
      'ingresos_atribuidos_meta_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', mm, 'amount', amt)), '[]'))
                         FROM (SELECT currency, date_trunc('month', bdate)::date mm, sum(net_product) amt FROM o WHERE o.market = mk.market AND o.channel = 'online' AND o.canal_attr = 'Meta pagado' AND NOT suspicious_currency GROUP BY 1, 2) q),
      'meta_organico_utm', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'pedidos', count(*), 'moneda', f360.intel_cur(mk.market),
                        'nota', 'Enlaces de Meta con UTM no pagado (orgánico): NO entra en el ROAS de la inversión') FROM o WHERE o.market = mk.market AND o.channel = 'online' AND o.canal_attr = 'Meta (UTM no pagado)'),
      'cobertura_atribucion_pct', (SELECT CASE WHEN count(*) = 0 THEN NULL ELSE round(count(*) FILTER (WHERE has_attr)::numeric / count(*) * 100, 1) END FROM o WHERE o.market = mk.market AND o.channel = 'online'),
      'pedidos_pagados', (SELECT count(*) FROM o WHERE o.market = mk.market),
      'pedidos_pagados_en_linea', (SELECT count(*) FROM o WHERE o.market = mk.market AND o.channel = 'online'),
      'clientas_nuevas', (SELECT count(DISTINCT o.customer_key) FROM o JOIN firsts f ON f.customer_key = o.customer_key WHERE o.market = mk.market AND f.first_day BETWEEN p_from AND p_to),
      'pedidos_sin_identidad', (SELECT count(*) FROM o WHERE o.market = mk.market AND customer_key IS NULL)) AS x
    FROM mk) q;
  SELECT coalesce(jsonb_agg(x || jsonb_build_object(
      -- ROAS: SOLO ingresos atribuidos a Meta pagado ÷ inversión en Meta (MXN con tasa aprobada)
      'roas_atribuido', CASE
         WHEN (x->'inversion_mxn'->>'mxn') IS NULL OR coalesce((x->'inversion_mxn'->>'mxn')::numeric, 0) = 0 THEN
           jsonb_build_object('valor', NULL, 'disponibilidad', 'FALTA', 'por_que', 'Sin inversión en Meta en el periodo')
         WHEN x->'ingresos_atribuidos_meta_mxn'->>'mxn' IS NULL THEN
           jsonb_build_object('valor', NULL, 'disponibilidad', 'FALTA', 'por_que', 'Falta tipo de cambio aprobado para convertir los ingresos atribuidos')
         ELSE jsonb_build_object('valor', round((x->'ingresos_atribuidos_meta_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2),
           'disponibilidad', CASE WHEN coalesce((x->>'cobertura_atribucion_pct')::numeric, 0) >= 80 THEN 'DISPONIBLE' ELSE 'PARCIAL' END,
           'base', 'Ingresos atribuidos a Meta pagado (WooCommerce, última interacción) ÷ inversión en Meta; MXN',
           'nota', 'Es un piso: pedidos sin UTM o de otros dispositivos no se atribuyen. No incluye ventas de tienda.') END,
      -- eficiencia comercial: NO implica atribución
      'eficiencia_combinada', CASE WHEN coalesce((x->'inversion_mxn'->>'mxn')::numeric, 0) > 0 AND x->'venta_neta_mxn'->>'mxn' IS NOT NULL
                  THEN round((x->'venta_neta_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2) END,
      'eficiencia_en_linea', CASE WHEN coalesce((x->'inversion_mxn'->>'mxn')::numeric, 0) > 0 AND x->'venta_en_linea_mxn'->>'mxn' IS NOT NULL
                  THEN round((x->'venta_en_linea_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2) END,
      'mer', CASE WHEN coalesce((x->'inversion_mxn'->>'mxn')::numeric, 0) > 0 AND x->'venta_neta_mxn'->>'mxn' IS NOT NULL
                  THEN round((x->'venta_neta_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2) END,
      'mer_definicion', 'MER = eficiencia combinada (venta en línea + tienda ÷ inversión). NO es ROAS ni implica atribución.',
      'cpa_mxn', CASE WHEN (x->>'pedidos_pagados')::int > 0 AND x->'inversion_mxn'->>'mxn' IS NOT NULL THEN round((x->'inversion_mxn'->>'mxn')::numeric / (x->>'pedidos_pagados')::int, 2) END,
      'cpa_en_linea_mxn', CASE WHEN (x->>'pedidos_pagados_en_linea')::int > 0 AND x->'inversion_mxn'->>'mxn' IS NOT NULL THEN round((x->'inversion_mxn'->>'mxn')::numeric / (x->>'pedidos_pagados_en_linea')::int, 2) END,
      'cac_mxn', CASE WHEN (x->>'clientas_nuevas')::int > 0 AND x->'inversion_mxn'->>'mxn' IS NOT NULL THEN round((x->'inversion_mxn'->>'mxn')::numeric / (x->>'clientas_nuevas')::int, 2) END)), '[]') INTO rows
    FROM jsonb_array_elements(rows) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'campana', campaign_name, 'inversion', s, 'moneda', currency) ORDER BY s DESC), '[]') INTO camp FROM (
    SELECT market, currency, coalesce(campaign_name, campaign_id) campaign_name, sum(spend) s FROM f360.marketing_spend_daily WHERE date BETWEEN p_from AND p_to AND spend > 0
    GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 15) q;
  SELECT max(imported_at) INTO upd FROM f360.marketing_spend_daily;
  falt := falt || jsonb_build_object('que', 'Atribución por campaña y multi-dispositivo', 'por_que', 'Solo hay atribución de última interacción por UTM de WooCommerce; GA4 aún no está conectado', 'quien', 'GA4 (permiso de Adrián)');
  IF g_exp IS NULL THEN falt := falt || jsonb_build_object('que', 'Gasto de Google Ads', 'por_que', 'No se sabe si hay gasto', 'quien', 'Mario'); END IF;
  RETURN jsonb_build_object('data', jsonb_build_object('por_mercado', rows, 'campanas_top', camp,
      'google_ads', CASE WHEN g_exp = false THEN 'sin gasto (confirmado por Mario)' WHEN g_exp THEN 'con gasto' ELSE 'desconocido' END,
      'formulas', jsonb_build_object('roas_atribuido', 'ingresos atribuidos a Meta pagado ÷ inversión en Meta (MXN)',
        'eficiencia_combinada', 'venta neta en línea + tienda (MXN) ÷ inversión (MXN) — no implica atribución',
        'eficiencia_en_linea', 'venta neta en línea (MXN) ÷ inversión (MXN) — no implica atribución',
        'cpa', 'inversión ÷ pedidos pagados (todos los canales)', 'cpa_en_linea', 'inversión ÷ pedidos pagados en línea', 'cac', 'inversión ÷ clientas nuevas identificadas')),
    'meta', f360.intel_meta('Gasto publicitario Meta (API) + Commerce Facts + atribución de pedidos WooCommerce', p_from, p_to, 'MXN para razones; venta en moneda original', 'PARCIAL', falt,
      jsonb_build_array('Las ventas de tienda nunca se cuentan como retorno de Meta.', 'El ROAS usa solo ingresos atribuidos a Meta pagado; MER y eficiencias no implican atribución.',
                        'CAC cuenta solo clientas identificadas (los pedidos de invitada sin cuenta no tienen identidad).'), upd));
END $$;

-- the analyst dispatcher learns the paged low-sell tool (same signature; every other tool unchanged)
CREATE OR REPLACE FUNCTION public.f360_intel_query(p_tool text, p_args jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
-- The ONLY entry point of the analyst: a fixed list of tools with typed arguments. No SQL is ever accepted.
DECLARE f date; t date; today date := f360.intel_today(); r jsonb;
BEGIN
  IF f360.intel_gate('f360_intel_query:' || left(coalesce(p_tool, ''), 40), p_args) IS NULL THEN RETURN f360_board.denied(); END IF;
  BEGIN
    f := coalesce((p_args->>'desde')::date, date_trunc('month', today)::date);
    t := least(coalesce((p_args->>'hasta')::date, today), today);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok', false, 'error', 'Fechas no válidas (AAAA-MM-DD).');
  END;
  IF NOT public.f360_intel_valid_range(f, t) THEN RETURN jsonb_build_object('ok', false, 'error', 'Rango no válido (máximo 800 días).'); END IF;
  BEGIN
    r := CASE p_tool
      WHEN 'ventas' THEN f360.intel_sales_core(f, t)
      WHEN 'presupuesto_vs_real' THEN f360.intel_budget_core(f, t)
      WHEN 'avance_meta' THEN f360.intel_goal_core(coalesce(nullif(p_args->>'meta', ''), 'ecommerce_mx_mensual'), coalesce((p_args->>'mes')::date, today))
      WHEN 'marketing' THEN f360.intel_marketing_core(f, t)
      WHEN 'pagos' THEN f360.intel_payments_core(f, t)
      WHEN 'inventario_mx' THEN f360.intel_inventory_core(coalesce((p_args->>'dias')::int, 60))
      WHEN 'inventario_baja_salida' THEN jsonb_build_object('data', f360.intel_low_sell_page(coalesce((p_args->>'dias')::int, 60), coalesce((p_args->>'pagina')::int, 1), coalesce((p_args->>'por_pagina')::int, 50)),
                                          'meta', f360.intel_meta('Ledger de inventario Fuxia 360 + ventas pagadas México (lista completa, paginada)', today - coalesce((p_args->>'dias')::int, 60), today, 'pares', 'PARCIAL',
                                            jsonb_build_array(jsonb_build_object('que', 'Conteo físico', 'por_que', 'El saldo es del sistema, sin conteo físico', 'quien', 'Mario / Carolina'))))
      WHEN 'margen' THEN f360.intel_margin_core(f, t)
      WHEN 'caja' THEN f360.intel_cash_core(coalesce((p_args->>'mes')::date, (date_trunc('month', today) - interval '1 month')::date))
      WHEN 'proyeccion_cierre' THEN f360.intel_forecast_core(coalesce((p_args->>'mes')::date, today))
      WHEN 'embudo' THEN f360.intel_funnel_core(f, t)
      WHEN 'senales_semana' THEN f360.intel_signals_core(f, t)
      WHEN 'fuentes' THEN f360.intel_sources_core()
      ELSE NULL END;
  EXCEPTION WHEN invalid_text_representation OR datetime_field_overflow OR invalid_datetime_format THEN RETURN jsonb_build_object('ok', false, 'error', 'Argumento no válido.');
  END;
  IF r IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Herramienta no disponible.'); END IF;
  RETURN jsonb_build_object('ok', true, 'herramienta', p_tool, 'argumentos', p_args) || r;
END $$;

-- ══ H2 · reserva atómica del tope de IA ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE f360.ai_inflight (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  auth_user_id  uuid NOT NULL,
  started_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  est_cost_usd  numeric(10,5) NOT NULL CHECK (est_cost_usd >= 0)
);
COMMENT ON TABLE f360.ai_inflight IS 'H2: questions in progress (reservations). Not an audit: a row is deleted when its f360.ai_queries row is written; rows older than 10 min are ignored.';

-- service role: atomically check AND reserve (serialized by an advisory lock); same limits as f360_ai_quota + in-flight questions + margin
CREATE FUNCTION public.f360_ai_reserve(p_user uuid, p_est_cost numeric) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE q jsonb; inflight_n int; inflight_usd numeric; v bigint; why text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('f360_ai_reserve'));   -- one reservation at a time: no two questions pass the same check
  DELETE FROM f360.ai_inflight WHERE started_at < clock_timestamp() - interval '10 minutes';
  q := public.f360_ai_quota(p_user);
  SELECT count(*) FILTER (WHERE auth_user_id = p_user), coalesce(sum(est_cost_usd), 0) INTO inflight_n, inflight_usd FROM f360.ai_inflight;
  why := CASE WHEN NOT (q->>'allowed')::boolean THEN coalesce(q->>'reason', 'apagado')
              WHEN (q->>'used_today')::int + inflight_n >= (SELECT per_user_daily FROM f360.ai_settings) THEN 'limite_usuario'
              WHEN (q->>'spent_month_usd')::numeric + inflight_usd + coalesce(p_est_cost, 0) > (q->>'budget_usd')::numeric THEN 'limite_mes' END;
  IF why IS NOT NULL THEN RETURN q || jsonb_build_object('allowed', false, 'reason', why, 'in_flight_usd', inflight_usd); END IF;
  INSERT INTO f360.ai_inflight (auth_user_id, est_cost_usd) VALUES (p_user, coalesce(p_est_cost, 0)) RETURNING id INTO v;
  RETURN q || jsonb_build_object('allowed', true, 'reason', NULL, 'reservation_id', v, 'in_flight_usd', inflight_usd);
END $$;

-- f360_ai_log: same behaviour + releases the reservation named in p.reservation_id (if any)
CREATE OR REPLACE FUNCTION public.f360_ai_log(p jsonb) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.ai_settings; v bigint; ti int := coalesce((p->>'tokens_input')::int, 0); tout int := coalesce((p->>'tokens_output')::int, 0);
  tcr int := coalesce((p->>'tokens_cache_read')::int, 0); tcw int := coalesce((p->>'tokens_cache_write')::int, 0);
BEGIN
  SELECT * INTO s FROM f360.ai_settings;
  INSERT INTO f360.ai_queries (auth_user_id, user_name, kind, question_masked, status, provider, model, tools, sources, answer, unverified,
                               tokens_input, tokens_output, tokens_cache_read, tokens_cache_write, cost_usd, duration_ms, error)
  VALUES ((p->>'auth_user_id')::uuid, coalesce((SELECT display_name FROM f360.user_roles WHERE auth_user_id = (p->>'auth_user_id')::uuid), 'Sin nombre'),
          coalesce(p->>'kind', 'pregunta'), f360.ai_mask(p->>'question'), p->>'status', p->>'provider', p->>'model',
          coalesce(p->'tools', '[]'), coalesce(p->'sources', '[]'), p->'answer', coalesce(p->'unverified', '[]'), ti, tout, tcr, tcw,
          round((ti * s.price_input_mtok + tout * s.price_output_mtok + tcr * s.price_cache_read_mtok + tcw * s.price_cache_write_mtok) / 1e6, 5),
          (p->>'duration_ms')::int, left(p->>'error', 500))
  RETURNING id INTO v;
  IF p ? 'reservation_id' THEN DELETE FROM f360.ai_inflight WHERE id = (p->>'reservation_id')::bigint; END IF;
  RETURN v;
END $$;

ALTER TABLE f360.ai_inflight ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.ai_inflight FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.ai_inflight TO service_role;
REVOKE ALL ON FUNCTION f360.intel_low_sell_page(int, int, int), public.f360_ai_reserve(uuid, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_ai_reserve(uuid, numeric) TO service_role;
