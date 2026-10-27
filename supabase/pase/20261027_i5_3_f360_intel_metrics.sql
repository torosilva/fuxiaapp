-- Fuxia 360 · PRODUCCIÓN · 20261024000300_f360_intel_metrics VERBATIM (Mario 2026-10-27: "pasa todo a produccion" / "de acuerdo").
-- Plan: docs/fuxia360/intelligence/I5_PLAN_PRODUCCION.md (earn-in: strategy-board/SB_EARNIN_DELIVERY.md). En staging desde oct.
-- Reversión: supabase/rollbacks/20261024000300_f360_intel_metrics.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000300') THEN RAISE EXCEPTION 'PRE: 20261024000300 ya está'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000200') THEN RAISE EXCEPTION 'PRE: falta 20261024000200'; END IF;
END $$;
-- Fuxia 360 · I1b Centro de Inteligencia — CAPA DE MÉTRICAS (Mario 2026-10-11, aprobado para STAGING). ADDITIVE, READ-ONLY.
-- One layer for BOTH the CEO Cockpit (/direccion) and the AI Business Analyst (f360-analyst): the same numbers, never recomputed
-- in the browser or by the model. No tables, no data changes.
-- Truth rules (growth/02_MEASUREMENT_TRUTH.md + Centro de Inteligencia §1, §5):
--   · money = paid orders (status_class 'countable'), net product revenue, from f360.commerce_orders_reporting (follows audited
--     currency corrections); business date = CDMX; markets apart in their own currency; the original currency is always returned;
--   · MXN consolidation only with f360.fx_rate_for_report (approved month, or — open month only — the last approved month, labelled
--     provisional); a missing rate → consolidated = null + listed as missing; orders flagged MONEDA_SOSPECHOSA and not corrected are
--     never converted (listed apart);
--   · Conciliación analytics exclusions are shown APART (original vs adjusted), never subtracted silently;
--   · nothing is invented: a metric without its source returns availability FALTA, value null and who must provide what.
-- Every public function returns {ok, data, meta}; meta = {fuente, periodo{desde,hasta}, moneda, actualizado_al, disponibilidad
-- (DISPONIBLE | PARCIAL | FALTA), calidad, faltantes[], notas[]}.
-- Access: board members with scope FINANCIAL (Mario, Carolina), second factor as /estrategia. Every call is written to
-- f360_board.access_log; calls from the analyst carry actor_kind 'ai_analyst' (header x-f360-actor: ai_analyst, set by f360-analyst).
-- Rollback: supabase/rollbacks/20261024000300_f360_intel_metrics.down.sql

-- ══ helpers ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION f360.intel_actor() RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE WHEN coalesce(nullif(current_setting('request.headers', true), '')::json->>'x-f360-actor', '') = 'ai_analyst' THEN 'ai_analyst' ELSE 'human' END $$;

-- the gate: same rule as f360_board.require_board_member('FINANCIAL', …) plus the actor kind
CREATE FUNCTION f360.intel_gate(p_rpc text, p_params jsonb DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); why text := f360_board.member_denial(auth.uid(), 'FINANCIAL');
BEGIN
  INSERT INTO f360_board.access_log (auth_user_id, rpc, scope, outcome, reason, object_ref, params_hash, request_id, actor_kind)
    VALUES (uid, p_rpc, 'FINANCIAL', CASE WHEN why IS NULL THEN 'allowed' ELSE 'denied' END, why, NULL, f360_board.params_hash(p_params),
            f360_board.request_id(), f360.intel_actor());
  RETURN CASE WHEN why IS NULL THEN uid END;
END $$;

