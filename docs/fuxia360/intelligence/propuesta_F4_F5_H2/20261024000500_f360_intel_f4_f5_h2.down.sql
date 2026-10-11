-- Rollback of 20261024000500_f360_intel_f4_f5_h2. Run inside one transaction with psql (no BEGIN/COMMIT here).
-- Restores the EXACT previous bodies (copied from 20261024000300 / 20261024000400) and drops the new objects. No business data involved;
-- f360.ai_inflight only holds reservations of questions in progress (lost reservations just free the quota).
CREATE OR REPLACE FUNCTION f360.intel_inventory_core(p_days int) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE d int := least(greatest(coalesce(p_days, 60), 14), 365); since date := f360.intel_today() - least(greatest(coalesce(p_days, 60), 14), 365);
  loc jsonb; prod jsonb; low jsonb; risk jsonb; tot int; hist_from date; cost_cov numeric; upd timestamptz; falt jsonb := '[]';
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
       FROM (SELECT * FROM p WHERE pairs > 0 AND units = 0 ORDER BY pairs DESC LIMIT 20) z),
    (SELECT coalesce(jsonb_agg(jsonb_build_object('modelo', name, 'pares', pairs, 'vendidos_periodo', units, 'dias_cobertura', round(pairs::numeric / (units::numeric / d)))
              ORDER BY pairs::numeric / (units::numeric / d)), '[]') FROM p WHERE units > 0 AND pairs::numeric / (units::numeric / d) < 21)
    INTO prod, low, risk;
  SELECT min((o.occurred_at AT TIME ZONE 'America/Mexico_City')::date) INTO hist_from FROM f360.commerce_orders o WHERE o.market = 'MX' AND o.status_class = 'countable';
  SELECT CASE WHEN count(*) = 0 THEN 0 ELSE round(count(*) FILTER (WHERE EXISTS (SELECT 1 FROM f360.product_cost_effective c WHERE c.product_id = v.product_id AND c.effective_to IS NULL))::numeric / count(*) * 100, 1) END
    INTO cost_cov FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id WHERE b.on_hand > 0;
  SELECT max(updated_at) INTO upd FROM f360.inventory_balances;
  falt := falt || jsonb_build_object('que', 'Inventario a costo', 'por_que', format('Costo aprobado solo para %s%% de los pares', coalesce(cost_cov, 0)), 'quien', 'Carolina (costos por modelo)');
  falt := falt || jsonb_build_object('que', 'Conteo físico y pares de la app anterior', 'por_que', 'Sin conteo físico; 179 pares en la app anterior nunca pasaron a Fuxia 360 (conciliación 2026-10-11)', 'quien', 'Mario / Carolina');
  RETURN jsonb_build_object('data', jsonb_build_object('pares_total', tot, 'por_ubicacion', loc, 'por_modelo', prod, 'baja_salida', low, 'riesgo_agotarse', risk,
      'ventana_dias', d, 'historial_ventas_desde', hist_from, 'cobertura_costo_pct', coalesce(cost_cov, 0),
      'formulas', jsonb_build_object('dias_cobertura', 'pares ÷ (vendidos en la ventana ÷ días)', 'baja_salida', 'pares > 0 y 0 vendidos en la ventana', 'riesgo', 'cobertura < 21 días')),
    'meta', f360.intel_meta('Ledger de inventario Fuxia 360 (saldo vivo, sin tránsito) + ventas pagadas México', since, f360.intel_today(), 'pares; valor a precio de venta en MXN',
      'PARCIAL', falt, jsonb_build_array('Ventas de tienda medidas desde el arranque de Fuxia 360; la rotación mejora con más historial (P0E).'), upd));
END $$;

