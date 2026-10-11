-- PASE · Growth War Room (S-G1) + Conciliación de Ventas + exclusiones + textos + corrección de moneda + eventos ajenos
-- (Mario 2026-10-11: "autorizo los despliegues y pases a producción de Growth y P0D"). = these migrations, verbatim and in order,
-- + their schema_migrations rows, in ONE transaction:
--   20261021000100_f360_growth_cockpit · 20261022000100_f360_sales_reconciliation · 20261022000200_f360_growth_exclusions
--   20261022000300_f360_sales_rec_wording · 20261022000400_f360_currency_corrections · 20261022000500_f360_environment_foreign_events
-- ADDITIVE: new functions/views/append-only tables; WooCommerce, Commerce Facts rows, inventory and gateways are not touched.
-- Loads NO decisions, exclusions, corrections or foreign-event marks (staging examples never come to production).
-- Applied with scripts/f360/prod_sql.sh (dry-run first). Rollback: supabase/rollbacks/*.down.sql in reverse order.
BEGIN;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261021000100','20261022000100','20261022000200','20261022000300','20261022000400','20261022000500'))
    THEN RAISE EXCEPTION 'ABORT: alguna de estas migraciones ya está aplicada'; END IF;
END $$;

-- ===== 20261021000100_f360_growth_cockpit =====
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261021000100', 'f360_growth_cockpit', '{}');

-- ===== 20261022000100_f360_sales_reconciliation =====
-- Fuxia 360 · Conciliación de Ventas (Growth 360). Mario 2026-10-10: STAGING only; design SALES_RECONCILIATION_DESIGN.md.
-- ADDITIVE. Reads Commerce Facts (f360.commerce_woo_orders & co.) and NEVER changes them, WooCommerce or any gateway.
-- Five states kept apart (Mario §5):
--   1. Woo status ............ commerce_woo_orders.woo_status (source, untouched)
--   2. Financial evidence .... derived from Commerce Facts + the latest read-only Woo evidence snapshot (sales_rec_evidence)
--   3. Human classification .. sales_rec_decisions (append-only; a newer decision supersedes, history stays)
--   4. Reconciliation state .. derived (pending / reviewed / conflict / changed after review / under investigation)
--   5. Analytics scope ....... sales_rec_exclusions (append-only, separate action with reason; NOT applied to any metric yet)
-- A human "Venta confirmada" never turns an order into a charged sale: financial evidence is computed only from Woo/gateway data.
-- Duplicates are only CANDIDATES (rule + the other order), never confirmed automatically.
-- Access: ONLY f360.customer_pii_viewers (Carolina, Mario) — f360.require_pii_viewer(). Evidence rows are written only by the
-- f360-woo-sync function (service role) after it verified the caller; they hold no card data, no raw notes and no customer data.
-- Depends on 20261021000100 (f360.classify_channel_v1).
-- Rollback: supabase/rollbacks/20261022000100_f360_sales_reconciliation.down.sql

-- ══ 1 · Evidence snapshots (minimal, structured) ══════════════════════════════
CREATE TABLE f360.sales_rec_evidence (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  source          text NOT NULL CHECK (source IN ('woo_rest_order')),
  source_ref      text NOT NULL,                                  -- e.g. woo_staging4:order/5351
  woo_status      text NOT NULL,
  date_paid       timestamptz,
  transaction_ref text CHECK (transaction_ref IS NULL OR length(transaction_ref) <= 100),
  payment_method  text,
  order_total     numeric(14,2),
  currency        text,
  refund_total    numeric(14,2) NOT NULL DEFAULT 0,
  gateway_result  text NOT NULL CHECK (gateway_result IN ('approved', 'rejected', 'pending', 'refunded', 'transaction_only', 'no_evidence', 'order_missing')),
  signals         text[] NOT NULL DEFAULT '{}',                   -- derived codes only (never note text)
  result          text NOT NULL,                                  -- one-line human summary, built server-side
  evidence_hash   text NOT NULL,                                  -- sha256 of the canonical snapshot
  queried_by      uuid NOT NULL,
  queried_by_name text NOT NULL,
  queried_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sales_rec_evidence_order_idx ON f360.sales_rec_evidence (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_evidence ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_evidence_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_evidence
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 2 · Human classification (append-only) ════════════════════════════════════
CREATE TABLE f360.sales_rec_decisions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  decision        text NOT NULL CHECK (decision IN ('venta_confirmada', 'no_se_concreto', 'duplicado', 'prueba', 'reembolso', 'requiere_investigacion')),
  duplicate_of    bigint CHECK (duplicate_of IS NULL OR decision = 'duplicado'),
  comment         text CHECK (comment IS NULL OR length(comment) <= 1000),
  evidence_id     bigint REFERENCES f360.sales_rec_evidence(id),
  woo_status_seen text NOT NULL,                                  -- what the source said when the person decided
  facts_hash_seen text,                                           -- commerce_woo_orders.economics_hash at decision time
  financial_seen  text NOT NULL,                                  -- financial evidence state at decision time
  supersedes      bigint UNIQUE REFERENCES f360.sales_rec_decisions(id),
  decided_by      uuid NOT NULL,
  decided_by_name text NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (decision <> 'duplicado' OR duplicate_of IS NOT NULL)
);
CREATE INDEX sales_rec_decisions_order_idx ON f360.sales_rec_decisions (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_decisions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_decisions_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_decisions
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 3 · Analytics scope (separate authorized action, append-only) ════════════
CREATE TABLE f360.sales_rec_exclusions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  action          text NOT NULL CHECK (action IN ('exclude', 'include')),
  reason          text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
  supersedes      bigint UNIQUE REFERENCES f360.sales_rec_exclusions(id),
  decided_by      uuid NOT NULL,
  decided_by_name text NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sales_rec_exclusions_order_idx ON f360.sales_rec_exclusions (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_exclusions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_exclusions_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_exclusions
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Current analytics scope per order (only orders with an exclusion history appear). Not consumed by any metric yet.
CREATE VIEW f360.sales_rec_analytics_scope AS
  SELECT DISTINCT ON (target_id, woo_order_id) target_id, woo_order_id, action = 'exclude' AS excluded, reason, decided_by_name, decided_at
  FROM f360.sales_rec_exclusions ORDER BY target_id, woo_order_id, id DESC;

-- ══ 4 · Cases: facts + flags + states (derived, nothing stored) ═══════════════
CREATE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at, o.market, o.currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
), enriched AS (
  SELECT b.*, ev.id AS evidence_id, ev.gateway_result, ev.transaction_ref, ev.queried_at AS evidence_at, ev.woo_status AS evidence_woo_status,
         d.id AS decision_id, d.decision, d.comment AS decision_comment, d.decided_by_name, d.decided_at, d.duplicate_of,
         d.woo_status_seen, d.facts_hash_seen,
         x.excluded, x.reason AS exclusion_reason,
         dup.candidates AS duplicate_candidates, rtr.retry_paid_order
  FROM base b
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_evidence e WHERE e.target_id = b.target_id AND e.woo_order_id = b.woo_order_id ORDER BY e.id DESC LIMIT 1) ev ON true
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_decisions d WHERE d.target_id = b.target_id AND d.woo_order_id = b.woo_order_id ORDER BY d.id DESC LIMIT 1) d ON true
  LEFT JOIN f360.sales_rec_analytics_scope x ON x.target_id = b.target_id AND x.woo_order_id = b.woo_order_id
  LEFT JOIN LATERAL (
    SELECT array_agg(b2.woo_order_id ORDER BY b2.woo_order_id) AS candidates FROM base b2
    WHERE b2.target_id = b.target_id AND b2.woo_order_id <> b.woo_order_id AND b2.market = b.market AND b2.currency = b.currency
      AND b2.order_total = b.order_total AND b.order_total > 0
      AND b2.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND abs(extract(epoch FROM b2.created_at - b.created_at)) <= 48 * 3600
      AND b.ever_paid AND b2.ever_paid                                  -- a duplicate matters only when both were paid
      AND (b.woo_customer_id IS NULL OR b2.woo_customer_id IS NULL OR b.woo_customer_id = b2.woo_customer_id)) dup ON true
  LEFT JOIN LATERAL (                                                   -- unpaid attempt followed by a paid one = retry, not duplicate
    SELECT min(b3.woo_order_id) AS retry_paid_order FROM base b3
    WHERE NOT b.ever_paid AND b3.ever_paid AND b3.target_id = b.target_id AND b3.market = b.market AND b3.currency = b.currency
      AND b3.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND b3.created_at > b.created_at AND b3.created_at - b.created_at <= interval '48 hours'
      AND (b.woo_customer_id IS NULL OR b3.woo_customer_id IS NULL OR b.woo_customer_id = b3.woo_customer_id)) rtr ON true
), fin AS (
  SELECT e.*,
    CASE
      WHEN NOT e.ever_paid AND e.gateway_result = 'approved' THEN 'CONTRADICTORIA'
      WHEN NOT e.ever_paid THEN 'SIN_COBRO'
      WHEN e.gateway_result = 'order_missing' THEN 'NO_EXISTE_EN_WOO'
      WHEN e.woo_status = 'refunded' OR (e.refund_total > 0 AND e.refund_total >= e.order_total) THEN 'REEMBOLSADO'
      WHEN e.refund_total > 0 THEN 'REEMBOLSO_PARCIAL'
      WHEN e.gateway_result = 'rejected' THEN 'CONTRADICTORIA'
      WHEN e.evidence_id IS NOT NULL AND e.transaction_ref IS NOT NULL AND e.gateway_result IN ('approved', 'transaction_only') THEN 'COBRO_CON_TRANSACCION'
      WHEN e.evidence_id IS NOT NULL THEN 'PAGO_SIN_TRANSACCION'
      ELSE 'PAGO_REGISTRADO_WOO'
    END AS financial_state
  FROM enriched e
), flagged AS (
  SELECT f.*, coalesce((SELECT jsonb_agg(fl) FROM (
    SELECT jsonb_build_object('code', 'NO_CONCRETADO', 'kind', 'no_concretado',
             'why', 'Nunca se registró pago. Estado en WooCommerce: ' || f.woo_status || '.') fl WHERE NOT f.ever_paid
    UNION ALL
    SELECT jsonb_build_object('code', 'REINTENTO_PAGADO', 'kind', 'info', 'paid_order', f.retry_paid_order,
             'why', 'Mismos productos y total: la clienta lo volvió a intentar y pagó en el pedido #' || f.retry_paid_order || ' (no es venta perdida).')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está "' || f.woo_status || '", sin reembolso registrado.')
      WHERE f.ever_paid AND f.woo_status IN ('cancelled', 'failed') AND f.refund_total = 0
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGADO_SIN_EVIDENCIA', 'kind', 'financiera', 'why',
             CASE WHEN f.paid_at IS NULL THEN 'Woo lo marca pagado (' || f.woo_status || ') pero no tiene fecha de pago.'
                  WHEN f.payment_method IS NULL THEN 'Pagado sin método de pago registrado.'
                  ELSE 'Consultado en WooCommerce: pagado sin número de transacción de la pasarela.' END)
      WHERE f.ever_paid AND f.woo_status IN ('processing', 'completed', 'on-hold')
        AND (f.paid_at IS NULL OR f.payment_method IS NULL OR f.financial_state = 'PAGO_SIN_TRANSACCION')
    UNION ALL
    SELECT jsonb_build_object('code', 'EVIDENCIA_CONTRADICE', 'kind', 'financiera', 'why',
             CASE WHEN f.ever_paid THEN 'Woo lo tiene como pagado pero la nota de la pasarela dice rechazado.'
                  ELSE 'La nota de la pasarela dice aprobado pero Woo no registró el pago.' END)
      WHERE f.financial_state = 'CONTRADICTORIA'
    UNION ALL
    SELECT jsonb_build_object('code', 'NO_EXISTE_EN_WOO', 'kind', CASE WHEN f.ever_paid THEN 'financiera' ELSE 'info' END,
             'why', 'Al consultarlo (' || to_char(f.evidence_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') ||
                    ') WooCommerce ya no tenía este pedido' || CASE WHEN f.ever_paid THEN ', y Fuxia 360 lo capturó con pago registrado.' ELSE '.' END)
      WHERE f.gateway_result = 'order_missing'
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_PRUEBA', 'kind', 'revision', 'why',
             CASE WHEN f.payment_method ~* '(prueba|test|sandbox)' THEN 'Método de pago de prueba: ' || f.payment_method || '.'
                  ELSE 'Pedido pagado por 0.' END)
      WHERE f.payment_method ~* '(prueba|test|sandbox)' OR (f.ever_paid AND f.order_total = 0)
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'kind', 'revision', 'candidates', to_jsonb(f.duplicate_candidates),
             'why', 'Dos pedidos PAGADOS con el mismo total y los mismos productos, misma clienta (o sin cuenta), en menos de 48 h: #' ||
                    array_to_string(f.duplicate_candidates, ', #') || '. Es un candidato: confirma o descarta.')
      WHERE f.duplicate_candidates IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'REEMBOLSO', 'kind', 'reembolso',
             'why', 'Reembolso registrado en WooCommerce por ' || f.refund_total || ' ' || f.currency || '.')
      WHERE f.refund_total > 0 OR f.woo_status = 'refunded'
  ) q), '[]'::jsonb) AS flags
  FROM fin f
)
SELECT g.*,
  EXISTS (SELECT 1 FROM jsonb_array_elements(g.flags) z WHERE z->>'kind' = 'financiera') AS has_financial,
  CASE
    WHEN g.decision IS NULL THEN NULL
    WHEN g.decision = 'venta_confirmada' AND g.financial_state IN ('SIN_COBRO', 'CONTRADICTORIA', 'REEMBOLSADO', 'PAGO_SIN_TRANSACCION', 'NO_EXISTE_EN_WOO')
      THEN 'Confirmada como venta, pero la evidencia financiera dice: ' || g.financial_state || '. No cuenta como cobro.'
    WHEN g.decision = 'no_se_concreto' AND g.financial_state IN ('COBRO_CON_TRANSACCION', 'PAGO_REGISTRADO_WOO')
      THEN 'Marcada "no se concretó", pero hay pago registrado y ningún reembolso.'
    WHEN g.decision IN ('duplicado', 'prueba') AND g.ever_paid AND g.refund_total = 0 AND g.woo_status NOT IN ('cancelled', 'failed', 'refunded')
      THEN 'Marcada "' || g.decision || '", pero tiene pago registrado y ningún reembolso.'
    WHEN g.decision = 'reembolso' AND g.refund_total = 0 AND g.woo_status <> 'refunded'
      THEN 'Marcada "reembolso", pero WooCommerce no tiene ningún reembolso registrado.'
  END AS conflict
FROM flagged g;

CREATE VIEW f360.sales_rec_cases_state AS
  SELECT c.*,
    CASE
      WHEN c.decision IS NULL AND c.has_financial THEN 'pendiente_discrepancia'
      WHEN c.decision IS NULL AND jsonb_array_length(c.flags) > 0 THEN 'pendiente'
      WHEN c.decision IS NULL THEN 'sin_novedad'
      WHEN c.woo_status_seen IS DISTINCT FROM c.woo_status OR c.facts_hash_seen IS DISTINCT FROM c.economics_hash THEN 'cambio_despues'
      WHEN c.decision = 'requiere_investigacion' THEN 'en_investigacion'
      WHEN c.conflict IS NOT NULL THEN 'conflicto'
      ELSE 'revisado'
    END AS rec_state
  FROM f360.sales_rec_cases c;

REVOKE ALL ON f360.sales_rec_evidence, f360.sales_rec_decisions, f360.sales_rec_exclusions, f360.sales_rec_analytics_scope,
  f360.sales_rec_cases, f360.sales_rec_cases_state FROM PUBLIC, anon, authenticated;

-- ══ 5 · RPCs (Carolina & Mario only) ═════════════════════════════════════════
CREATE FUNCTION f360.sales_rec_actor_name(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Persona autorizada');
$$;
REVOKE ALL ON FUNCTION f360.sales_rec_actor_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.sales_rec_row(c f360.sales_rec_cases_state) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('target_id', c.target_id, 'target_key', c.target_key, 'woo_order_id', c.woo_order_id, 'created_at', c.created_at,
    'market', c.market, 'currency', c.currency, 'order_total', c.order_total, 'refund_total', c.refund_total, 'woo_status', c.woo_status,
    'payment_method', c.payment_method, 'paid_at', c.paid_at, 'ever_paid', c.ever_paid, 'units', c.units, 'status_class', c.status_class,
    'financial_state', c.financial_state, 'flags', c.flags, 'rec_state', c.rec_state, 'conflict', c.conflict,
    'evidence', CASE WHEN c.evidence_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.evidence_id, 'gateway_result', c.gateway_result,
                  'transaction_ref', c.transaction_ref, 'queried_at', c.evidence_at) END,
    'decision', CASE WHEN c.decision_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.decision_id, 'decision', c.decision,
                  'comment', c.decision_comment, 'by', c.decided_by_name, 'at', c.decided_at, 'duplicate_of', c.duplicate_of) END,
    'excluded', coalesce(c.excluded, false));
$$;
REVOKE ALL ON FUNCTION f360.sales_rec_row(f360.sales_rec_cases_state) FROM PUBLIC, anon, authenticated;

-- Used by f360-woo-sync with the caller's own token BEFORE it reads WooCommerce.
CREATE FUNCTION public.f360_rec_can_view() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN PERFORM f360.require_pii_viewer(); RETURN true; END $$;

CREATE FUNCTION public.f360_rec_list(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_market text DEFAULT NULL, p_woo_status text DEFAULT NULL,
  p_method text DEFAULT NULL, p_flag text DEFAULT NULL, p_state text DEFAULT NULL, p_decision text DEFAULT NULL,
  p_limit int DEFAULT 100, p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); r jsonb; n int;
  t_from timestamptz := CASE WHEN p_from IS NULL THEN NULL ELSE p_from::timestamp AT TIME ZONE 'America/Mexico_City' END;
  t_to   timestamptz := CASE WHEN p_to   IS NULL THEN NULL ELSE (p_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City' END;
BEGIN
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN RAISE EXCEPTION 'La fecha final es anterior a la inicial.'; END IF;
  WITH m AS (
    SELECT c FROM f360.sales_rec_cases_state c
    WHERE (t_from IS NULL OR c.created_at >= t_from) AND (t_to IS NULL OR c.created_at < t_to)
      AND (p_market IS NULL OR c.market = p_market) AND (p_woo_status IS NULL OR c.woo_status = p_woo_status)
      AND (p_method IS NULL OR coalesce(c.payment_method, 'sin_metodo') = p_method)
      AND (p_flag IS NULL OR (p_flag = 'financiera' AND c.has_financial) OR c.flags @> jsonb_build_array(jsonb_build_object('code', p_flag)))
      AND (p_state IS NULL OR c.rec_state = p_state OR (p_state = 'pendientes' AND c.rec_state IN ('pendiente', 'pendiente_discrepancia', 'cambio_despues')))
      AND (p_decision IS NULL OR c.decision = p_decision OR (p_decision = 'sin_decision' AND c.decision IS NULL)))
  SELECT count(*), coalesce((SELECT jsonb_agg(f360.sales_rec_row(x.c) ORDER BY (x.c).created_at DESC, (x.c).woo_order_id DESC) FROM (
           SELECT c FROM m ORDER BY (c).created_at DESC, (c).woo_order_id DESC
           LIMIT least(greatest(coalesce(p_limit, 100), 1), 200) OFFSET greatest(coalesce(p_offset, 0), 0)) x), '[]')
    INTO n, r FROM m;
  RETURN jsonb_build_object('total', n, 'rows', r);
END $$;

CREATE FUNCTION public.f360_rec_summary(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_market text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); r jsonb;
  t_from timestamptz := CASE WHEN p_from IS NULL THEN NULL ELSE p_from::timestamp AT TIME ZONE 'America/Mexico_City' END;
  t_to   timestamptz := CASE WHEN p_to   IS NULL THEN NULL ELSE (p_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City' END;
BEGIN
  WITH m AS (SELECT * FROM f360.sales_rec_cases_state c WHERE (t_from IS NULL OR c.created_at >= t_from) AND (t_to IS NULL OR c.created_at < t_to)
                AND (p_market IS NULL OR c.market = p_market))
  SELECT jsonb_build_object(
    'by_market', coalesce((SELECT jsonb_agg(jsonb_build_object('market', market, 'currency', currency, 'orders', n, 'pending', pend,
                   'financial_open', fin_open, 'not_completed', nc, 'duplicate_candidates', dupc, 'reviewed', rev, 'conflicts', conf,
                   'investigating', inv, 'changed', chg, 'no_issue', ok, 'excluded', exc) ORDER BY market) FROM (
        SELECT market, currency, count(*) n,
          count(*) FILTER (WHERE rec_state IN ('pendiente', 'pendiente_discrepancia', 'cambio_despues')) pend,
          count(*) FILTER (WHERE has_financial AND rec_state IN ('pendiente_discrepancia', 'cambio_despues', 'en_investigacion', 'conflicto')) fin_open,
          count(*) FILTER (WHERE flags @> '[{"code":"NO_CONCRETADO"}]') nc,
          count(*) FILTER (WHERE flags @> '[{"code":"POSIBLE_DUPLICADO"}]' AND decision IS NULL) dupc,
          count(*) FILTER (WHERE rec_state = 'revisado') rev, count(*) FILTER (WHERE rec_state = 'conflicto') conf,
          count(*) FILTER (WHERE rec_state = 'en_investigacion') inv, count(*) FILTER (WHERE rec_state = 'cambio_despues') chg,
          count(*) FILTER (WHERE rec_state = 'sin_novedad') ok, count(*) FILTER (WHERE excluded) exc
        FROM m GROUP BY market, currency) q), '[]'),
    'methods', coalesce((SELECT jsonb_agg(DISTINCT coalesce(payment_method, 'sin_metodo')) FROM m), '[]'),
    'statuses', coalesce((SELECT jsonb_agg(DISTINCT woo_status) FROM m), '[]'),
    'generated_at', now()) INTO r;
  RETURN r;
END $$;

CREATE FUNCTION public.f360_rec_case(p_target uuid, p_order bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); c f360.sales_rec_cases_state;
BEGIN
  SELECT * INTO c FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  IF c.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN f360.sales_rec_row(c) || jsonb_build_object(
    'facts', (SELECT jsonb_build_object('created_via', o.created_via, 'business_origin', o.business_origin, 'items_subtotal', o.items_subtotal,
               'discount_total', o.discount_total, 'shipping_total', o.shipping_total, 'total_tax', o.total_tax, 'woo_modified_at', o.woo_modified_at,
               'completed_at', o.completed_at, 'billing_country', o.billing_country, 'last_captured_via', o.last_captured_via,
               'last_changed_at', o.last_changed_at, 'source', 'Commerce Facts · ' || c.target_key || ' · pedido ' || o.woo_order_id)
              FROM f360.commerce_woo_orders o WHERE o.target_id = p_target AND o.woo_order_id = p_order),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object('product', nm.name, 'sku', l.sku, 'quantity', l.quantity, 'total', l.total) ORDER BY l.woo_line_id), '[]')
              FROM f360.commerce_woo_order_lines l
              CROSS JOIN LATERAL (SELECT coalesce(
                (SELECT p.name FROM f360.woo_product_links wl JOIN f360.products p ON p.id = wl.product_id WHERE wl.woo_product_id = l.woo_product_id LIMIT 1),
                (SELECT p.name FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.sku = l.sku LIMIT 1),
                (SELECT m.woo_product_name FROM f360.legacy_woo_map m WHERE m.woo_product_id = l.woo_product_id AND m.woo_product_name IS NOT NULL LIMIT 1),
                'SKU ' || coalesce(l.sku, '?')) AS name) nm
              WHERE l.target_id = p_target AND l.woo_order_id = p_order),
    'origin', (SELECT jsonb_build_object('channel', f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host),
               'utm_source', a.utm_source, 'utm_campaign', a.utm_campaign, 'device', a.device_type)
               FROM f360.commerce_woo_attribution a WHERE a.target_id = p_target AND a.woo_order_id = p_order),
    'duplicates', (SELECT coalesce(jsonb_agg(f360.sales_rec_row(d) ORDER BY d.woo_order_id), '[]') FROM f360.sales_rec_cases_state d
                   WHERE d.target_id = p_target AND d.woo_order_id = ANY (coalesce(c.duplicate_candidates, '{}'))),
    'evidence_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'source_ref', e.source_ref, 'woo_status', e.woo_status,
               'date_paid', e.date_paid, 'transaction_ref', e.transaction_ref, 'payment_method', e.payment_method, 'order_total', e.order_total,
               'currency', e.currency, 'refund_total', e.refund_total, 'gateway_result', e.gateway_result, 'signals', e.signals, 'result', e.result,
               'hash', e.evidence_hash, 'by', e.queried_by_name, 'at', e.queried_at) ORDER BY e.id DESC), '[]')
               FROM f360.sales_rec_evidence e WHERE e.target_id = p_target AND e.woo_order_id = p_order),
    'decision_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'decision', d.decision, 'comment', d.comment, 'duplicate_of', d.duplicate_of,
               'evidence_id', d.evidence_id, 'woo_status_seen', d.woo_status_seen, 'financial_seen', d.financial_seen, 'supersedes', d.supersedes,
               'by', d.decided_by_name, 'at', d.decided_at) ORDER BY d.id DESC), '[]')
               FROM f360.sales_rec_decisions d WHERE d.target_id = p_target AND d.woo_order_id = p_order),
    'exclusion_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'action', x.action, 'reason', x.reason, 'by', x.decided_by_name,
               'at', x.decided_at) ORDER BY x.id DESC), '[]')
               FROM f360.sales_rec_exclusions x WHERE x.target_id = p_target AND x.woo_order_id = p_order));
END $$;

CREATE FUNCTION public.f360_rec_decide(p_target uuid, p_order bigint, p_decision text, p_comment text DEFAULT NULL,
  p_evidence_id bigint DEFAULT NULL, p_duplicate_of bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); c f360.sales_rec_cases_state; prev bigint; cmt text := nullif(btrim(coalesce(p_comment, '')), '');
  new_id bigint; after f360.sales_rec_cases_state;
BEGIN
  IF p_decision NOT IN ('venta_confirmada', 'no_se_concreto', 'duplicado', 'prueba', 'reembolso', 'requiere_investigacion') THEN
    RAISE EXCEPTION 'Decisión no válida.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('sales_rec:' || p_target || ':' || p_order, 0));
  SELECT * INTO c FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  IF c.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  prev := c.decision_id;
  IF p_decision IN ('duplicado', 'prueba', 'requiere_investigacion') AND (cmt IS NULL OR length(cmt) < 5) THEN
    RAISE EXCEPTION 'Escribe un comentario (por qué es %).', replace(p_decision, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  IF prev IS NOT NULL AND (cmt IS NULL OR length(cmt) < 5) THEN
    RAISE EXCEPTION 'Para corregir una decisión anterior escribe el motivo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision = 'duplicado' THEN
    IF p_duplicate_of IS NULL OR p_duplicate_of = p_order
       OR NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_duplicate_of) THEN
      RAISE EXCEPTION 'Indica de qué pedido es duplicado (otro pedido de la misma tienda).' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF p_duplicate_of IS NOT NULL THEN
    RAISE EXCEPTION 'Solo un duplicado lleva "duplicado de".' USING ERRCODE = 'check_violation';
  END IF;
  IF p_evidence_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.sales_rec_evidence WHERE id = p_evidence_id AND target_id = p_target AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Esa evidencia no es de este pedido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision IN ('venta_confirmada', 'reembolso') AND p_evidence_id IS NULL THEN
    RAISE EXCEPTION 'Consulta la evidencia de WooCommerce antes de confirmar (botón "Consultar evidencia").' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO f360.sales_rec_decisions (target_id, woo_order_id, decision, duplicate_of, comment, evidence_id, woo_status_seen, facts_hash_seen,
                                        financial_seen, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, p_decision, p_duplicate_of, cmt, p_evidence_id, c.woo_status, c.economics_hash, c.financial_state, prev, uid,
          f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  SELECT * INTO after FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'supersedes', prev, 'rec_state', after.rec_state, 'conflict', after.conflict,
                            'financial_state', after.financial_state);
END $$;

CREATE FUNCTION public.f360_rec_set_analytics(p_target uuid, p_order bigint, p_exclude boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); cur f360.sales_rec_exclusions; rsn text := btrim(coalesce(p_reason, '')); new_id bigint;
BEGIN
  IF p_exclude IS NULL THEN RAISE EXCEPTION 'Indica si se excluye o se vuelve a incluir.'; END IF;
  IF length(rsn) < 5 THEN RAISE EXCEPTION 'Escribe el motivo (mínimo 5 letras).' USING ERRCODE = 'check_violation'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('sales_rec_x:' || p_target || ':' || p_order, 0));
  IF NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT * INTO cur FROM f360.sales_rec_exclusions WHERE target_id = p_target AND woo_order_id = p_order ORDER BY id DESC LIMIT 1;
  IF p_exclude AND cur.action = 'exclude' THEN RAISE EXCEPTION 'Ese pedido ya está excluido de las métricas.'; END IF;
  IF NOT p_exclude AND coalesce(cur.action, 'include') = 'include' THEN RAISE EXCEPTION 'Ese pedido ya está incluido en las métricas.'; END IF;
  INSERT INTO f360.sales_rec_exclusions (target_id, woo_order_id, action, reason, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, CASE WHEN p_exclude THEN 'exclude' ELSE 'include' END, rsn, cur.id, uid, f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'excluded', p_exclude);
END $$;

-- Service role only (f360-woo-sync): stores the minimal snapshot it read from WooCommerce for a verified viewer.
CREATE FUNCTION public.f360_rec_evidence_record(p_actor uuid, p_target_key text, p_order bigint, p_ev jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE tid uuid; tx text := nullif(btrim(coalesce(p_ev->>'transaction_ref', '')), ''); sigs text[]; res text; gw text := p_ev->>'gateway_result';
  snap jsonb; h text; new_id bigint; digits text;
BEGIN
  IF p_actor IS NULL OR NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = p_actor) THEN
    RAISE EXCEPTION 'Solo las personas autorizadas pueden consultar evidencia.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT id INTO tid FROM f360.sales_targets WHERE key = p_target_key;
  IF tid IS NULL OR NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = tid AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found';
  END IF;
  IF gw IS NULL OR gw NOT IN ('approved', 'rejected', 'pending', 'refunded', 'transaction_only', 'no_evidence', 'order_missing') THEN
    RAISE EXCEPTION 'Resultado de pasarela no válido.';
  END IF;
  -- Never store anything that looks like a card number (13–19 digits); a gateway transaction id is never one.
  digits := regexp_replace(coalesce(tx, ''), '[\s-]', '', 'g');
  IF tx IS NOT NULL AND (digits ~ '^\d{13,19}$' OR length(tx) > 100) THEN tx := NULL; sigs := ARRAY['tx_redacted']; END IF;
  sigs := coalesce(sigs, '{}') || coalesce((SELECT array_agg(s) FROM jsonb_array_elements_text(coalesce(p_ev->'signals', '[]')) s
            WHERE s IN ('tx_present', 'tx_field', 'tx_meta_mercadopago', 'tx_meta_other', 'date_paid', 'note_approved', 'note_rejected', 'note_pending', 'note_refunded', 'refund_records',
                        'status_paid', 'status_unpaid', 'no_gateway_notes')), '{}');
  res := CASE gw
    WHEN 'approved' THEN 'La pasarela registró el pago como aprobado en WooCommerce'
    WHEN 'rejected' THEN 'La pasarela registró el pago como rechazado en WooCommerce'
    WHEN 'pending' THEN 'La pasarela dejó el pago pendiente en WooCommerce'
    WHEN 'refunded' THEN 'Hay reembolso registrado en WooCommerce'
    WHEN 'order_missing' THEN 'WooCommerce ya no tiene este pedido (no existe o fue borrado)'
    WHEN 'transaction_only' THEN 'WooCommerce tiene número de transacción pero no nota de la pasarela'
    ELSE 'WooCommerce no tiene número de transacción ni nota de la pasarela' END
    || CASE WHEN tx IS NOT NULL THEN ' · transacción ' || tx ELSE '' END || '.';
  snap := jsonb_build_object('source', 'woo_rest_order', 'source_ref', p_target_key || ':order/' || p_order, 'woo_status', p_ev->>'woo_status',
            'date_paid', p_ev->>'date_paid', 'transaction_ref', tx, 'payment_method', p_ev->>'payment_method', 'order_total', p_ev->>'order_total',
            'currency', p_ev->>'currency', 'refund_total', coalesce(p_ev->>'refund_total', '0'), 'gateway_result', gw, 'signals', to_jsonb(sigs),
            'queried_by', p_actor, 'queried_at', now());
  h := encode(extensions.digest(snap::text, 'sha256'), 'hex');
  INSERT INTO f360.sales_rec_evidence (target_id, woo_order_id, source, source_ref, woo_status, date_paid, transaction_ref, payment_method, order_total,
    currency, refund_total, gateway_result, signals, result, evidence_hash, queried_by, queried_by_name, queried_at)
  VALUES (tid, p_order, 'woo_rest_order', p_target_key || ':order/' || p_order, coalesce(p_ev->>'woo_status', '?'), (p_ev->>'date_paid')::timestamptz, tx,
    nullif(p_ev->>'payment_method', ''), (p_ev->>'order_total')::numeric, p_ev->>'currency', coalesce((p_ev->>'refund_total')::numeric, 0), gw, sigs, res,
    h, p_actor, f360.sales_rec_actor_name(p_actor), (snap->>'queried_at')::timestamptz)
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('id', new_id, 'hash', h, 'result', res, 'transaction_ref', tx, 'gateway_result', gw, 'signals', to_jsonb(sigs));
END $$;

REVOKE ALL ON FUNCTION public.f360_rec_can_view(), public.f360_rec_list(date, date, text, text, text, text, text, text, int, int),
  public.f360_rec_summary(date, date, text), public.f360_rec_case(uuid, bigint), public.f360_rec_decide(uuid, bigint, text, text, bigint, bigint),
  public.f360_rec_set_analytics(uuid, bigint, boolean, text), public.f360_rec_evidence_record(uuid, text, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_rec_can_view(), public.f360_rec_list(date, date, text, text, text, text, text, text, int, int),
  public.f360_rec_summary(date, date, text), public.f360_rec_case(uuid, bigint), public.f360_rec_decide(uuid, bigint, text, text, bigint, bigint),
  public.f360_rec_set_analytics(uuid, bigint, boolean, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_rec_evidence_record(uuid, text, bigint, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.f360_rec_evidence_record(uuid, text, bigint, jsonb) TO service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261022000100', 'f360_sales_reconciliation', '{}');

-- ===== 20261022000200_f360_growth_exclusions =====
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261022000200', 'f360_growth_exclusions', '{}');

-- ===== 20261022000300_f360_sales_rec_wording =====
-- Fuxia 360 · Conciliación — wording only (Mario 2026-10-10 #13: a retry is a CANDIDATE, never assumed to be the same purchase;
-- statuses in Spanish). Same columns, same rules; replaces the view text of 20261022000100. STAGING.
-- Rollback: supabase/rollbacks/20261022000300_f360_sales_rec_wording.down.sql (restores the 20261022000100 view text).
CREATE OR REPLACE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at, o.market, o.currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
), enriched AS (
  SELECT b.*, ev.id AS evidence_id, ev.gateway_result, ev.transaction_ref, ev.queried_at AS evidence_at, ev.woo_status AS evidence_woo_status,
         d.id AS decision_id, d.decision, d.comment AS decision_comment, d.decided_by_name, d.decided_at, d.duplicate_of,
         d.woo_status_seen, d.facts_hash_seen,
         x.excluded, x.reason AS exclusion_reason,
         dup.candidates AS duplicate_candidates, rtr.retry_paid_order
  FROM base b
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_evidence e WHERE e.target_id = b.target_id AND e.woo_order_id = b.woo_order_id ORDER BY e.id DESC LIMIT 1) ev ON true
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_decisions d WHERE d.target_id = b.target_id AND d.woo_order_id = b.woo_order_id ORDER BY d.id DESC LIMIT 1) d ON true
  LEFT JOIN f360.sales_rec_analytics_scope x ON x.target_id = b.target_id AND x.woo_order_id = b.woo_order_id
  LEFT JOIN LATERAL (
    SELECT array_agg(b2.woo_order_id ORDER BY b2.woo_order_id) AS candidates FROM base b2
    WHERE b2.target_id = b.target_id AND b2.woo_order_id <> b.woo_order_id AND b2.market = b.market AND b2.currency = b.currency
      AND b2.order_total = b.order_total AND b.order_total > 0
      AND b2.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND abs(extract(epoch FROM b2.created_at - b.created_at)) <= 48 * 3600
      AND b.ever_paid AND b2.ever_paid                                  -- a duplicate matters only when both were paid
      AND (b.woo_customer_id IS NULL OR b2.woo_customer_id IS NULL OR b.woo_customer_id = b2.woo_customer_id)) dup ON true
  LEFT JOIN LATERAL (                                                   -- unpaid attempt followed by a paid one = retry, not duplicate
    SELECT min(b3.woo_order_id) AS retry_paid_order FROM base b3
    WHERE NOT b.ever_paid AND b3.ever_paid AND b3.target_id = b.target_id AND b3.market = b.market AND b3.currency = b.currency
      AND b3.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND b3.created_at > b.created_at AND b3.created_at - b.created_at <= interval '48 hours'
      AND (b.woo_customer_id IS NULL OR b3.woo_customer_id IS NULL OR b.woo_customer_id = b3.woo_customer_id)) rtr ON true
), fin AS (
  SELECT e.*,
    CASE
      WHEN NOT e.ever_paid AND e.gateway_result = 'approved' THEN 'CONTRADICTORIA'
      WHEN NOT e.ever_paid THEN 'SIN_COBRO'
      WHEN e.gateway_result = 'order_missing' THEN 'NO_EXISTE_EN_WOO'
      WHEN e.woo_status = 'refunded' OR (e.refund_total > 0 AND e.refund_total >= e.order_total) THEN 'REEMBOLSADO'
      WHEN e.refund_total > 0 THEN 'REEMBOLSO_PARCIAL'
      WHEN e.gateway_result = 'rejected' THEN 'CONTRADICTORIA'
      WHEN e.evidence_id IS NOT NULL AND e.transaction_ref IS NOT NULL AND e.gateway_result IN ('approved', 'transaction_only') THEN 'COBRO_CON_TRANSACCION'
      WHEN e.evidence_id IS NOT NULL THEN 'PAGO_SIN_TRANSACCION'
      ELSE 'PAGO_REGISTRADO_WOO'
    END AS financial_state
  FROM enriched e
), flagged AS (
  SELECT f.*, coalesce((SELECT jsonb_agg(fl) FROM (
    SELECT jsonb_build_object('code', 'NO_CONCRETADO', 'kind', 'no_concretado',
             'why', 'Nunca se registró pago. Estado en WooCommerce: ' || f.woo_status || '.') fl WHERE NOT f.ever_paid
    UNION ALL
    SELECT jsonb_build_object('code', 'REINTENTO_PAGADO', 'kind', 'info', 'paid_order', f.retry_paid_order,
             'why', 'Posible reintento: el pedido #' || f.retry_paid_order || ' se pagó con los mismos productos y el mismo total en menos de 48 h. ' ||
                    'No se da por hecho que sea la misma compra: confírmalo con la evidencia (misma clienta) antes de clasificarlo.')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está ' || CASE f.woo_status WHEN 'cancelled' THEN 'cancelado' WHEN 'failed' THEN 'fallido' ELSE f.woo_status END || ', sin reembolso registrado.')
      WHERE f.ever_paid AND f.woo_status IN ('cancelled', 'failed') AND f.refund_total = 0
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGADO_SIN_EVIDENCIA', 'kind', 'financiera', 'why',
             CASE WHEN f.paid_at IS NULL THEN 'Woo lo marca pagado (' || f.woo_status || ') pero no tiene fecha de pago.'
                  WHEN f.payment_method IS NULL THEN 'Pagado sin método de pago registrado.'
                  ELSE 'Consultado en WooCommerce: pagado sin número de transacción de la pasarela.' END)
      WHERE f.ever_paid AND f.woo_status IN ('processing', 'completed', 'on-hold')
        AND (f.paid_at IS NULL OR f.payment_method IS NULL OR f.financial_state = 'PAGO_SIN_TRANSACCION')
    UNION ALL
    SELECT jsonb_build_object('code', 'EVIDENCIA_CONTRADICE', 'kind', 'financiera', 'why',
             CASE WHEN f.ever_paid THEN 'Woo lo tiene como pagado pero la nota de la pasarela dice rechazado.'
                  ELSE 'La nota de la pasarela dice aprobado pero Woo no registró el pago.' END)
      WHERE f.financial_state = 'CONTRADICTORIA'
    UNION ALL
    SELECT jsonb_build_object('code', 'NO_EXISTE_EN_WOO', 'kind', CASE WHEN f.ever_paid THEN 'financiera' ELSE 'info' END,
             'why', 'Al consultarlo (' || to_char(f.evidence_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') ||
                    ') WooCommerce ya no tenía este pedido' || CASE WHEN f.ever_paid THEN ', y Fuxia 360 lo capturó con pago registrado.' ELSE '.' END)
      WHERE f.gateway_result = 'order_missing'
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_PRUEBA', 'kind', 'revision', 'why',
             CASE WHEN f.payment_method ~* '(prueba|test|sandbox)' THEN 'Método de pago de prueba: ' || f.payment_method || '.'
                  ELSE 'Pedido pagado por 0.' END)
      WHERE f.payment_method ~* '(prueba|test|sandbox)' OR (f.ever_paid AND f.order_total = 0)
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'kind', 'revision', 'candidates', to_jsonb(f.duplicate_candidates),
             'why', 'Dos pedidos PAGADOS con el mismo total y los mismos productos, misma clienta (o sin cuenta), en menos de 48 h: #' ||
                    array_to_string(f.duplicate_candidates, ', #') || '. Es un candidato: confirma o descarta.')
      WHERE f.duplicate_candidates IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'REEMBOLSO', 'kind', 'reembolso',
             'why', 'Reembolso registrado en WooCommerce por ' || f.refund_total || ' ' || f.currency || '.')
      WHERE f.refund_total > 0 OR f.woo_status = 'refunded'
  ) q), '[]'::jsonb) AS flags
  FROM fin f
)
SELECT g.*,
  EXISTS (SELECT 1 FROM jsonb_array_elements(g.flags) z WHERE z->>'kind' = 'financiera') AS has_financial,
  CASE
    WHEN g.decision IS NULL THEN NULL
    WHEN g.decision = 'venta_confirmada' AND g.financial_state IN ('SIN_COBRO', 'CONTRADICTORIA', 'REEMBOLSADO', 'PAGO_SIN_TRANSACCION', 'NO_EXISTE_EN_WOO')
      THEN 'Confirmada como venta, pero la evidencia financiera dice: ' || g.financial_state || '. No cuenta como cobro.'
    WHEN g.decision = 'no_se_concreto' AND g.financial_state IN ('COBRO_CON_TRANSACCION', 'PAGO_REGISTRADO_WOO')
      THEN 'Marcada "no se concretó", pero hay pago registrado y ningún reembolso.'
    WHEN g.decision IN ('duplicado', 'prueba') AND g.ever_paid AND g.refund_total = 0 AND g.woo_status NOT IN ('cancelled', 'failed', 'refunded')
      THEN 'Marcada "' || g.decision || '", pero tiene pago registrado y ningún reembolso.'
    WHEN g.decision = 'reembolso' AND g.refund_total = 0 AND g.woo_status <> 'refunded'
      THEN 'Marcada "reembolso", pero WooCommerce no tiene ningún reembolso registrado.'
  END AS conflict
FROM flagged g;


INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261022000300', 'f360_sales_rec_wording', '{}');

-- ===== 20261022000400_f360_currency_corrections =====
-- Fuxia 360 · Corrección comercial auditada de moneda/mercado (Mario 2026-10-10: #2095 es COP 405,000, no USD). STAGING. ADDITIVE.
-- WooCommerce and Commerce Facts keep the SOURCE record (USD 405,000, market ROW, cancelled). A correction is a separate,
-- append-only event (who, when, reason, server-captured evidence; revert = new event). No FX conversion: the amount is read as
-- the corrected currency. The payment state never changes (a correction never makes an order "paid").
-- Consumers that follow the correction (reporting market/currency): Growth War Room (growth_market_block, growth_adjustments via
-- f360.commerce_orders_reporting) and Conciliación (sales_rec_cases). Commerce Facts (técnico), Medición/measurement_sales and the
-- executive dashboard keep showing the source until their own pase (documented).
-- Alert: f360.currency_suspicion() flags orders whose currency disagrees with billing country (MX/CO), a single-currency gateway
-- (ePayco = COP, Mercado Pago México = MXN; PayPal is NOT assumed: staging4 has COP orders completed with PayPal) or price range
-- ("Moneda sospechosa" in Conciliación). It never corrects anything by itself.
-- Depends on 20261021000100, 20261022000100/0200/0300.
-- Rollback: supabase/rollbacks/20261022000400_f360_currency_corrections.down.sql

CREATE TABLE f360.commerce_currency_corrections (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id       bigint NOT NULL,
  action             text NOT NULL CHECK (action IN ('correct', 'revert')),
  original_currency  text NOT NULL,
  original_market    text NOT NULL,
  corrected_currency text CHECK (corrected_currency IN ('MXN', 'COP', 'USD')),
  corrected_market   text CHECK (corrected_market IN ('MX', 'CO', 'ROW')),
  reason             text NOT NULL CHECK (length(btrim(reason)) BETWEEN 10 AND 1000),
  evidence           jsonb NOT NULL,                 -- captured by the server from Commerce Facts, never sent by the client
  supersedes         bigint UNIQUE REFERENCES f360.commerce_currency_corrections(id),
  decided_by         uuid NOT NULL,
  decided_by_name    text NOT NULL,
  decided_at         timestamptz NOT NULL DEFAULT now(),
  CHECK ((action = 'correct') = (corrected_currency IS NOT NULL AND corrected_market IS NOT NULL)),
  CHECK (corrected_currency IS NULL OR (corrected_currency, corrected_market) IN (('MXN', 'MX'), ('COP', 'CO'), ('USD', 'ROW')))
);
CREATE INDEX commerce_currency_corrections_order_idx ON f360.commerce_currency_corrections (target_id, woo_order_id, id DESC);
ALTER TABLE f360.commerce_currency_corrections ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER commerce_currency_corrections_append_only BEFORE UPDATE OR DELETE ON f360.commerce_currency_corrections
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE VIEW f360.commerce_currency_scope AS
  SELECT DISTINCT ON (target_id, woo_order_id) id, target_id, woo_order_id, action = 'correct' AS active, original_currency, original_market,
         corrected_currency, corrected_market, reason, decided_by_name, decided_at
  FROM f360.commerce_currency_corrections ORDER BY target_id, woo_order_id, id DESC;

-- Why an order's currency looks wrong (NULL = nothing suspicious). Billing country is only used for MX / CO.
CREATE FUNCTION f360.currency_suspicion(p_target uuid, p_order bigint) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT nullif(concat_ws(' ',
    CASE WHEN o.billing_country IN ('MX', 'CO') AND o.billing_country <> o.market
         THEN format('Factura en %s pero la moneda es %s (mercado %s).', o.billing_country, o.currency, o.market) END,
    CASE WHEN o.payment_method = 'epayco' AND o.currency <> 'COP' THEN format('ePayco cobra en COP pero el pedido está en %s.', o.currency)
         WHEN o.payment_method LIKE 'woo-mercado-pago%' AND o.currency <> 'MXN' THEN format('Mercado Pago (México) cobra en MXN pero el pedido está en %s.', o.currency) END,
    CASE WHEN o.currency = 'USD' AND l.max_unit > 5000 THEN format('Precio por par de %s USD: fuera de rango para dólares.', round(l.max_unit))
         WHEN o.currency = 'MXN' AND l.max_unit > 60000 THEN format('Precio por par de %s MXN: fuera de rango para pesos mexicanos.', round(l.max_unit))
         WHEN o.currency = 'COP' AND l.max_unit > 0 AND l.max_unit < 50000 THEN format('Precio por par de %s COP: fuera de rango para pesos colombianos.', round(l.max_unit)) END), '')
  FROM f360.commerce_woo_orders o
  LEFT JOIN LATERAL (SELECT max(CASE WHEN quantity > 0 THEN subtotal / quantity END) AS max_unit FROM f360.commerce_woo_order_lines x
                     WHERE x.target_id = o.target_id AND x.woo_order_id = o.woo_order_id) l ON true
  WHERE o.target_id = p_target AND o.woo_order_id = p_order;
$$;
REVOKE ALL ON FUNCTION f360.currency_suspicion(uuid, bigint) FROM PUBLIC, anon, authenticated;

-- Commerce Facts + the active correction (reporting fields only; the source fields are unchanged).
CREATE VIEW f360.commerce_orders_reporting AS
  SELECT co.*, coalesce(cc.corrected_market, co.market) AS market_reporting, coalesce(cc.corrected_currency, co.currency_original) AS currency_reporting,
         (cc.id IS NOT NULL) AS currency_corrected
  FROM f360.commerce_orders co
  LEFT JOIN f360.commerce_currency_scope cc ON cc.target_id = co.target_id AND cc.woo_order_id = co.woo_order_id AND cc.active;

REVOKE ALL ON f360.commerce_currency_corrections, f360.commerce_currency_scope, f360.commerce_orders_reporting FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at,
         coalesce(cc.corrected_market, o.market) AS market, coalesce(cc.corrected_currency, o.currency) AS currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
  LEFT JOIN f360.commerce_currency_scope cc ON cc.target_id = o.target_id AND cc.woo_order_id = o.woo_order_id AND cc.active
), enriched AS (
  SELECT b.*, ev.id AS evidence_id, ev.gateway_result, ev.transaction_ref, ev.queried_at AS evidence_at, ev.woo_status AS evidence_woo_status,
         d.id AS decision_id, d.decision, d.comment AS decision_comment, d.decided_by_name, d.decided_at, d.duplicate_of,
         d.woo_status_seen, d.facts_hash_seen,
         x.excluded, x.reason AS exclusion_reason,
         dup.candidates AS duplicate_candidates, rtr.retry_paid_order
  FROM base b
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_evidence e WHERE e.target_id = b.target_id AND e.woo_order_id = b.woo_order_id ORDER BY e.id DESC LIMIT 1) ev ON true
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_decisions d WHERE d.target_id = b.target_id AND d.woo_order_id = b.woo_order_id ORDER BY d.id DESC LIMIT 1) d ON true
  LEFT JOIN f360.sales_rec_analytics_scope x ON x.target_id = b.target_id AND x.woo_order_id = b.woo_order_id
  LEFT JOIN LATERAL (
    SELECT array_agg(b2.woo_order_id ORDER BY b2.woo_order_id) AS candidates FROM base b2
    WHERE b2.target_id = b.target_id AND b2.woo_order_id <> b.woo_order_id AND b2.market = b.market AND b2.currency = b.currency
      AND b2.order_total = b.order_total AND b.order_total > 0
      AND b2.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND abs(extract(epoch FROM b2.created_at - b.created_at)) <= 48 * 3600
      AND b.ever_paid AND b2.ever_paid                                  -- a duplicate matters only when both were paid
      AND (b.woo_customer_id IS NULL OR b2.woo_customer_id IS NULL OR b.woo_customer_id = b2.woo_customer_id)) dup ON true
  LEFT JOIN LATERAL (                                                   -- unpaid attempt followed by a paid one = retry, not duplicate
    SELECT min(b3.woo_order_id) AS retry_paid_order FROM base b3
    WHERE NOT b.ever_paid AND b3.ever_paid AND b3.target_id = b.target_id AND b3.market = b.market AND b3.currency = b.currency
      AND b3.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND b3.created_at > b.created_at AND b3.created_at - b.created_at <= interval '48 hours'
      AND (b.woo_customer_id IS NULL OR b3.woo_customer_id IS NULL OR b.woo_customer_id = b3.woo_customer_id)) rtr ON true
), fin AS (
  SELECT e.*,
    CASE
      WHEN NOT e.ever_paid AND e.gateway_result = 'approved' THEN 'CONTRADICTORIA'
      WHEN NOT e.ever_paid THEN 'SIN_COBRO'
      WHEN e.gateway_result = 'order_missing' THEN 'NO_EXISTE_EN_WOO'
      WHEN e.woo_status = 'refunded' OR (e.refund_total > 0 AND e.refund_total >= e.order_total) THEN 'REEMBOLSADO'
      WHEN e.refund_total > 0 THEN 'REEMBOLSO_PARCIAL'
      WHEN e.gateway_result = 'rejected' THEN 'CONTRADICTORIA'
      WHEN e.evidence_id IS NOT NULL AND e.transaction_ref IS NOT NULL AND e.gateway_result IN ('approved', 'transaction_only') THEN 'COBRO_CON_TRANSACCION'
      WHEN e.evidence_id IS NOT NULL THEN 'PAGO_SIN_TRANSACCION'
      ELSE 'PAGO_REGISTRADO_WOO'
    END AS financial_state
  FROM enriched e
), flagged AS (
  SELECT f.*, coalesce((SELECT jsonb_agg(fl) FROM (
    SELECT jsonb_build_object('code', 'NO_CONCRETADO', 'kind', 'no_concretado',
             'why', 'Nunca se registró pago. Estado en WooCommerce: ' || f.woo_status || '.') fl WHERE NOT f.ever_paid
    UNION ALL
    SELECT jsonb_build_object('code', 'REINTENTO_PAGADO', 'kind', 'info', 'paid_order', f.retry_paid_order,
             'why', 'Posible reintento: el pedido #' || f.retry_paid_order || ' se pagó con los mismos productos y el mismo total en menos de 48 h. ' ||
                    'No se da por hecho que sea la misma compra: confírmalo con la evidencia (misma clienta) antes de clasificarlo.')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está ' || CASE f.woo_status WHEN 'cancelled' THEN 'cancelado' WHEN 'failed' THEN 'fallido' ELSE f.woo_status END || ', sin reembolso registrado.')
      WHERE f.ever_paid AND f.woo_status IN ('cancelled', 'failed') AND f.refund_total = 0
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGADO_SIN_EVIDENCIA', 'kind', 'financiera', 'why',
             CASE WHEN f.paid_at IS NULL THEN 'Woo lo marca pagado (' || f.woo_status || ') pero no tiene fecha de pago.'
                  WHEN f.payment_method IS NULL THEN 'Pagado sin método de pago registrado.'
                  ELSE 'Consultado en WooCommerce: pagado sin número de transacción de la pasarela.' END)
      WHERE f.ever_paid AND f.woo_status IN ('processing', 'completed', 'on-hold')
        AND (f.paid_at IS NULL OR f.payment_method IS NULL OR f.financial_state = 'PAGO_SIN_TRANSACCION')
    UNION ALL
    SELECT jsonb_build_object('code', 'EVIDENCIA_CONTRADICE', 'kind', 'financiera', 'why',
             CASE WHEN f.ever_paid THEN 'Woo lo tiene como pagado pero la nota de la pasarela dice rechazado.'
                  ELSE 'La nota de la pasarela dice aprobado pero Woo no registró el pago.' END)
      WHERE f.financial_state = 'CONTRADICTORIA'
    UNION ALL
    SELECT jsonb_build_object('code', 'NO_EXISTE_EN_WOO', 'kind', CASE WHEN f.ever_paid THEN 'financiera' ELSE 'info' END,
             'why', 'Al consultarlo (' || to_char(f.evidence_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') ||
                    ') WooCommerce ya no tenía este pedido' || CASE WHEN f.ever_paid THEN ', y Fuxia 360 lo capturó con pago registrado.' ELSE '.' END)
      WHERE f.gateway_result = 'order_missing'
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_PRUEBA', 'kind', 'revision', 'why',
             CASE WHEN f.payment_method ~* '(prueba|test|sandbox)' THEN 'Método de pago de prueba: ' || f.payment_method || '.'
                  ELSE 'Pedido pagado por 0.' END)
      WHERE f.payment_method ~* '(prueba|test|sandbox)' OR (f.ever_paid AND f.order_total = 0)
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'kind', 'revision', 'candidates', to_jsonb(f.duplicate_candidates),
             'why', 'Dos pedidos PAGADOS con el mismo total y los mismos productos, misma clienta (o sin cuenta), en menos de 48 h: #' ||
                    array_to_string(f.duplicate_candidates, ', #') || '. Es un candidato: confirma o descarta.')
      WHERE f.duplicate_candidates IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_CORREGIDA', 'kind', 'info', 'why',
             'WooCommerce registra ' || cc.original_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (mercado ' || cc.original_market ||
             '). Corrección comercial: ' || cc.corrected_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (' || cc.corrected_market ||
             ') · ' || cc.decided_by_name || ': "' || cc.reason || '". Sin conversión cambiaria; no cambia el estado de pago.')
      FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_SOSPECHOSA', 'kind', 'revision', 'why', sus.why || ' Confírmalo y, si aplica, registra la corrección de moneda.')
      FROM (SELECT f360.currency_suspicion(f.target_id, f.woo_order_id) AS why) sus
      WHERE sus.why IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active)
    UNION ALL
    SELECT jsonb_build_object('code', 'REEMBOLSO', 'kind', 'reembolso',
             'why', 'Reembolso registrado en WooCommerce por ' || f.refund_total || ' ' || f.currency || '.')
      WHERE f.refund_total > 0 OR f.woo_status = 'refunded'
  ) q), '[]'::jsonb) AS flags
  FROM fin f
)
SELECT g.*,
  EXISTS (SELECT 1 FROM jsonb_array_elements(g.flags) z WHERE z->>'kind' = 'financiera') AS has_financial,
  CASE
    WHEN g.decision IS NULL THEN NULL
    WHEN g.decision = 'venta_confirmada' AND g.financial_state IN ('SIN_COBRO', 'CONTRADICTORIA', 'REEMBOLSADO', 'PAGO_SIN_TRANSACCION', 'NO_EXISTE_EN_WOO')
      THEN 'Confirmada como venta, pero la evidencia financiera dice: ' || g.financial_state || '. No cuenta como cobro.'
    WHEN g.decision = 'no_se_concreto' AND g.financial_state IN ('COBRO_CON_TRANSACCION', 'PAGO_REGISTRADO_WOO')
      THEN 'Marcada "no se concretó", pero hay pago registrado y ningún reembolso.'
    WHEN g.decision IN ('duplicado', 'prueba') AND g.ever_paid AND g.refund_total = 0 AND g.woo_status NOT IN ('cancelled', 'failed', 'refunded')
      THEN 'Marcada "' || g.decision || '", pero tiene pago registrado y ningún reembolso.'
    WHEN g.decision = 'reembolso' AND g.refund_total = 0 AND g.woo_status <> 'refunded'
      THEN 'Marcada "reembolso", pero WooCommerce no tiene ningún reembolso registrado.'
  END AS conflict
FROM flagged g;


CREATE OR REPLACE FUNCTION f360.sales_rec_row(c f360.sales_rec_cases_state) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('target_id', c.target_id, 'target_key', c.target_key, 'woo_order_id', c.woo_order_id, 'created_at', c.created_at,
    'market', c.market, 'currency', c.currency, 'order_total', c.order_total, 'refund_total', c.refund_total, 'woo_status', c.woo_status,
    'payment_method', c.payment_method, 'paid_at', c.paid_at, 'ever_paid', c.ever_paid, 'units', c.units, 'status_class', c.status_class,
    'financial_state', c.financial_state, 'flags', c.flags, 'rec_state', c.rec_state, 'conflict', c.conflict,
    'evidence', CASE WHEN c.evidence_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.evidence_id, 'gateway_result', c.gateway_result,
                  'transaction_ref', c.transaction_ref, 'queried_at', c.evidence_at) END,
    'decision', CASE WHEN c.decision_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.decision_id, 'decision', c.decision,
                  'comment', c.decision_comment, 'by', c.decided_by_name, 'at', c.decided_at, 'duplicate_of', c.duplicate_of) END,
    'excluded', coalesce(c.excluded, false),
    'currency_correction', (SELECT jsonb_build_object('id', cc.id, 'woo_currency', cc.original_currency, 'woo_market', cc.original_market,
        'currency', cc.corrected_currency, 'market', cc.corrected_market, 'reason', cc.reason, 'by', cc.decided_by_name, 'at', cc.decided_at)
      FROM f360.commerce_currency_scope cc WHERE cc.target_id = c.target_id AND cc.woo_order_id = c.woo_order_id AND cc.active));
$$;


-- Carolina & Mario only. Evidence is captured here from Commerce Facts (never from the client).
CREATE FUNCTION public.f360_rec_correct_currency(p_target uuid, p_order bigint, p_currency text, p_reason text, p_revert boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); o f360.commerce_woo_orders; cur f360.commerce_currency_scope; rsn text := btrim(coalesce(p_reason, ''));
  mkt text := CASE p_currency WHEN 'MXN' THEN 'MX' WHEN 'COP' THEN 'CO' WHEN 'USD' THEN 'ROW' END; new_id bigint; ev jsonb;
BEGIN
  IF length(rsn) < 10 THEN RAISE EXCEPTION 'Escribe el motivo y la evidencia (mínimo 10 letras).' USING ERRCODE = 'check_violation'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('currency:' || p_target || ':' || p_order, 0));
  SELECT * INTO o FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_order;
  IF o.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  SELECT * INTO cur FROM f360.commerce_currency_scope WHERE target_id = p_target AND woo_order_id = p_order;
  IF coalesce(p_revert, false) THEN
    IF NOT coalesce(cur.active, false) THEN RAISE EXCEPTION 'Ese pedido no tiene una corrección de moneda activa.' USING ERRCODE = 'check_violation'; END IF;
  ELSE
    IF mkt IS NULL THEN RAISE EXCEPTION 'Moneda no válida (MXN, COP o USD).' USING ERRCODE = 'check_violation'; END IF;
    IF p_currency = o.currency AND NOT coalesce(cur.active, false) THEN RAISE EXCEPTION 'El pedido ya está en %: no hay nada que corregir.', p_currency USING ERRCODE = 'check_violation'; END IF;
    IF coalesce(cur.active, false) AND cur.corrected_currency = p_currency THEN RAISE EXCEPTION 'Ya está corregido a %.', p_currency USING ERRCODE = 'check_violation'; END IF;
  END IF;
  ev := jsonb_build_object('woo_currency', o.currency, 'woo_market', o.market, 'market_source', o.market_source, 'billing_country', o.billing_country,
          'payment_method', o.payment_method, 'order_total', o.order_total, 'woo_status', o.woo_status, 'ever_paid', o.ever_paid,
          'economics_hash', o.economics_hash, 'suspicion', f360.currency_suspicion(p_target, p_order),
          'max_unit_price', (SELECT max(CASE WHEN quantity > 0 THEN subtotal / quantity END) FROM f360.commerce_woo_order_lines x WHERE x.target_id = p_target AND x.woo_order_id = p_order));
  INSERT INTO f360.commerce_currency_corrections (target_id, woo_order_id, action, original_currency, original_market, corrected_currency, corrected_market,
                                                  reason, evidence, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, CASE WHEN p_revert THEN 'revert' ELSE 'correct' END, o.currency, o.market,
          CASE WHEN p_revert THEN NULL ELSE p_currency END, CASE WHEN p_revert THEN NULL ELSE mkt END, rsn, ev, cur.id, uid, f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'active', NOT coalesce(p_revert, false), 'woo_currency', o.currency, 'woo_market', o.market,
                            'currency', CASE WHEN p_revert THEN o.currency ELSE p_currency END, 'market', CASE WHEN p_revert THEN o.market ELSE mkt END);
END $$;
REVOKE ALL ON FUNCTION public.f360_rec_correct_currency(uuid, bigint, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_rec_correct_currency(uuid, bigint, text, text, boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION f360.growth_market_block(p_market text, p_from timestamptz, p_to timestamptz, p_pfrom timestamptz, p_pto timestamptz) RETURNS jsonb
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
    FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_from AND occurred_at < p_to;
  SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0), count(*) FILTER (WHERE status_class = 'countable'), count(*)
    INTO rev_p, paid_p, created_p
    FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_pfrom AND occurred_at < p_pto;
  SELECT sum(spend), sum(impressions), sum(clicks), bool_and(currency = cur) INTO sp, imp, clk, sp_cur_ok
    FROM f360.marketing_spend_daily WHERE market = p_market AND date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND date < (p_to AT TIME ZONE 'America/Mexico_City')::date;
  SELECT sum(spend) INTO sp_p FROM f360.marketing_spend_daily
    WHERE market = p_market AND date >= (p_pfrom AT TIME ZONE 'America/Mexico_City')::date AND date < (p_pto AT TIME ZONE 'America/Mexico_City')::date;
  spend_status := CASE WHEN sp IS NULL THEN 'NOT_CONFIGURED' WHEN NOT sp_cur_ok THEN 'DATA_INCOMPLETE' ELSE 'OK' END;
  ga4_status := CASE WHEN ga4 IN ('HEALTHY', 'CONFIGURED') THEN 'DATA_INCOMPLETE' ELSE 'NOT_CONFIGURED' END;   -- ingestion arrives in S-G2
  SELECT count(*) INTO attributed FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.source_type IS NOT NULL;

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
        FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_from AND occurred_at < p_to
        GROUP BY coalesce(nullif(payment_method, ''), 'sin método')) q)),
    'by_channel', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('channel', f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host),
                 'orders_created', count(*), 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0)) x
        FROM f360.commerce_orders_reporting o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host)) q),
    'by_campaign', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('campaign', a.utm_campaign, 'source', a.utm_source, 'orders_created', count(*),
                 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0),
                 'spend', (SELECT sum(d.spend) FROM f360.marketing_spend_daily d WHERE d.market = p_market AND d.campaign_id = a.utm_campaign
                            AND d.date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND d.date < (p_to AT TIME ZONE 'America/Mexico_City')::date)) x
        FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.utm_campaign IS NOT NULL
        GROUP BY a.utm_campaign, a.utm_source) q),
    'by_product', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('product', nm.name, 'paid_units', sum(l.quantity), 'revenue', sum(l.total)) x
        FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_order_lines l ON l.target_id = o.target_id AND l.woo_order_id = o.woo_order_id
        CROSS JOIN LATERAL (SELECT coalesce(
            (SELECT p.name FROM f360.woo_product_links wl JOIN f360.products p ON p.id = wl.product_id WHERE wl.woo_product_id = l.woo_product_id LIMIT 1),
            (SELECT p.name FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.sku = l.sku LIMIT 1),
            (SELECT m.woo_product_name FROM f360.legacy_woo_map m WHERE m.woo_product_id = l.woo_product_id AND m.woo_product_name IS NOT NULL LIMIT 1),
            'SKU ' || coalesce(l.sku, '?')) AS name) nm
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY nm.name LIMIT 15) q));
END $$;

CREATE OR REPLACE FUNCTION f360.growth_adjustments(p_market text, p_from timestamptz, p_to timestamptz, p_detail boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH o AS (
    SELECT co.target_id, co.woo_order_id, co.status_class, co.net_product, co.units, co.payment_state, co.currency_corrected, co.currency_original, co.market AS market_original, co.order_total
    FROM f360.commerce_orders_reporting co WHERE co.source_system = 'woo' AND co.market_reporting = p_market AND co.occurred_at >= p_from AND co.occurred_at < p_to
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
    'currency_corrections', (SELECT jsonb_build_object('count', count(*), 'detail', CASE WHEN p_detail THEN coalesce(jsonb_agg(jsonb_build_object(
        'woo_order_id', o.woo_order_id, 'woo_currency', o.currency_original, 'woo_market', o.market_original, 'amount', o.order_total,
        'status_class', o.status_class)), '[]') END) FROM o WHERE o.currency_corrected),
    'source', 'Conciliación de Ventas · exclusiones autorizadas (registro inmutable)')
  FROM orig, eff, cls;
$$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261022000400', 'f360_currency_corrections', '{}');

-- ===== 20261022000500_f360_environment_foreign_events =====
-- Fuxia 360 · Aislamiento de ambientes (Mario 2026-10-10): pedidos de PRODUCCIÓN que llegaron a staging por los webhooks #3/#4
-- copiados de staging4 se CONSERVAN como evidencia, identificados como eventos ajenos. Append-only. The marks themselves are data
-- loaded per environment (supabase/staging/mark_foreign_events.sql), never by this migration.
-- Rollback: supabase/rollbacks/20261022000500_f360_environment_foreign_events.down.sql

CREATE TABLE f360.environment_foreign_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id    uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id bigint NOT NULL,
  source_env   text NOT NULL CHECK (source_env IN ('production', 'staging', 'local')),
  source_store text NOT NULL,
  note         text NOT NULL CHECK (length(btrim(note)) >= 10),
  evidence     jsonb NOT NULL,
  noted_by     text NOT NULL,
  noted_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (target_id, woo_order_id)
);
ALTER TABLE f360.environment_foreign_events ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER environment_foreign_events_append_only BEFORE UPDATE OR DELETE ON f360.environment_foreign_events
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
REVOKE ALL ON f360.environment_foreign_events FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at,
         coalesce(cc.corrected_market, o.market) AS market, coalesce(cc.corrected_currency, o.currency) AS currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
  LEFT JOIN f360.commerce_currency_scope cc ON cc.target_id = o.target_id AND cc.woo_order_id = o.woo_order_id AND cc.active
), enriched AS (
  SELECT b.*, ev.id AS evidence_id, ev.gateway_result, ev.transaction_ref, ev.queried_at AS evidence_at, ev.woo_status AS evidence_woo_status,
         d.id AS decision_id, d.decision, d.comment AS decision_comment, d.decided_by_name, d.decided_at, d.duplicate_of,
         d.woo_status_seen, d.facts_hash_seen,
         x.excluded, x.reason AS exclusion_reason,
         dup.candidates AS duplicate_candidates, rtr.retry_paid_order
  FROM base b
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_evidence e WHERE e.target_id = b.target_id AND e.woo_order_id = b.woo_order_id ORDER BY e.id DESC LIMIT 1) ev ON true
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_decisions d WHERE d.target_id = b.target_id AND d.woo_order_id = b.woo_order_id ORDER BY d.id DESC LIMIT 1) d ON true
  LEFT JOIN f360.sales_rec_analytics_scope x ON x.target_id = b.target_id AND x.woo_order_id = b.woo_order_id
  LEFT JOIN LATERAL (
    SELECT array_agg(b2.woo_order_id ORDER BY b2.woo_order_id) AS candidates FROM base b2
    WHERE b2.target_id = b.target_id AND b2.woo_order_id <> b.woo_order_id AND b2.market = b.market AND b2.currency = b.currency
      AND b2.order_total = b.order_total AND b.order_total > 0
      AND b2.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND abs(extract(epoch FROM b2.created_at - b.created_at)) <= 48 * 3600
      AND b.ever_paid AND b2.ever_paid                                  -- a duplicate matters only when both were paid
      AND (b.woo_customer_id IS NULL OR b2.woo_customer_id IS NULL OR b.woo_customer_id = b2.woo_customer_id)) dup ON true
  LEFT JOIN LATERAL (                                                   -- unpaid attempt followed by a paid one = retry, not duplicate
    SELECT min(b3.woo_order_id) AS retry_paid_order FROM base b3
    WHERE NOT b.ever_paid AND b3.ever_paid AND b3.target_id = b.target_id AND b3.market = b.market AND b3.currency = b.currency
      AND b3.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND b3.created_at > b.created_at AND b3.created_at - b.created_at <= interval '48 hours'
      AND (b.woo_customer_id IS NULL OR b3.woo_customer_id IS NULL OR b.woo_customer_id = b3.woo_customer_id)) rtr ON true
), fin AS (
  SELECT e.*,
    CASE
      WHEN NOT e.ever_paid AND e.gateway_result = 'approved' THEN 'CONTRADICTORIA'
      WHEN NOT e.ever_paid THEN 'SIN_COBRO'
      WHEN e.gateway_result = 'order_missing' THEN 'NO_EXISTE_EN_WOO'
      WHEN e.woo_status = 'refunded' OR (e.refund_total > 0 AND e.refund_total >= e.order_total) THEN 'REEMBOLSADO'
      WHEN e.refund_total > 0 THEN 'REEMBOLSO_PARCIAL'
      WHEN e.gateway_result = 'rejected' THEN 'CONTRADICTORIA'
      WHEN e.evidence_id IS NOT NULL AND e.transaction_ref IS NOT NULL AND e.gateway_result IN ('approved', 'transaction_only') THEN 'COBRO_CON_TRANSACCION'
      WHEN e.evidence_id IS NOT NULL THEN 'PAGO_SIN_TRANSACCION'
      ELSE 'PAGO_REGISTRADO_WOO'
    END AS financial_state
  FROM enriched e
), flagged AS (
  SELECT f.*, coalesce((SELECT jsonb_agg(fl) FROM (
    SELECT jsonb_build_object('code', 'NO_CONCRETADO', 'kind', 'no_concretado',
             'why', 'Nunca se registró pago. Estado en WooCommerce: ' || f.woo_status || '.') fl WHERE NOT f.ever_paid
    UNION ALL
    SELECT jsonb_build_object('code', 'REINTENTO_PAGADO', 'kind', 'info', 'paid_order', f.retry_paid_order,
             'why', 'Posible reintento: el pedido #' || f.retry_paid_order || ' se pagó con los mismos productos y el mismo total en menos de 48 h. ' ||
                    'No se da por hecho que sea la misma compra: confírmalo con la evidencia (misma clienta) antes de clasificarlo.')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está ' || CASE f.woo_status WHEN 'cancelled' THEN 'cancelado' WHEN 'failed' THEN 'fallido' ELSE f.woo_status END || ', sin reembolso registrado.')
      WHERE f.ever_paid AND f.woo_status IN ('cancelled', 'failed') AND f.refund_total = 0
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGADO_SIN_EVIDENCIA', 'kind', 'financiera', 'why',
             CASE WHEN f.paid_at IS NULL THEN 'Woo lo marca pagado (' || f.woo_status || ') pero no tiene fecha de pago.'
                  WHEN f.payment_method IS NULL THEN 'Pagado sin método de pago registrado.'
                  ELSE 'Consultado en WooCommerce: pagado sin número de transacción de la pasarela.' END)
      WHERE f.ever_paid AND f.woo_status IN ('processing', 'completed', 'on-hold')
        AND (f.paid_at IS NULL OR f.payment_method IS NULL OR f.financial_state = 'PAGO_SIN_TRANSACCION')
    UNION ALL
    SELECT jsonb_build_object('code', 'EVIDENCIA_CONTRADICE', 'kind', 'financiera', 'why',
             CASE WHEN f.ever_paid THEN 'Woo lo tiene como pagado pero la nota de la pasarela dice rechazado.'
                  ELSE 'La nota de la pasarela dice aprobado pero Woo no registró el pago.' END)
      WHERE f.financial_state = 'CONTRADICTORIA'
    UNION ALL
    SELECT jsonb_build_object('code', 'NO_EXISTE_EN_WOO', 'kind', CASE WHEN f.ever_paid THEN 'financiera' ELSE 'info' END,
             'why', 'Al consultarlo (' || to_char(f.evidence_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') ||
                    ') WooCommerce ya no tenía este pedido' || CASE WHEN f.ever_paid THEN ', y Fuxia 360 lo capturó con pago registrado.' ELSE '.' END)
      WHERE f.gateway_result = 'order_missing'
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_PRUEBA', 'kind', 'revision', 'why',
             CASE WHEN f.payment_method ~* '(prueba|test|sandbox)' THEN 'Método de pago de prueba: ' || f.payment_method || '.'
                  ELSE 'Pedido pagado por 0.' END)
      WHERE f.payment_method ~* '(prueba|test|sandbox)' OR (f.ever_paid AND f.order_total = 0)
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'kind', 'revision', 'candidates', to_jsonb(f.duplicate_candidates),
             'why', 'Dos pedidos PAGADOS con el mismo total y los mismos productos, misma clienta (o sin cuenta), en menos de 48 h: #' ||
                    array_to_string(f.duplicate_candidates, ', #') || '. Es un candidato: confirma o descarta.')
      WHERE f.duplicate_candidates IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'EVENTO_DE_PRODUCCION', 'kind', 'info', 'why',
             'Este registro llegó a ESTE ambiente desde ' || fe.source_store || ' (' || fe.source_env || ') por un webhook copiado; ' ||
             'se conserva solo como evidencia y no es una venta de este ambiente. ' || fe.note)
      FROM f360.environment_foreign_events fe WHERE fe.target_id = f.target_id AND fe.woo_order_id = f.woo_order_id
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_CORREGIDA', 'kind', 'info', 'why',
             'WooCommerce registra ' || cc.original_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (mercado ' || cc.original_market ||
             '). Corrección comercial: ' || cc.corrected_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (' || cc.corrected_market ||
             ') · ' || cc.decided_by_name || ': "' || cc.reason || '". Sin conversión cambiaria; no cambia el estado de pago.')
      FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_SOSPECHOSA', 'kind', 'revision', 'why', sus.why || ' Confírmalo y, si aplica, registra la corrección de moneda.')
      FROM (SELECT f360.currency_suspicion(f.target_id, f.woo_order_id) AS why) sus
      WHERE sus.why IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active)
    UNION ALL
    SELECT jsonb_build_object('code', 'REEMBOLSO', 'kind', 'reembolso',
             'why', 'Reembolso registrado en WooCommerce por ' || f.refund_total || ' ' || f.currency || '.')
      WHERE f.refund_total > 0 OR f.woo_status = 'refunded'
  ) q), '[]'::jsonb) AS flags
  FROM fin f
)
SELECT g.*,
  EXISTS (SELECT 1 FROM jsonb_array_elements(g.flags) z WHERE z->>'kind' = 'financiera') AS has_financial,
  CASE
    WHEN g.decision IS NULL THEN NULL
    WHEN g.decision = 'venta_confirmada' AND g.financial_state IN ('SIN_COBRO', 'CONTRADICTORIA', 'REEMBOLSADO', 'PAGO_SIN_TRANSACCION', 'NO_EXISTE_EN_WOO')
      THEN 'Confirmada como venta, pero la evidencia financiera dice: ' || g.financial_state || '. No cuenta como cobro.'
    WHEN g.decision = 'no_se_concreto' AND g.financial_state IN ('COBRO_CON_TRANSACCION', 'PAGO_REGISTRADO_WOO')
      THEN 'Marcada "no se concretó", pero hay pago registrado y ningún reembolso.'
    WHEN g.decision IN ('duplicado', 'prueba') AND g.ever_paid AND g.refund_total = 0 AND g.woo_status NOT IN ('cancelled', 'failed', 'refunded')
      THEN 'Marcada "' || g.decision || '", pero tiene pago registrado y ningún reembolso.'
    WHEN g.decision = 'reembolso' AND g.refund_total = 0 AND g.woo_status <> 'refunded'
      THEN 'Marcada "reembolso", pero WooCommerce no tiene ningún reembolso registrado.'
  END AS conflict
FROM flagged g;



INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261022000500', 'f360_environment_foreign_events', '{}');

-- Post-checks (same transaction)
DO $$ BEGIN
  IF (SELECT count(DISTINCT proname) FROM pg_proc WHERE proname IN ('f360_growth_cockpit','f360_rec_list','f360_rec_summary','f360_rec_case','f360_rec_decide',
      'f360_rec_set_analytics','f360_rec_can_view','f360_rec_evidence_record','f360_rec_correct_currency')) < 9 THEN RAISE EXCEPTION 'ABORT: faltan funciones'; END IF;
  IF EXISTS (SELECT 1 FROM f360.sales_rec_decisions) OR EXISTS (SELECT 1 FROM f360.sales_rec_exclusions) OR EXISTS (SELECT 1 FROM f360.sales_rec_evidence)
     OR EXISTS (SELECT 1 FROM f360.commerce_currency_corrections) OR EXISTS (SELECT 1 FROM f360.environment_foreign_events)
    THEN RAISE EXCEPTION 'ABORT: este pase no carga datos'; END IF;
  IF has_table_privilege('authenticated', 'f360.sales_rec_decisions', 'INSERT') OR has_table_privilege('authenticated', 'f360.commerce_currency_corrections', 'INSERT')
     OR has_table_privilege('anon', 'f360.sales_rec_decisions', 'SELECT') THEN RAISE EXCEPTION 'ABORT: grants de tablas'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname IN ('f360_rec_evidence_record','f360_growth_cockpit','f360_rec_decide') AND has_function_privilege('anon', oid, 'EXECUTE'))
    THEN RAISE EXCEPTION 'ABORT: funciones abiertas a anon'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'f360_rec_evidence_record' AND has_function_privilege('authenticated', oid, 'EXECUTE'))
    THEN RAISE EXCEPTION 'ABORT: evidencia solo service role'; END IF;
END $$;
COMMIT;