CREATE FUNCTION f360.intel_meta(p_fuente text, p_desde date, p_hasta date, p_moneda text, p_disp text, p_faltantes jsonb DEFAULT '[]',
  p_notas jsonb DEFAULT '[]', p_actualizado timestamptz DEFAULT NULL, p_calidad text DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('fuente', p_fuente, 'periodo', jsonb_build_object('desde', p_desde, 'hasta', p_hasta), 'moneda', p_moneda,
    'actualizado_al', coalesce(p_actualizado, now()), 'disponibilidad', p_disp, 'calidad', coalesce(p_calidad, CASE p_disp WHEN 'DISPONIBLE' THEN 'buena' WHEN 'PARCIAL' THEN 'parcial' ELSE 'sin datos' END),
    'faltantes', coalesce(p_faltantes, '[]'), 'notas', coalesce(p_notas, '[]'), 'generado_al', clock_timestamp()) $$;

CREATE FUNCTION f360.intel_today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'America/Mexico_City')::date $$;
CREATE FUNCTION f360.intel_cur(p_market text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT CASE p_market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END $$;

-- countable orders in a CDMX date range, with the reporting market/currency, channel and the flags the consolidation needs
CREATE FUNCTION f360.intel_orders(p_from date, p_to date) RETURNS TABLE (
  source_system text, external_ref text, target_id uuid, woo_order_id bigint, bdate date, market text, currency text, channel text,
  status_class text, payment_state text, payment_method text, net_product numeric, order_total numeric, units int,
  customer_key text, excluded boolean, suspicious_currency boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT o.source_system, o.external_ref, o.target_id, o.woo_order_id, (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date,
         o.market_reporting, o.currency_reporting, o.channel, o.status_class, o.payment_state, o.payment_method, o.net_product, o.order_total, o.units,
         coalesce(o.loyalty_customer_id::text, CASE WHEN coalesce(o.woo_customer_id, 0) > 0 THEN 'woo:' || o.woo_customer_id END),
         EXISTS (SELECT 1 FROM f360.sales_rec_analytics_scope s WHERE s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id AND s.excluded),
         EXISTS (SELECT 1 FROM f360.sales_rec_cases c WHERE c.target_id = o.target_id AND c.woo_order_id = o.woo_order_id AND c.flags @> '[{"code":"MONEDA_SOSPECHOSA"}]')
  FROM f360.commerce_orders_reporting o
  WHERE (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date BETWEEN p_from AND p_to
    -- orders of ANOTHER environment received by mistake (e.g. production #5347/#5351 in staging) are evidence, never sales here
    AND NOT EXISTS (SELECT 1 FROM f360.environment_foreign_events fe WHERE fe.target_id = o.target_id AND fe.woo_order_id = o.woo_order_id)
$$;
COMMENT ON FUNCTION f360.intel_orders(date, date) IS 'I1b: one row per order in range (CDMX), reporting market/currency; foreign-environment events excluded.';

-- converts a per-month, per-currency set of amounts to MXN; returns {mxn, rates[], missing[]} (null mxn if any rate is missing)
CREATE FUNCTION f360.intel_to_mxn(p_rows jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE x jsonb; r jsonb; total numeric := 0; rates jsonb := '[]'; missing jsonb := '[]';
BEGIN
  FOR x IN SELECT * FROM jsonb_array_elements(coalesce(p_rows, '[]')) LOOP
    r := f360.fx_rate_for_report(x->>'currency', (x->>'month')::date);
    IF r->>'status' = 'missing' THEN missing := missing || jsonb_build_object('moneda', x->>'currency', 'mes', x->>'month');
    ELSE
      total := total + (x->>'amount')::numeric * (r->>'rate')::numeric;
      IF x->>'currency' <> 'MXN' THEN rates := rates || jsonb_build_object('moneda', x->>'currency', 'mes', x->>'month', 'tasa', r->'rate', 'estado', r->>'status', 'fuente', r->>'source'); END IF;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('mxn', CASE WHEN jsonb_array_length(missing) = 0 THEN round(total, 2) END, 'tasas', rates, 'sin_tasa', missing);
END $$;

-- ══ core metrics (internal; no gate) ═════════════════════════════════════════════════════════════════════════════════════
-- 1 · ventas por mercado × canal (+ periodo anterior, + exclusiones aparte, + consolidado MXN)
CREATE FUNCTION f360.intel_sales_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE len int := p_to - p_from + 1; pf date := p_from - (p_to - p_from + 1); pt date := p_from - 1; rows jsonb; cons jsonb; excl jsonb; susp jsonb;
  first_store date; falt jsonb := '[]'; upd timestamptz;
BEGIN
  WITH cur AS (SELECT * FROM f360.intel_orders(p_from, p_to) WHERE status_class = 'countable'),
       prv AS (SELECT * FROM f360.intel_orders(pf, pt) WHERE status_class = 'countable'),
       keys AS (SELECT market, channel FROM cur UNION SELECT market, channel FROM prv),
       agg AS (
         SELECT k.market, k.channel, f360.intel_cur(k.market) AS currency,
                (SELECT count(*) FROM cur c WHERE c.market = k.market AND c.channel = k.channel) AS orders,
                (SELECT coalesce(sum(units), 0) FROM cur c WHERE c.market = k.market AND c.channel = k.channel) AS units,
                (SELECT coalesce(sum(net_product), 0) FROM cur c WHERE c.market = k.market AND c.channel = k.channel) AS revenue,
                (SELECT count(*) FROM prv c WHERE c.market = k.market AND c.channel = k.channel) AS orders_prev,
                (SELECT coalesce(sum(net_product), 0) FROM prv c WHERE c.market = k.market AND c.channel = k.channel) AS revenue_prev
         FROM keys k)
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'canal', channel, 'moneda', currency, 'pedidos_pagados', orders, 'pares', units,
           'venta_neta', revenue, 'ticket_promedio', CASE WHEN orders > 0 THEN round(revenue / orders, 2) END,
           'anterior', jsonb_build_object('pedidos_pagados', orders_prev, 'venta_neta', revenue_prev,
                         'ticket_promedio', CASE WHEN orders_prev > 0 THEN round(revenue_prev / orders_prev, 2) END),
           -- cálculo: cambio de venta = efecto pedidos (Δpedidos × ticket anterior) + efecto ticket (Δticket × pedidos actuales)
           'explicacion_cambio', CASE WHEN orders_prev > 0 AND orders > 0 THEN jsonb_build_object(
               'cambio_venta', revenue - revenue_prev,
               'por_pedidos', round((orders - orders_prev) * (revenue_prev / orders_prev), 2),
               'por_ticket', round(((revenue / orders) - (revenue_prev / orders_prev)) * orders, 2),
               'formula', 'Δventa = Δpedidos × ticket anterior + Δticket × pedidos actuales') END)
           ORDER BY market, channel), '[]') INTO rows FROM agg;
  -- consolidated MXN (suspicious, uncorrected currency never converted)
  SELECT f360.intel_to_mxn(coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', m, 'amount', amt)), '[]')) INTO cons
    FROM (SELECT currency, date_trunc('month', bdate)::date AS m, sum(net_product) AS amt FROM f360.intel_orders(p_from, p_to)
          WHERE status_class = 'countable' AND NOT suspicious_currency GROUP BY 1, 2) q;
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'moneda', currency, 'pedidos', n, 'venta_neta', amt)), '[]') INTO excl
    FROM (SELECT market, currency, count(*) n, sum(net_product) amt FROM f360.intel_orders(p_from, p_to) WHERE status_class = 'countable' AND excluded GROUP BY 1, 2) q;
  SELECT coalesce(jsonb_agg(jsonb_build_object('pedido', woo_order_id, 'moneda', currency, 'estado', status_class)), '[]') INTO susp
    FROM f360.intel_orders(p_from, p_to) WHERE suspicious_currency;
  SELECT min((occurred_at AT TIME ZONE 'America/Mexico_City')::date) INTO first_store FROM f360.commerce_orders WHERE channel = 'store';
  IF first_store IS NULL OR first_store > p_from THEN
    falt := falt || jsonb_build_object('que', 'Ventas de tienda ' || CASE WHEN first_store IS NULL THEN '(ninguna medida todavía)' ELSE 'anteriores al ' || first_store END,
                                       'por_que', 'Siguen en la app anterior (public.offline_sales), fuera de la medición', 'quien', 'Pase P0E (Carolina decide bazares)');
  END IF;
  IF jsonb_array_length(cons->'sin_tasa') > 0 THEN
    falt := falt || jsonb_build_object('que', 'Tipo de cambio aprobado', 'por_que', 'Sin tasa aprobada no se consolida en MXN', 'quien', 'Mario aprueba la tasa mensual propuesta');
  END IF;
  SELECT greatest(max(last_changed_at), max(first_captured_at)) INTO upd FROM f360.commerce_woo_orders;
  RETURN jsonb_build_object('data', jsonb_build_object('por_mercado_canal', rows, 'consolidado_mxn', cons,
      'excluidas_por_conciliacion', excl, 'moneda_por_conciliar', susp, 'periodo_anterior', jsonb_build_object('desde', pf, 'hasta', pt)),
    'meta', f360.intel_meta('Commerce Facts · pedidos pagados (venta neta de producto, moneda original)', p_from, p_to, 'original por mercado; MXN solo con tasa aprobada',
                            CASE WHEN jsonb_array_length(falt) = 0 THEN 'DISPONIBLE' ELSE 'PARCIAL' END, falt,
                            jsonb_build_array('Montos tal como se cobraron: tratamiento de IVA pendiente de la contadora.',
                                              'Las exclusiones de Conciliación se muestran aparte; la venta original no se modifica.'), upd));
END $$;

-- 2 · presupuesto vs real (prorrateo por días cuando el rango no cubre meses completos)
CREATE FUNCTION f360.intel_budget_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE res jsonb; nver int;
BEGIN
  WITH months AS (SELECT generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month')::date AS m),
  ver AS (SELECT DISTINCT ON (fiscal_year) id, fiscal_year, name, approved_at FROM f360_board.budget_versions WHERE status = 'APPROVED' ORDER BY fiscal_year, approved_at DESC),
  bl AS (
    SELECT l.dim_market AS market, l.dim_channel AS channel, l.currency, l.period_month,
           l.amount * (least(p_to, (l.period_month + interval '1 month - 1 day')::date) - greatest(p_from, l.period_month) + 1)::numeric
             / extract(day FROM (l.period_month + interval '1 month - 1 day'))::numeric AS amount_prorated, ver.name AS version
    FROM f360_board.budget_lines l JOIN ver ON ver.id = l.version_id JOIN months ON months.m = l.period_month
    WHERE l.metric_key = 'revenue_net_product'),
  act AS (SELECT market, channel, sum(net_product) AS revenue FROM f360.intel_orders(p_from, p_to) WHERE status_class = 'countable' GROUP BY 1, 2)
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', b.market, 'canal', b.channel, 'moneda', b.currency, 'presupuesto', round(b.amt, 2),
           'real', coalesce(a.revenue, 0), 'cumplimiento_pct', CASE WHEN b.amt > 0 THEN round(coalesce(a.revenue, 0) / b.amt * 100, 1) END,
           'brecha', round(coalesce(a.revenue, 0) - b.amt, 2), 'version', b.version) ORDER BY b.market, b.channel), '[]') INTO res
  FROM (SELECT market, channel, currency, sum(amount_prorated) AS amt, min(version) AS version FROM bl GROUP BY 1, 2, 3) b
  LEFT JOIN act a ON a.market = b.market AND a.channel = b.channel;
  SELECT count(*) INTO nver FROM f360_board.budget_versions WHERE status = 'APPROVED' AND fiscal_year BETWEEN extract(year FROM p_from) AND extract(year FROM p_to);
  RETURN jsonb_build_object('data', jsonb_build_object('lineas', res),
    'meta', f360.intel_meta('Presupuesto aprobado (f360_board.budget_versions) vs Commerce Facts', p_from, p_to, 'original por mercado',
      CASE WHEN nver = 0 THEN 'FALTA' WHEN jsonb_array_length(res) = 0 THEN 'FALTA' ELSE 'DISPONIBLE' END,
      CASE WHEN nver = 0 THEN jsonb_build_array(jsonb_build_object('que', 'Presupuesto aprobado del año', 'por_que', 'No hay versión aprobada', 'quien', 'Mario define y aprueba; Carolina valida'))
           ELSE '[]' END,
      jsonb_build_array('Cálculo: si el periodo no cubre el mes completo, el presupuesto mensual se prorratea por días.'),
      (SELECT max(approved_at) FROM f360_board.budget_versions)));