CREATE OR REPLACE FUNCTION f360.intel_marketing_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rows jsonb; camp jsonb; g_exp boolean := (SELECT spend_expected FROM f360.measurement_sources WHERE key = 'google_ads'); upd timestamptz; falt jsonb := '[]';
BEGIN
  WITH sp AS (SELECT market, currency, date_trunc('month', date)::date m, sum(spend) s, sum(clicks) c, sum(impressions) i FROM f360.marketing_spend_daily
              WHERE date BETWEEN p_from AND p_to GROUP BY 1, 2, 3),
       o AS (SELECT * FROM f360.intel_orders(p_from, p_to) WHERE status_class = 'countable'),
       firsts AS (SELECT customer_key, min(bdate) AS first_day FROM f360.intel_orders('2000-01-01', p_to) WHERE status_class = 'countable' AND customer_key IS NOT NULL GROUP BY 1),
       mk AS (SELECT DISTINCT market FROM sp WHERE market IN ('MX', 'CO', 'ROW') UNION SELECT DISTINCT market FROM o)
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'mercado'), '[]') INTO rows FROM (
    SELECT jsonb_build_object('mercado', mk.market,
      'inversion', (SELECT jsonb_build_object('monto', sum(s), 'moneda', min(currency), 'clics', sum(c), 'impresiones', sum(i)) FROM sp WHERE sp.market = mk.market),
      'inversion_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', m, 'amount', s)), '[]')) FROM sp WHERE sp.market = mk.market),
      'venta_neta', (SELECT jsonb_build_object('monto', coalesce(sum(net_product), 0), 'moneda', f360.intel_cur(mk.market)) FROM o WHERE o.market = mk.market),
      'venta_neta_mxn', (SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', mm, 'amount', amt)), '[]'))
                         FROM (SELECT currency, date_trunc('month', bdate)::date mm, sum(net_product) amt FROM o WHERE o.market = mk.market AND NOT suspicious_currency GROUP BY 1, 2) q),
      'pedidos_pagados', (SELECT count(*) FROM o WHERE o.market = mk.market),
      'clientas_nuevas', (SELECT count(DISTINCT o.customer_key) FROM o JOIN firsts f ON f.customer_key = o.customer_key WHERE o.market = mk.market AND f.first_day BETWEEN p_from AND p_to),
      'pedidos_sin_identidad', (SELECT count(*) FROM o WHERE o.market = mk.market AND customer_key IS NULL)) AS x
    FROM mk) q;
  -- ratios on MXN (spend is in MXN; revenue converted with the approved rate)
  SELECT coalesce(jsonb_agg(x || jsonb_build_object(
      'mer', CASE WHEN (x->'inversion_mxn'->>'mxn')::numeric > 0 AND x->'venta_neta_mxn'->>'mxn' IS NOT NULL
                  THEN round((x->'venta_neta_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2) END,
      'cpa_mxn', CASE WHEN (x->>'pedidos_pagados')::int > 0 AND x->'inversion_mxn'->>'mxn' IS NOT NULL THEN round((x->'inversion_mxn'->>'mxn')::numeric / (x->>'pedidos_pagados')::int, 2) END,
      'cac_mxn', CASE WHEN (x->>'clientas_nuevas')::int > 0 AND x->'inversion_mxn'->>'mxn' IS NOT NULL THEN round((x->'inversion_mxn'->>'mxn')::numeric / (x->>'clientas_nuevas')::int, 2) END,
      'roas_atribuido', jsonb_build_object('valor', NULL, 'disponibilidad', 'FALTA', 'por_que', 'Requiere atribución propia (UTM + GA4); nunca el ROAS reportado por Meta'))), '[]') INTO rows
    FROM jsonb_array_elements(rows) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'campana', campaign_name, 'inversion', s, 'moneda', currency) ORDER BY s DESC), '[]') INTO camp FROM (
    SELECT market, currency, coalesce(campaign_name, campaign_id) campaign_name, sum(spend) s FROM f360.marketing_spend_daily WHERE date BETWEEN p_from AND p_to AND spend > 0
    GROUP BY 1, 2, 3 ORDER BY 4 DESC LIMIT 15) q;
  SELECT max(imported_at) INTO upd FROM f360.marketing_spend_daily;
  falt := falt || jsonb_build_object('que', 'ROAS atribuido', 'por_que', 'No hay atribución propia por campaña todavía', 'quien', 'GA4 (permiso de Adrián) + UTM');
  IF g_exp IS NULL THEN falt := falt || jsonb_build_object('que', 'Gasto de Google Ads', 'por_que', 'No se sabe si hay gasto', 'quien', 'Mario'); END IF;
  RETURN jsonb_build_object('data', jsonb_build_object('por_mercado', rows, 'campanas_top', camp,
      'google_ads', CASE WHEN g_exp = false THEN 'sin gasto (confirmado por Mario)' WHEN g_exp THEN 'con gasto' ELSE 'desconocido' END,
      'formulas', jsonb_build_object('mer', 'venta neta (MXN) ÷ inversión (MXN)', 'cpa', 'inversión ÷ pedidos pagados', 'cac', 'inversión ÷ clientas nuevas identificadas')),
    'meta', f360.intel_meta('Gasto publicitario (Meta API) + Commerce Facts', p_from, p_to, 'MXN para razones; venta en moneda original', 'PARCIAL', falt,
      jsonb_build_array('CAC cuenta solo clientas identificadas (los pedidos de invitada sin cuenta no tienen identidad).',
                        'Colombia gasta en MXN y vende en COP: el MER usa la tasa aprobada (o la provisional del mes en curso).'), upd));