END $$;

-- 3 · avance contra una meta mensual (p. ej. ecommerce MX $300,000)
CREATE FUNCTION f360.intel_goal_core(p_goal_key text, p_month date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE g f360_board.goals; m date := date_trunc('month', p_month)::date; m_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  today date := f360.intel_today(); upto date; actual numeric; orders int; d_el int; d_tot int; d_rem int; best jsonb; hist jsonb;
BEGIN
  g := f360_board.goal_for(p_goal_key, m);
  IF g.id IS NULL THEN
    RETURN jsonb_build_object('data', NULL, 'meta', f360.intel_meta('Metas (f360_board.goals)', m, m_end, NULL, 'FALTA',
      jsonb_build_array(jsonb_build_object('que', 'Meta ' || p_goal_key, 'por_que', 'No está registrada para ese mes', 'quien', 'Mario'))));
  END IF;
  upto := least(m_end, today);
  SELECT coalesce(sum(net_product), 0), count(*) INTO actual, orders FROM f360.intel_orders(m, upto)
    WHERE status_class = 'countable' AND market = g.dim_market AND (g.dim_channel IS NULL OR channel = g.dim_channel);
  d_tot := extract(day FROM m_end); d_el := greatest(0, upto - m + 1); d_rem := greatest(0, m_end - upto);
  SELECT coalesce(jsonb_agg(jsonb_build_object('mes', mm, 'venta_neta', amt) ORDER BY mm), '[]') INTO hist FROM (
    SELECT date_trunc('month', bdate)::date mm, sum(net_product) amt FROM f360.intel_orders((m - interval '12 months')::date, m - 1)
    WHERE status_class = 'countable' AND market = g.dim_market AND (g.dim_channel IS NULL OR channel = g.dim_channel) GROUP BY 1) q;
  SELECT jsonb_build_object('mes', x->>'mes', 'venta_neta', (x->>'venta_neta')::numeric) INTO best FROM jsonb_array_elements(hist) x ORDER BY (x->>'venta_neta')::numeric DESC LIMIT 1;
  RETURN jsonb_build_object('data', jsonb_build_object('meta_clave', g.goal_key, 'meta_nombre', g.label, 'mercado', g.dim_market, 'canal', g.dim_channel,
      'moneda', g.currency, 'meta', g.amount, 'meta_definida_por', g.set_by_name, 'meta_motivo', g.reason,
      'real_al_dia', actual, 'pedidos_pagados', orders, 'avance_pct', round(actual / g.amount * 100, 1), 'faltante', greatest(0, g.amount - actual),
      'dias_transcurridos', d_el, 'dias_restantes', d_rem, 'dias_del_mes', d_tot,
      'ritmo_necesario_diario', CASE WHEN d_rem > 0 THEN round(greatest(0, g.amount - actual) / d_rem, 2) END,
      'ritmo_actual_diario', CASE WHEN d_el > 0 THEN round(actual / d_el, 2) END,
      'proyeccion_por_ritmo', CASE WHEN d_el > 0 THEN round(actual / d_el * d_tot, 2) END,
      'mejor_mes_ultimos_12', best, 'historial_12_meses', hist,
      'formulas', jsonb_build_object('ritmo_necesario', '(meta − real) ÷ días restantes', 'proyeccion', 'real ÷ días transcurridos × días del mes (cálculo, no pronóstico)')),
    'meta', f360.intel_meta('Meta registrada por ' || g.set_by_name || ' + Commerce Facts (pedidos pagados)', m, upto, g.currency, 'DISPONIBLE', '[]',
      jsonb_build_array('La proyección por ritmo es un cálculo lineal, no un pronóstico.')));
END $$;

-- 4 · marketing: inversión, MER, CPA, CAC (ROAS atribuido aún no)
CREATE FUNCTION f360.intel_marketing_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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

-- 5 · pagos que no se completan (sin datos personales)
CREATE FUNCTION f360.intel_payments_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rows jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'moneda', currency, 'metodo', metodo, 'creados', n, 'pagados', paid,
           'nunca_pagados', never, 'tasa_no_completado_pct', CASE WHEN n > 0 THEN round(never::numeric / n * 100, 1) END, 'monto_no_cobrado', amt_never)
           ORDER BY market, n DESC), '[]') INTO rows FROM (
    SELECT market, currency, coalesce(nullif(payment_method, ''), 'sin método') metodo, count(*) n, count(*) FILTER (WHERE status_class = 'countable') paid,
           count(*) FILTER (WHERE payment_state = 'never_paid') never, coalesce(sum(order_total) FILTER (WHERE payment_state = 'never_paid'), 0) amt_never
    FROM f360.intel_orders(p_from, p_to) WHERE channel = 'online' GROUP BY 1, 2, 3) q;
  RETURN jsonb_build_object('data', jsonb_build_object('por_metodo', rows),
    'meta', f360.intel_meta('Commerce Facts · pedidos en línea creados vs pagados', p_from, p_to, 'original por mercado', 'DISPONIBLE', '[]',
      jsonb_build_array('"Nunca pagado" incluye intentos repetidos de la misma clienta; Conciliación los distingue caso por caso.')));
END $$;

-- 6 · inventario México: saldo, rotación, baja salida, riesgo de agotarse
CREATE FUNCTION f360.intel_inventory_core(p_days int) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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

-- 7 · margen de contribución (solo si hay costo para TODO lo vendido; si no, FALTA con la cobertura)
CREATE FUNCTION f360.intel_margin_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rows jsonb; cov numeric; est boolean;
BEGIN
  WITH ln AS (
    SELECT o.market, o.channel, o.currency, o.bdate, l.product_id, l.variant_id, l.quantity, l.net,
           (SELECT c FROM f360.product_cost_effective c WHERE c.product_id = l.product_id AND (c.variant_id IS NULL OR c.variant_id = l.variant_id)
              AND (c.market IS NULL OR c.market = o.market) AND c.effective_from <= o.bdate AND (c.effective_to IS NULL OR c.effective_to >= o.bdate)
            ORDER BY (c.variant_id IS NOT NULL) DESC, (c.market IS NOT NULL) DESC, c.effective_from DESC LIMIT 1) AS cost
    FROM f360.intel_orders(p_from, p_to) o JOIN f360.commerce_order_lines l ON l.source_system = o.source_system AND l.external_ref = o.external_ref
    WHERE o.status_class = 'countable')
  SELECT round(coalesce(sum(quantity) FILTER (WHERE cost IS NOT NULL), 0)::numeric / nullif(sum(quantity), 0) * 100, 1),
         bool_or((cost).cost_basis = 'estimated')
    INTO cov, est FROM ln;
  IF coalesce(cov, 0) < 100 THEN
    RETURN jsonb_build_object('data', jsonb_build_object('cobertura_costo_pct', coalesce(cov, 0)),
      'meta', f360.intel_meta('Commerce Facts + costos aprobados (product_cost_versions)', p_from, p_to, NULL, 'FALTA',
        jsonb_build_array(jsonb_build_object('que', 'Costo por modelo', 'por_que', format('Solo %s%% de los pares vendidos tienen costo aprobado', coalesce(cov, 0)), 'quien', 'Carolina'),
                          jsonb_build_object('que', 'Comisión de pasarelas y costo de envío real', 'por_que', 'No están en ninguna fuente', 'quien', 'Contadora / Mario'))));
  END IF;
  -- (all sold pairs have an approved cost) — contribution = revenue − COGS − marketing; payment fees/shipping still missing → ESTIMADO
  rows := '[]';
  RETURN jsonb_build_object('data', jsonb_build_object('cobertura_costo_pct', cov, 'nota', 'Cálculo completo pendiente de comisiones y envíos'),
    'meta', f360.intel_meta('Commerce Facts + costos aprobados', p_from, p_to, NULL, 'PARCIAL',
      jsonb_build_array(jsonb_build_object('que', 'Comisión de pasarelas y costo de envío real', 'por_que', 'No están en ninguna fuente', 'quien', 'Contadora / Mario')),
      CASE WHEN est THEN jsonb_build_array('ESTIMADO: incluye costos estimados (no confirmados).') ELSE '[]' END));