END $$;

CREATE OR REPLACE FUNCTION public.f360_intel_query(p_tool text, p_args jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
-- The ONLY entry point of the analyst: a fixed list of tools with typed arguments. No SQL is ever accepted.
DECLARE f date; t date; today date := f360.intel_today(); r jsonb; mk text := upper(coalesce(p_args->>'mercado', ''));
BEGIN
  IF f360.intel_gate('f360_intel_query:' || left(coalesce(p_tool, ''), 40), p_args) IS NULL THEN RETURN f360_board.denied(); END IF;
  BEGIN
    f := coalesce((p_args->>'desde')::date, date_trunc('month', today)::date);
    t := least(coalesce((p_args->>'hasta')::date, today), today);
  EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok', false, 'error', 'Fechas no válidas (AAAA-MM-DD).');
  END;
  IF NOT public.f360_intel_valid_range(f, t) THEN RETURN jsonb_build_object('ok', false, 'error', 'Rango no válido (máximo 800 días).'); END IF;
  r := CASE p_tool
    WHEN 'ventas' THEN f360.intel_sales_core(f, t)
    WHEN 'presupuesto_vs_real' THEN f360.intel_budget_core(f, t)
    WHEN 'avance_meta' THEN f360.intel_goal_core(coalesce(nullif(p_args->>'meta', ''), 'ecommerce_mx_mensual'), coalesce((p_args->>'mes')::date, today))
    WHEN 'marketing' THEN f360.intel_marketing_core(f, t)
    WHEN 'pagos' THEN f360.intel_payments_core(f, t)
    WHEN 'inventario_mx' THEN f360.intel_inventory_core(coalesce((p_args->>'dias')::int, 60))
    WHEN 'margen' THEN f360.intel_margin_core(f, t)
    WHEN 'caja' THEN f360.intel_cash_core(coalesce((p_args->>'mes')::date, (date_trunc('month', today) - interval '1 month')::date))
    WHEN 'proyeccion_cierre' THEN f360.intel_forecast_core(coalesce((p_args->>'mes')::date, today))
    WHEN 'embudo' THEN f360.intel_funnel_core(f, t)
    WHEN 'senales_semana' THEN f360.intel_signals_core(f, t)
    WHEN 'fuentes' THEN f360.intel_sources_core()
    ELSE NULL END;
  IF r IS NULL THEN RETURN jsonb_build_object('ok', false, 'error', 'Herramienta no disponible.'); END IF;
  -- optional market filter on list results (never changes how numbers are computed)
  RETURN jsonb_build_object('ok', true, 'herramienta', p_tool, 'argumentos', p_args) || r;
END $$;

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
  RETURN v;
END $$;

DROP FUNCTION public.f360_ai_reserve(uuid, numeric);
DROP TABLE f360.ai_inflight;
DROP FUNCTION f360.intel_low_sell_page(int, int, int);
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000500';