END $$;

-- 8 · caja y compromisos (cierre mensual aprobado + compromisos pendientes)
CREATE FUNCTION f360.intel_cash_core(p_month date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE per f360_board.fiscal_periods; entries jsonb; pend int; comm jsonb; m date := date_trunc('month', p_month)::date;
BEGIN
  SELECT * INTO per FROM f360_board.fiscal_periods WHERE kind = 'MONTH' AND period_start = m LIMIT 1;
  SELECT coalesce(jsonb_agg(jsonb_build_object('cuenta', a.label, 'componente', a.component, 'monto', e.amount, 'moneda', e.currency, 'fuente', e.source,
           'aprobado_por', e.approved_by_name) ORDER BY a.sort), '[]') INTO entries
    FROM f360_board.monthly_close_entries e JOIN f360_board.close_accounts a USING (account_key)
    WHERE e.period_id = per.id AND e.status = 'active' AND e.approved_by IS NOT NULL;
  SELECT count(*) INTO pend FROM f360_board.monthly_close_entries WHERE period_id = per.id AND status = 'active' AND approved_by IS NULL;
  SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', currency, 'monto', amt, 'compromisos', n, 'proximo_vencimiento', nxt, 'aprobados', ap) ORDER BY currency), '[]') INTO comm FROM (
    SELECT currency, sum(amount) amt, count(*) n, min(due_date) nxt, count(*) FILTER (WHERE approved_at IS NOT NULL) ap
    FROM f360_board.commitments_current WHERE state = 'pendiente' AND due_date <= f360.intel_today() + 90 GROUP BY 1) q;
  RETURN jsonb_build_object('data', jsonb_build_object('mes', m, 'estado_del_mes', per.status, 'cierre_aprobado', entries, 'capturas_por_aprobar', pend,
      'compromisos_90_dias', comm),
    'meta', f360.intel_meta('Cierre mensual (capturas aprobadas) + compromisos financieros', m, (m + interval '1 month - 1 day')::date, 'original',
      CASE WHEN jsonb_array_length(entries) = 0 THEN 'FALTA' ELSE 'PARCIAL' END,
      CASE WHEN jsonb_array_length(entries) = 0 THEN jsonb_build_array(jsonb_build_object('que', 'Cierre del mes (bancos, efectivo, gastos)',
        'por_que', CASE WHEN pend > 0 THEN format('%s capturas esperan aprobación', pend) ELSE 'Sin capturas' END, 'quien', 'Contadora captura; Mario o Carolina aprueban')) ELSE '[]' END,
      jsonb_build_array('Solo cuentan montos aprobados; no hay conexión bancaria.')));
END $$;

-- 9 · proyección de cierre por ritmo y brecha contra metas / presupuesto
CREATE FUNCTION f360.intel_forecast_core(p_month date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE m date := date_trunc('month', p_month)::date; m_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date; upto date;
  d_el int; d_tot int; rows jsonb; budget jsonb;
BEGIN
  upto := least(m_end, f360.intel_today()); d_el := greatest(1, upto - m + 1); d_tot := extract(day FROM m_end);
  budget := (f360.intel_budget_core(m, m_end))->'data'->'lineas';
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'canal', channel, 'moneda', f360.intel_cur(market), 'real_al_dia', amt,
           'proyeccion_por_ritmo', round(amt / d_el * d_tot, 2),
           'meta', (SELECT g.amount FROM f360_board.goals g WHERE g.dim_market = q.market AND g.dim_channel = q.channel AND g.effective_from <= m ORDER BY g.effective_from DESC, g.set_at DESC LIMIT 1),
           'presupuesto', (SELECT (b->>'presupuesto')::numeric FROM jsonb_array_elements(budget) b WHERE b->>'mercado' = q.market AND b->>'canal' = q.channel))
           ORDER BY market, channel), '[]') INTO rows FROM (
    SELECT market, channel, sum(net_product) amt FROM f360.intel_orders(m, upto) WHERE status_class = 'countable' GROUP BY 1, 2) q;
  SELECT coalesce(jsonb_agg(r || jsonb_build_object('brecha_vs_meta', CASE WHEN r->>'meta' IS NOT NULL THEN (r->>'proyeccion_por_ritmo')::numeric - (r->>'meta')::numeric END,
           'brecha_vs_presupuesto', CASE WHEN r->>'presupuesto' IS NOT NULL THEN (r->>'proyeccion_por_ritmo')::numeric - (r->>'presupuesto')::numeric END)), '[]')
    INTO rows FROM jsonb_array_elements(rows) r;
  RETURN jsonb_build_object('data', jsonb_build_object('mes', m, 'dias_transcurridos', d_el, 'dias_del_mes', d_tot, 'lineas', rows,
      'pronostico_formal', (SELECT count(*) FROM f360_board.forecast_versions WHERE status = 'PUBLISHED')),
    'meta', f360.intel_meta('Commerce Facts + metas + presupuesto aprobado', m, upto, 'original por mercado', 'PARCIAL',
      jsonb_build_array(jsonb_build_object('que', 'Pronóstico formal', 'por_que', 'No hay pronóstico publicado; se muestra proyección por ritmo', 'quien', 'Mario (Estrategia)')),
      jsonb_build_array('Proyección por ritmo = real ÷ días transcurridos × días del mes. Es un cálculo lineal, no un pronóstico.')));
END $$;

-- 10 · embudo en línea (lo que existe hoy: pedidos creados y pagados; visitas cuando GA4 esté conectado)
CREATE FUNCTION f360.intel_funnel_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE rows jsonb; ga4 text := (SELECT config_status FROM f360.measurement_sources WHERE key = 'ga4');
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('mercado', market, 'etapas', jsonb_build_array(
      jsonb_build_object('etapa', 'Visitas', 'valor', NULL, 'disponibilidad', 'FALTA'),
      jsonb_build_object('etapa', 'Vieron un producto', 'valor', NULL, 'disponibilidad', 'FALTA'),
      jsonb_build_object('etapa', 'Agregaron al carrito', 'valor', NULL, 'disponibilidad', 'FALTA'),
      jsonb_build_object('etapa', 'Hicieron pedido', 'valor', n, 'disponibilidad', 'DISPONIBLE'),
      jsonb_build_object('etapa', 'Pagaron', 'valor', paid, 'disponibilidad', 'DISPONIBLE'))) ORDER BY market), '[]') INTO rows FROM (
    SELECT market, count(*) n, count(*) FILTER (WHERE status_class = 'countable') paid FROM f360.intel_orders(p_from, p_to) WHERE channel = 'online' GROUP BY 1) q;
  RETURN jsonb_build_object('data', jsonb_build_object('por_mercado', rows),
    'meta', f360.intel_meta('Commerce Facts (pedidos) · GA4 (' || coalesce(ga4, 'NOT_CONFIGURED') || ')', p_from, p_to, NULL, 'PARCIAL',
      jsonb_build_array(jsonb_build_object('que', 'Visitas, vistas de producto y carrito', 'por_que', 'Google Analytics aún no da permiso de lectura', 'quien', 'Adrián (Lector para fuxia360-analytics@…)'))));
END $$;

-- 11 · señales con evidencia para las 3 prioridades semanales (reglas fijas; el analista recomienda, la base solo constata)
CREATE FUNCTION f360.intel_signals_core(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s jsonb := '[]'; g jsonb; x jsonb; inv jsonb; mk jsonb;
BEGIN
  g := (f360.intel_goal_core('ecommerce_mx_mensual', f360.intel_today()))->'data';
  IF g IS NOT NULL AND (g->>'ritmo_necesario_diario') IS NOT NULL AND coalesce((g->>'ritmo_actual_diario')::numeric, 0) * 2 < (g->>'ritmo_necesario_diario')::numeric THEN
    s := s || jsonb_build_object('codigo', 'META_ECOMMERCE_MX', 'area', 'ventas', 'titulo', 'El ritmo de ecommerce México está lejos de la meta',
      'evidencia', jsonb_build_object('real_al_dia', g->'real_al_dia', 'meta', g->'meta', 'ritmo_actual_diario', g->'ritmo_actual_diario',
                                      'ritmo_necesario_diario', g->'ritmo_necesario_diario', 'mejor_mes_ultimos_12', g->'mejor_mes_ultimos_12'),
      'tipo', 'hecho + cálculo');
  END IF;
  FOR x IN SELECT * FROM jsonb_array_elements((f360.intel_payments_core(p_from, p_to))->'data'->'por_metodo') LOOP
    IF (x->>'creados')::int >= 3 AND (x->>'tasa_no_completado_pct')::numeric >= 30 THEN
      s := s || jsonb_build_object('codigo', 'PAGOS_NO_COMPLETADOS', 'area', 'conversión', 'titulo', format('Pagos que no se completan con %s (%s)', x->>'metodo', x->>'mercado'),
        'evidencia', x, 'tipo', 'hecho');
    END IF;
  END LOOP;
  FOR mk IN SELECT * FROM jsonb_array_elements((f360.intel_marketing_core(p_from, p_to))->'data'->'por_mercado') LOOP
    IF coalesce((mk->'inversion'->>'monto')::numeric, 0) > 0 AND (mk->>'pedidos_pagados')::int = 0 THEN
      s := s || jsonb_build_object('codigo', 'INVERSION_SIN_VENTAS', 'area', 'marketing', 'titulo', format('Inversión en %s sin pedidos pagados en el periodo', mk->>'mercado'),
        'evidencia', jsonb_build_object('mercado', mk->'mercado', 'inversion', mk->'inversion', 'pedidos_pagados', 0), 'tipo', 'hecho');
    END IF;
  END LOOP;
  inv := (f360.intel_inventory_core(60))->'data';
  IF jsonb_array_length(inv->'baja_salida') > 0 THEN
    s := s || jsonb_build_object('codigo', 'INVENTARIO_BAJA_SALIDA', 'area', 'inventario', 'titulo', 'Modelos con pares y sin ventas en 60 días',
      'evidencia', jsonb_build_object('modelos', jsonb_array_length(inv->'baja_salida'),
        'pares', (SELECT sum((z->>'pares')::int) FROM jsonb_array_elements(inv->'baja_salida') z), 'ejemplos', (SELECT jsonb_agg(z) FROM (SELECT z FROM jsonb_array_elements(inv->'baja_salida') z LIMIT 5) q)),
      'tipo', 'hecho');
  END IF;
  IF jsonb_array_length(inv->'riesgo_agotarse') > 0 THEN
    s := s || jsonb_build_object('codigo', 'RIESGO_AGOTARSE', 'area', 'inventario', 'titulo', 'Modelos que se agotarían en menos de 3 semanas al ritmo actual',
      'evidencia', inv->'riesgo_agotarse', 'tipo', 'cálculo');
  END IF;
  RETURN jsonb_build_object('data', jsonb_build_object('senales', s),
    'meta', f360.intel_meta('Reglas fijas sobre ventas, pagos, marketing e inventario', p_from, p_to, NULL, 'DISPONIBLE', '[]',
      jsonb_build_array('Las señales son hechos o cálculos con evidencia. Las prioridades y responsables los propone el analista como recomendación.')));
END $$;

-- 12 · disponibilidad de fuentes (lo que falta y de quién)
CREATE FUNCTION f360.intel_sources_core() RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('data', jsonb_build_object('fuentes', jsonb_build_array(
      jsonb_build_object('fuente', 'Ventas en línea', 'estado', 'DISPONIBLE', 'desde', (SELECT min(occurred_at)::date FROM f360.commerce_orders WHERE channel = 'online')),
      jsonb_build_object('fuente', 'Ventas de tienda', 'estado', 'PARCIAL', 'desde', (SELECT min(occurred_at)::date FROM f360.commerce_orders WHERE channel = 'store'), 'falta', 'P0E (ventas previas)'),
      jsonb_build_object('fuente', 'Presupuesto aprobado', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360_board.budget_versions WHERE status = 'APPROVED') THEN 'DISPONIBLE' ELSE 'FALTA' END, 'quien', 'Mario'),
      jsonb_build_object('fuente', 'Metas', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360_board.goals) THEN 'DISPONIBLE' ELSE 'FALTA' END, 'quien', 'Mario'),
      jsonb_build_object('fuente', 'Costo por modelo', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360.product_cost_effective) THEN 'PARCIAL' ELSE 'FALTA' END, 'quien', 'Carolina'),
      jsonb_build_object('fuente', 'Cierre mensual (caja, gastos)', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360_board.monthly_close_entries WHERE approved_by IS NOT NULL) THEN 'PARCIAL' ELSE 'FALTA' END, 'quien', 'Contadora + aprobación'),
      jsonb_build_object('fuente', 'Gasto Meta', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360.marketing_spend_daily) THEN 'DISPONIBLE' ELSE 'FALTA' END, 'actualizado', (SELECT max(imported_at) FROM f360.marketing_spend_daily)),
      jsonb_build_object('fuente', 'Tipo de cambio aprobado', 'estado', CASE WHEN EXISTS (SELECT 1 FROM f360.fx_rates WHERE status = 'approved') THEN 'DISPONIBLE' ELSE 'FALTA' END,
                         'propuestas_pendientes', (SELECT count(*) FROM f360.fx_rates WHERE status = 'proposed'), 'quien', 'Mario aprueba'),
      jsonb_build_object('fuente', 'Google Analytics (visitas)', 'estado', 'FALTA', 'quien', 'Adrián: Lector a fuxia360-analytics@fuxia360.iam.gserviceaccount.com'),
      jsonb_build_object('fuente', 'Inventario', 'estado', 'PARCIAL', 'falta', 'Conteo físico; 179 pares de la app anterior')
    )), 'meta', f360.intel_meta('Estado de fuentes del Centro de Inteligencia', f360.intel_today(), f360.intel_today(), NULL, 'DISPONIBLE')) $$;

-- ══ CEO Cockpit: las 8 tarjetas en una llamada ═══════════════════════════════════════════════════════════════════════════
CREATE FUNCTION f360.intel_cockpit_core(p_week_start date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE ws date := p_week_start - (extract(isodow FROM p_week_start)::int - 1); we date; ms date; me date; today date := f360.intel_today();
BEGIN
  we := least(ws + 6, today); ms := date_trunc('month', we)::date; me := least((ms + interval '1 month - 1 day')::date, today);
  RETURN jsonb_build_object('semana', jsonb_build_object('desde', ws, 'hasta', we), 'mes', jsonb_build_object('desde', ms, 'hasta', me),
    'tarjetas', jsonb_build_array(
      jsonb_build_object('id', 1, 'titulo', 'Ventas netas vs presupuesto', 'semana', f360.intel_sales_core(ws, we), 'mes', f360.intel_sales_core(ms, me),
                         'presupuesto_semana', f360.intel_budget_core(ws, we), 'presupuesto_mes', f360.intel_budget_core(ms, me)),
      jsonb_build_object('id', 2, 'titulo', 'Ecommerce México hacia $300,000', 'valor', f360.intel_goal_core('ecommerce_mx_mensual', me)),
      jsonb_build_object('id', 3, 'titulo', 'Ventas por país y canal', 'valor', f360.intel_sales_core(ms, me)),
      jsonb_build_object('id', 4, 'titulo', 'Margen de contribución', 'valor', f360.intel_margin_core(ms, me)),
      jsonb_build_object('id', 5, 'titulo', 'Inversión, MER, CPA, CAC', 'valor', f360.intel_marketing_core(ms, me)),
      jsonb_build_object('id', 6, 'titulo', 'Inventario México', 'valor', f360.intel_inventory_core(60)),
      jsonb_build_object('id', 7, 'titulo', 'Caja y compromisos', 'valor', f360.intel_cash_core((ms - interval '1 month')::date)),
      jsonb_build_object('id', 8, 'titulo', 'Cierre proyectado y brecha', 'valor', f360.intel_forecast_core(ms))),
    'fuentes', f360.intel_sources_core());
END $$;

-- ══ public wrappers (gate + log) ═════════════════════════════════════════════════════════════════════════════════════════
CREATE FUNCTION public.f360_intel_valid_range(p_from date, p_to date) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_from IS NOT NULL AND p_to IS NOT NULL AND p_from <= p_to AND p_to - p_from <= 800 AND p_from >= '2020-01-01' $$;

CREATE FUNCTION public.f360_intel_cockpit(p_week_start date DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF f360.intel_gate('f360_intel_cockpit', jsonb_build_object('w', p_week_start)) IS NULL THEN RETURN f360_board.denied(); END IF;
  RETURN jsonb_build_object('ok', true) || f360.intel_cockpit_core(coalesce(p_week_start, f360.intel_today()));
END $$;

CREATE FUNCTION public.f360_intel_query(p_tool text, p_args jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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

-- ══ grants ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION f360.intel_actor(), f360.intel_gate(text, jsonb), f360.intel_meta(text, date, date, text, text, jsonb, jsonb, timestamptz, text), f360.intel_today(),
  f360.intel_cur(text), f360.intel_orders(date, date), f360.intel_to_mxn(jsonb), f360.intel_sales_core(date, date), f360.intel_budget_core(date, date),
  f360.intel_goal_core(text, date), f360.intel_marketing_core(date, date), f360.intel_payments_core(date, date), f360.intel_inventory_core(int),
  f360.intel_margin_core(date, date), f360.intel_cash_core(date), f360.intel_forecast_core(date), f360.intel_funnel_core(date, date),
  f360.intel_signals_core(date, date), f360.intel_sources_core(), f360.intel_cockpit_core(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_intel_cockpit(date), public.f360_intel_query(text, jsonb), public.f360_intel_valid_range(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_intel_cockpit(date), public.f360_intel_query(text, jsonb), public.f360_intel_valid_range(date, date) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261024000300', 'f360_intel_metrics', '{}');
COMMIT;
