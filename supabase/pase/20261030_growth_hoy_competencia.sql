-- Fuxia 360 · PRODUCCIÓN · 20261105000100_f360_growth_hoy + 20261105000200_f360_growth_competencia VERBATIM
-- (Mario 2026-10-30: "si dale" → portada Hoy, Clientas a recuperar, Competencia y camino de la clienta de GA4). Probadas en staging.
-- Reversión: supabase/rollbacks/20261105000200_f360_growth_competencia.down.sql y luego 20261105000100_f360_growth_hoy.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261105000100', '20261105000200')) THEN RAISE EXCEPTION 'PRE: ya están'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261104000200') THEN RAISE EXCEPTION 'PRE: falta 20261104000200'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.measurement_sources WHERE key = 'ga4') THEN RAISE EXCEPTION 'PRE: falta la fuente ga4'; END IF;
END $$;
-- Growth · "Hoy" (Mario 2026-10-30: "Growth junta datos pero no dice qué hacer para vender").
--   · f360.ga4_funnel: the GA4 customer path (people per step: visit → product → cart → checkout → purchase) for the last 14 complete
--     days and the 14 before, per market and per GA4 channel group, captured daily by f360-ga4 (company service account, read-only).
--     People are distinct within one (window, market, channel); the 'TODOS' channel row is the distinct total (never a sum of channels).
--   · public.f360_growth_hoy(): one screen — paid sales per market, days since the last sale, cost per sale of the ads (last click),
--     what Meta claims, Instagram net followers, the GA4 path, open experiments and alerts with the action each one asks for.
--   · public.f360_growth_recuperar(): customers who already bought online (paid Woo orders) and have not bought again, with what they
--     bought (product, colour, size) and a link to the Woo order. Only customer_pii_viewers (Carolina, Mario). No new personal data
--     is stored: names/phones stay in WooCommerce, the screen links to the order. f360.growth_outreach logs the follow-up
--     (written / answered / bought / not interested) so Carolina and Mario see who is pending.
-- Business rules unchanged: paid = status_class 'countable' (as War Room, Campañas, Experimentos); currencies are never summed.
-- Rollback: supabase/rollbacks/20261105000100_f360_growth_hoy.down.sql

CREATE TABLE f360.ga4_funnel (
  captured_on  date NOT NULL,                                                   -- CDMX day of the capture
  period       text NOT NULL CHECK (period IN ('actual', 'anterior')),
  date_from    date NOT NULL,
  date_to      date NOT NULL,
  market       text NOT NULL CHECK (market IN ('MX', 'CO', 'ROW')),
  channel      text NOT NULL CHECK (channel ~ '^[A-Za-zÁÉÍÓÚáéíóúñ /()-]{2,60}$'),   -- GA4 sessionDefaultChannelGroup or 'TODOS'
  step         text NOT NULL CHECK (step IN ('session_start', 'view_item', 'add_to_cart', 'begin_checkout', 'purchase')),
  users        integer NOT NULL CHECK (users >= 0),
  imported_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (captured_on, period, market, channel, step),
  CHECK (date_to >= date_from)
);
COMMENT ON TABLE f360.ga4_funnel IS 'Growth Hoy: GA4 people per funnel step (14-day windows) per market/channel, captured daily. Aggregates only.';

CREATE FUNCTION public.f360_ga4_import(p_captured_on date, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE n int;
BEGIN
  IF p_captured_on IS NULL OR p_captured_on > (now() AT TIME ZONE 'America/Mexico_City')::date + 1 OR p_captured_on < '2026-01-01' THEN RAISE EXCEPTION 'Fecha no válida.'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) > 2000 THEN RAISE EXCEPTION 'Respuesta no válida.'; END IF;
  DELETE FROM f360.ga4_funnel WHERE captured_on = p_captured_on;
  INSERT INTO f360.ga4_funnel (captured_on, period, date_from, date_to, market, channel, step, users)
  SELECT p_captured_on, x->>'period', (x->>'date_from')::date, (x->>'date_to')::date, x->>'market', x->>'channel', x->>'step', (x->>'users')::int
  FROM jsonb_array_elements(p_rows) x;
  GET DIAGNOSTICS n = ROW_COUNT;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, rows)
    VALUES ('ga4', clock_timestamp(), true, (SELECT min(date_from) FROM f360.ga4_funnel WHERE captured_on = p_captured_on),
            (SELECT max(date_to) FROM f360.ga4_funnel WHERE captured_on = p_captured_on), n);
  UPDATE f360.measurement_sources SET config_status = 'CONFIGURED', updated_by_name = 'f360-ga4', updated_at = now(),
      notes = 'Cuenta de servicio de la empresa (fuxia360-lectura@fuxia360-datos), Lector en la propiedad 519011849.'
    WHERE key = 'ga4';
  RETURN jsonb_build_object('ok', true, 'rows', n);
END $$;

-- Same tick as Instagram/Clarity, one more allowed function.
CREATE OR REPLACE FUNCTION f360.growth_source_tick(p_function text, p_body jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_function NOT IN ('f360-instagram', 'f360-clarity', 'f360-ga4') THEN RETURN; END IF;
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/' || p_function) INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ ('/functions/v1/' || p_function || '$') THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := p_body, timeout_milliseconds := 55000);
END $$;
-- GA4: daily 07:30 UTC (01:30 CDMX), after GA4 closes the previous day.
SELECT cron.schedule('f360-ga4', '30 7 * * *', $$SELECT f360.growth_source_tick('f360-ga4', '{"action":"daily"}'::jsonb)$$);

-- ── Hoy ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_growth_hoy() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
  today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  d14 date := today - 13; p14 date := today - 27;
  ts14 timestamptz := (today - 13)::timestamp AT TIME ZONE 'America/Mexico_City';
  tp14 timestamptz := (today - 27)::timestamp AT TIME ZONE 'America/Mexico_City';
  ts30 timestamptz := (today - 29)::timestamp AT TIME ZONE 'America/Mexico_City';
  markets jsonb; channels jsonb; ads jsonb; campaigns jsonb; ig jsonb; funnel jsonb; exps jsonb; sources jsonb; alerts jsonb := '[]'; last_capture date;
  m record;
BEGIN
  -- Paid sales per market (native currency, never summed across currencies).
  WITH o AS (
    SELECT o.market, o.net_product, o.occurred_at, o.status_class
    FROM f360.commerce_orders o WHERE o.source_system = 'woo' AND o.occurred_at >= tp14 AND o.market IN ('MX', 'CO')
  ), lastp AS (
    SELECT o.market, max(o.occurred_at) AS last_paid FROM f360.commerce_orders o
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.market IN ('MX', 'CO') GROUP BY 1
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'market', mk.market, 'currency', CASE mk.market WHEN 'CO' THEN 'COP' ELSE 'MXN' END,
      'paid_14', (SELECT count(*) FROM o WHERE o.market = mk.market AND o.status_class = 'countable' AND o.occurred_at >= ts14),
      'paid_prev_14', (SELECT count(*) FROM o WHERE o.market = mk.market AND o.status_class = 'countable' AND o.occurred_at < ts14),
      'revenue_14', (SELECT coalesce(sum(o.net_product), 0) FROM o WHERE o.market = mk.market AND o.status_class = 'countable' AND o.occurred_at >= ts14),
      'created_14', (SELECT count(*) FROM o WHERE o.market = mk.market AND o.occurred_at >= ts14),
      'paid_30', (SELECT count(*) FROM f360.commerce_orders x WHERE x.source_system = 'woo' AND x.status_class = 'countable' AND x.market = mk.market AND x.occurred_at >= ts30),
      'last_paid_at', l.last_paid,
      'days_since_last', CASE WHEN l.last_paid IS NOT NULL THEN today - (l.last_paid AT TIME ZONE 'America/Mexico_City')::date END
    ) ORDER BY mk.market DESC), '[]')
  INTO markets
  FROM (VALUES ('MX'), ('CO')) mk(market) LEFT JOIN lastp l ON l.market = mk.market;

  -- Where the paid sales of the last 14 days came from (last click, Woo attribution).
  SELECT coalesce(jsonb_agg(jsonb_build_object('market', q.market, 'channel', q.channel, 'paid', q.n) ORDER BY q.market DESC, q.n DESC), '[]') INTO channels
  FROM (SELECT o.market, f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host) AS channel, count(*) n
        FROM f360.commerce_orders o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= ts14 AND o.market IN ('MX', 'CO') GROUP BY 1, 2) q;

  -- Ads (Meta) per market, last 14 days: spend vs paid sales whose last click was an ad.
  WITH sp AS (
    SELECT d.market, sum(d.spend) spend, sum(d.clicks) clicks, sum(d.meta_purchases) meta_purchases, bool_and(d.currency = 'MXN') mxn, max(d.date) last_day
    FROM f360.marketing_spend_daily d WHERE d.platform = 'meta' AND d.date >= d14 GROUP BY 1
  ), od AS (
    SELECT o.market, count(*) n FROM f360.commerce_orders o
    JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= ts14
      AND f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host) = 'Meta pagado' GROUP BY 1
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object('market', sp.market, 'spend_mxn', CASE WHEN sp.mxn THEN round(sp.spend) END, 'clicks', sp.clicks,
      'meta_purchases', sp.meta_purchases, 'ads_paid_orders', coalesce(od.n, 0), 'last_day', sp.last_day,
      'cost_per_sale', CASE WHEN sp.mxn AND coalesce(od.n, 0) > 0 THEN round(sp.spend / od.n) END) ORDER BY sp.market DESC), '[]')
  INTO ads FROM sp LEFT JOIN od ON od.market = sp.market;

  SELECT coalesce(jsonb_agg(jsonb_build_object('campaign_id', c.campaign_id, 'name', c.name, 'market', c.market, 'spend_mxn', round(c.spend), 'clicks', c.clicks,
      'meta_purchases', c.mp, 'ads_paid_orders', coalesce(c.orders, 0), 'last_day', c.last_day, 'active', c.last_day >= today - 2) ORDER BY c.spend DESC), '[]')
  INTO campaigns
  -- One row per campaign × market: a campaign that runs in both markets shows both, each with its own spend and sales.
  FROM (SELECT d.campaign_id, max(d.campaign_name) name, d.market, sum(d.spend) spend, sum(d.clicks) clicks,
               sum(d.meta_purchases) mp, max(d.date) last_day,
               (SELECT count(*) FROM f360.commerce_orders o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
                 WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= ts14 AND a.utm_id = d.campaign_id AND o.market = d.market) orders
        FROM f360.marketing_spend_daily d WHERE d.platform = 'meta' AND d.date >= d14 GROUP BY d.campaign_id, d.market) c;

  -- Instagram: net followers last 7 days vs the 7 before (follows/unfollows from the API; days without data are not counted as 0).
  SELECT jsonb_build_object(
      'follows_7', sum(follows) FILTER (WHERE date > today - 8), 'unfollows_7', sum(unfollows) FILTER (WHERE date > today - 8),
      'follows_prev_7', sum(follows) FILTER (WHERE date <= today - 8), 'unfollows_prev_7', sum(unfollows) FILTER (WHERE date <= today - 8),
      'days_7', count(follows) FILTER (WHERE date > today - 8), 'days_prev_7', count(follows) FILTER (WHERE date <= today - 8),
      'followers', (SELECT followers_count FROM f360.ig_account_daily WHERE followers_count IS NOT NULL ORDER BY date DESC LIMIT 1),
      'reach_7', sum(reach) FILTER (WHERE date > today - 8), 'website_clicks_7', sum(website_clicks) FILTER (WHERE date > today - 8))
  INTO ig FROM f360.ig_account_daily WHERE date > today - 15 AND date < today;

  -- GA4 path: the latest capture.
  SELECT max(captured_on) INTO last_capture FROM f360.ga4_funnel;
  SELECT jsonb_build_object('captured_on', last_capture,
      'rows', coalesce(jsonb_agg(jsonb_build_object('period', g.period, 'from', g.date_from, 'to', g.date_to, 'market', g.market, 'channel', g.channel, 'step', g.step, 'users', g.users)), '[]'))
  INTO funnel FROM f360.ga4_funnel g WHERE g.captured_on = last_capture;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'code', e.code, 'name', e.name, 'status', e.status, 'market', e.market, 'start_date', e.start_date,
      'end_date', e.end_date, 'responsible', e.responsible, 'campaign_ids', e.campaign_ids,
      'live', CASE WHEN e.status = 'RUNNING' THEN f360.growth_experiment_measure(e) END) ORDER BY e.created_at), '[]')
  INTO exps FROM f360.growth_experiments e WHERE e.status IN ('DRAFT', 'APPROVED', 'RUNNING');

  SELECT coalesce(jsonb_agg(jsonb_build_object('key', s.key, 'label', s.label, 'config_status', s.config_status,
      'last_success_at', (SELECT max(finished_at) FROM f360.measurement_runs mr WHERE mr.source_key = s.key AND mr.ok))), '[]')
  INTO sources FROM f360.measurement_sources s WHERE s.key IN ('ga4', 'instagram', 'clarity', 'meta_ads');

  -- Alerts: each one says what to do. Rules are explicit and shown on screen; nothing here changes a business rule.
  FOR m IN SELECT * FROM jsonb_array_elements(markets) LOOP
    IF (m.value->>'days_since_last')::int >= 3 THEN
      alerts := alerts || jsonb_build_object('level', CASE WHEN (m.value->>'days_since_last')::int >= 7 THEN 'alta' ELSE 'media' END,
        'market', m.value->>'market', 'title', format('%s días sin una venta pagada en %s', m.value->>'days_since_last', CASE m.value->>'market' WHEN 'MX' THEN 'México' ELSE 'Colombia' END),
        'action', 'Hacer una compra de prueba hasta la pasarela y revisar que los anuncios estén corriendo.');
    END IF;
  END LOOP;
  FOR m IN SELECT * FROM jsonb_array_elements(ads) LOOP
    IF (m.value->>'spend_mxn')::numeric >= 1000 AND (m.value->>'ads_paid_orders')::int = 0 THEN
      alerts := alerts || jsonb_build_object('level', 'alta', 'market', m.value->>'market',
        'title', format('$%s MXN en anuncios en 14 días y ninguna venta que llegara por un anuncio (%s)', to_char((m.value->>'spend_mxn')::numeric, 'FM999,999'), m.value->>'market'),
        'action', 'Pedir a la agencia que cambie objetivo, audiencia o destino, y registrarlo como experimento antes de gastar más.');
    END IF;
  END LOOP;
  IF last_capture IS NULL OR last_capture < today - 1 THEN
    alerts := alerts || jsonb_build_object('level', 'media', 'market', NULL, 'title', 'El camino de la clienta (Google Analytics) no se actualizó hoy',
      'action', 'Revisar la fuente ga4 en Growth → Medición.');
  END IF;

  RETURN jsonb_build_object('today', today, 'generated_at', now(), 'window', jsonb_build_object('from', d14, 'to', today, 'prev_from', p14, 'prev_to', d14 - 1),
    'markets', markets, 'channels', channels, 'ads', ads, 'campaigns', campaigns, 'instagram', ig, 'funnel', funnel, 'experiments', exps,
    'sources', sources, 'alerts', alerts,
    'rules', jsonb_build_array(
      'Venta = pedido de WooCommerce pagado (el mismo criterio que War Room, Campañas y Experimentos).',
      'Venta por anuncio = el último clic antes de comprar fue un anuncio de Meta (UTM pagado). Meta cuenta además a quien solo vio el anuncio: por eso “Meta dice” suele ser mayor.',
      'Camino de la clienta = personas distintas en Google Analytics en los últimos 14 días cerrados; Google Analytics no ve a quien bloquea cookies.',
      'MXN y COP nunca se suman.'));
END $$;

-- Follow-up log (who wrote to whom and what happened). Append-only; the list shows the latest entry per buyer.
CREATE TABLE f360.growth_outreach (
  id          bigserial PRIMARY KEY,
  market      text NOT NULL CHECK (market IN ('MX', 'CO')),
  buyer       text NOT NULL CHECK (buyer ~ '^(pedido-)?[0-9]{1,12}$'),
  status      text NOT NULL CHECK (status IN ('escrito', 'respondio', 'compro', 'no_interesa', 'sin_datos')),
  note        text CHECK (note IS NULL OR length(note) <= 300),
  actor       uuid NOT NULL,
  actor_name  text NOT NULL,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX growth_outreach_buyer_idx ON f360.growth_outreach (market, buyer, at DESC);
CREATE TRIGGER growth_outreach_no_edit BEFORE UPDATE OR DELETE ON f360.growth_outreach
  FOR EACH ROW EXECUTE FUNCTION f360.growth_experiment_changes_append_only();

CREATE FUNCTION public.f360_growth_outreach_mark(p_market text, p_buyer text, p_status text, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Solo Carolina y Mario ven esta lista.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  INSERT INTO f360.growth_outreach (market, buyer, status, note, actor, actor_name) VALUES (p_market, p_buyer, p_status, nullif(btrim(p_note), ''), r.auth_user_id, r.display_name);
  RETURN jsonb_build_object('ok', true);
END $$;

-- ── Clientas a recuperar ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Volatile (writes the access log). One row per buyer (Woo customer id; guest orders by order). Only paid online orders. Who bought again is excluded by default.
CREATE FUNCTION public.f360_growth_recuperar(p_market text DEFAULT 'MX') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); res jsonb;
  today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Solo Carolina y Mario ven esta lista.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_market NOT IN ('MX', 'CO') THEN RAISE EXCEPTION 'Mercado no válido.'; END IF;

  WITH paid AS (
    SELECT o.target_id, o.woo_order_id, o.external_ref, o.occurred_at, o.net_product, o.loyalty_customer_id,
           coalesce(nullif(o.woo_customer_id, 0)::text, 'pedido-' || o.woo_order_id) AS buyer
    FROM f360.commerce_orders o
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.market = p_market
  ), b AS (
    SELECT buyer, count(*) orders, min(occurred_at) first_at, max(occurred_at) last_at, sum(net_product) spent,
           bool_or(loyalty_customer_id IS NOT NULL) in_club,
           (array_agg(woo_order_id ORDER BY occurred_at DESC))[1] last_order, (array_agg(external_ref ORDER BY occurred_at DESC))[1] last_ref,
           (array_agg(target_id ORDER BY occurred_at DESC))[1] last_target
    FROM paid GROUP BY buyer
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'buyer', b.buyer, 'orders', b.orders, 'first_at', b.first_at, 'last_at', b.last_at,
      'days_since', today - (b.last_at AT TIME ZONE 'America/Mexico_City')::date, 'spent', b.spent, 'in_club', b.in_club,
      'outreach', (SELECT jsonb_build_object('status', g.status, 'note', g.note, 'by', g.actor_name, 'at', g.at) FROM f360.growth_outreach g
                   WHERE g.market = p_market AND g.buyer = b.buyer ORDER BY g.at DESC LIMIT 1),
      'last_order', b.last_order, 'order_url', (SELECT t.base_url FROM f360.sales_targets t WHERE t.id = b.last_target) || '/wp-admin/post.php?post=' || b.last_order || '&action=edit',
      'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('product', coalesce(p.name, l.canonical_product_key, l.sku), 'color', pc.name, 'size', v.size_label, 'qty', l.quantity)), '[]')
                FROM f360.commerce_order_lines l
                LEFT JOIN f360.product_variants v ON v.id = l.variant_id
                LEFT JOIN f360.products p ON p.id = coalesce(v.product_id, l.product_id)
                LEFT JOIN f360.product_colors pc ON pc.id = v.color_id
                WHERE l.source_system = 'woo' AND l.external_ref = b.last_ref)
    ) ORDER BY b.last_at DESC), '[]')
  INTO res FROM b WHERE b.orders = 1 OR b.last_at < now() - interval '60 days';

  INSERT INTO f360.customer_access_log (auth_user_id, action, result) VALUES (auth.uid(), 'admin_list', 'ok');   -- Growth → Clientas a recuperar
  RETURN jsonb_build_object('market', p_market, 'generated_at', now(), 'buyers', res,
    'rule', 'Clientas con un solo pedido pagado en línea, o cuya última compra fue hace más de 60 días. El nombre y el teléfono están en el pedido de WooCommerce (no se copian a Fuxia 360).');
END $$;

-- ── Permissions ───────────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE f360.ga4_funnel ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.growth_outreach ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.ga4_funnel, f360.growth_outreach FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.ga4_funnel TO service_role;
GRANT SELECT, INSERT ON f360.growth_outreach TO service_role;
GRANT USAGE ON SEQUENCE f360.growth_outreach_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.f360_growth_outreach_mark(text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_growth_outreach_mark(text, text, text, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_ga4_import(date, jsonb), public.f360_growth_hoy(), public.f360_growth_recuperar(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION f360.growth_source_tick(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_ga4_import(date, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_growth_hoy(), public.f360_growth_recuperar(text) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261105000100', 'f360_growth_hoy', '{}');
-- Growth · Competencia (Mario 2026-10-30: "me habías puesto una tabla con mi competencia y ya no la veo").
--   · f360.competitors: the brands we watch. f360.competitor_observations: dated observations (followers, active ads in the Meta
--     Ad Library, price band, channels, how they advertise), each with its source. Nothing is overwritten: every week is a new row,
--     so the screen shows the change.
--   · Seed: the analysis of 2026-10-27 (Meta Ad Library by keyword → ad counts are approximate; "NV" = not verified → NULL).
--   · public.f360_growth_competencia() (operator) and public.f360_competitor_observe() (owner) to record a new observation.
-- Rollback: supabase/rollbacks/20261105000200_f360_growth_competencia.down.sql

CREATE TABLE f360.competitors (
  key        text PRIMARY KEY CHECK (key ~ '^[a-z0-9-]{2,40}$'),
  name       text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 80),
  origin     text CHECK (origin IS NULL OR length(origin) <= 80),
  url        text CHECK (url IS NULL OR url ~ '^https://[^\s]{4,200}$'),
  ig_handle  text CHECK (ig_handle IS NULL OR ig_handle ~ '^[A-Za-z0-9._]{2,30}$'),
  is_self    boolean NOT NULL DEFAULT false,
  sort       smallint NOT NULL DEFAULT 100,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE f360.competitor_observations (
  id               bigserial PRIMARY KEY,
  competitor_key   text NOT NULL REFERENCES f360.competitors(key) ON DELETE RESTRICT,
  observed_on      date NOT NULL,
  followers_ig     integer CHECK (followers_ig IS NULL OR followers_ig >= 0),
  active_ads_meta  integer CHECK (active_ads_meta IS NULL OR active_ads_meta >= 0),
  ads_approx       boolean NOT NULL DEFAULT true,
  price_text       text CHECK (price_text IS NULL OR length(price_text) <= 300),
  channels         text CHECK (channels IS NULL OR length(channels) <= 300),
  how_they_advertise text CHECK (how_they_advertise IS NULL OR length(how_they_advertise) <= 1500),
  source           text NOT NULL CHECK (length(btrim(source)) BETWEEN 3 AND 300),
  recorded_by_name text NOT NULL,
  recorded_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (competitor_key, observed_on)
);
COMMENT ON TABLE f360.competitor_observations IS 'Growth Competencia: dated public observations of competitor brands (followers, Meta Ad Library counts, prices). One row per brand per day; history is kept.';

INSERT INTO f360.competitors (key, name, origin, url, is_self, sort) VALUES
  ('fuxia', 'Fuxia', 'MX / CO', 'https://fuxiaballerinas.com', true, 0),
  ('regina-romero', 'Regina Romero', 'MX, desde 1984', 'https://reginaromero.com', false, 10),
  ('bala-di-gala', 'Bala Di Gala', 'MX, hecho a mano', 'https://baladigala.com.mx', false, 20),
  ('dione', 'Dione', 'MX', 'https://dione.com.mx', false, 30),
  ('goroshus', 'Goroshus', 'MX', 'https://goroshus.com', false, 40),
  ('loly-in-the-sky', 'Loly in the Sky', 'MX, León', 'https://lolyinthesky.com.mx', false, 50),
  ('milamilu', 'MilaMilu', 'MX, Guadalajara', 'https://milamilu.com', false, 60),
  ('pretty-ballerinas', 'Pretty Ballerinas', 'España', 'https://prettyballerinas.com', false, 70),
  ('flamingos-life', 'Flamingos'' Life', 'España', 'https://flamingoslife.com', false, 80),
  ('bimba-y-lola', 'Bimba y Lola', 'España', 'https://bimbaylola.com', false, 90),
  ('roth-malere', 'Roth Malère', 'MX, lujo', 'https://rothmalere.com', false, 95);

INSERT INTO f360.competitor_observations (competitor_key, observed_on, followers_ig, active_ads_meta, price_text, channels, how_they_advertise, source, recorded_by_name) VALUES
  ('fuxia', '2026-10-27', 99000, 5, '2,800–4,500 MXN', 'Sitio propio',
   '3 de los 5 anuncios mandan al perfil de Instagram o piden "Comenta FUXIA y te mandamos el link"; solo 2 llevan a la tienda. Ninguno menciona meses sin intereses, envío gratis, cambio de talla ni precio.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado) y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('regina-romero', '2026-10-27', 211000, 100, 'Flats y loafers de 2,000 (rebaja) a 4,599 MXN; mediana del catálogo 3,899', 'Sitio, Palacio de Hierro, Liverpool, boutiques en Lomas y Roma (CDMX)',
   'Video corto (3–31 s), carrusel y catálogo con precio tachado. Mensajes: "Hechos a mano en México desde 1984", hasta 6 MSI, envío gratis desde $1,500, recuperación de carrito con reseña de clienta. Del 11 sep al 10 oct corrió "THE FINAL EDIT": pares a $2,000 y $2,500 con envío gratis. Lleva a la página de producto.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('bala-di-gala', '2026-10-27', 190000, 110, 'Botines en Palacio a 3,990 MXN; clog Penny en promoción a 1,000; sitio en USD 169–349', 'Sitio MX y sitio en USD, Palacio de Hierro, TikTok @baladigala',
   'Muchos videos cortos, uno o dos por modelo. Le habla a un dolor concreto ("tu western necesita contraste", "Ojo con el fit"). Repite "Envío gratis + primer cambio de talla sin costo" y "Hecho a mano en México". Escasez: "1,000 Penny''s a $1,000" (código PENNY1000). Colaboración FLUX MITS x BDG. Lleva a su tienda.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('dione', '2026-10-27', 61000, 32, 'Ballerinas de piel de 2,094 a 3,490 MXN (Sandy y Margot 2,990; Aurielle 3,490)', 'Sitio, boutiques (según su sitio), TikTok @dione_moda',
   'Lanzamiento de la colección OI26: más de 20 anuncios entre el 21 y el 26 de octubre, videos con hashtags (#ballerinas). Gancho: 10% en la primera compra. Un anuncio en alianza con una creadora (Ciara Gómez Ibarra). Reseñas con Judge.me. Lleva a su tienda.',
   'Biblioteca de anuncios de Meta (búsqueda por palabra, conteo aproximado), sitio y perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('goroshus', '2026-10-27', 26000, NULL, 'Flats de 830 a 998 MXN', 'Sitio', NULL, 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('loly-in-the-sky', '2026-10-27', 416000, NULL, NULL, 'Sitio', NULL, 'Perfil de Instagram, 27 oct 2026; precios y anuncios no verificados', 'Análisis de competencia (Claude)'),
  ('milamilu', '2026-10-27', 51000, NULL, '599–3,800 MXN (mules 1,300)', 'Sitio', 'Su producto más reciente es de diciembre de 2025.', 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('pretty-ballerinas', '2026-10-27', 179000, NULL, '99–229 € (≈2,100–4,900 MXN)', 'Tienda propia en México según Modaes (no verificado)', NULL, 'Sitio y perfil de Instagram, 27 oct 2026; anuncios no revisados', 'Análisis de competencia (Claude)'),
  ('flamingos-life', '2026-10-27', 147000, NULL, NULL, 'Sitio', NULL, 'Perfil de Instagram, 27 oct 2026; precios y anuncios no verificados', 'Análisis de competencia (Claude)'),
  ('bimba-y-lola', '2026-10-27', 2000000, NULL, NULL, 'Presencia en México no verificada', NULL, 'Perfil de Instagram, 27 oct 2026', 'Análisis de competencia (Claude)'),
  ('roth-malere', '2026-10-27', NULL, NULL, '8,550–12,500 MXN, sin flats', 'Sitio', NULL, 'Sitio, 27 oct 2026', 'Análisis de competencia (Claude)');

CREATE FUNCTION public.f360_growth_competencia() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); res jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'name', c.name, 'origin', c.origin, 'url', c.url, 'is_self', c.is_self,
      'latest', (SELECT to_jsonb(o) - 'id' FROM f360.competitor_observations o WHERE o.competitor_key = c.key ORDER BY o.observed_on DESC LIMIT 1),
      'previous', (SELECT jsonb_build_object('observed_on', o.observed_on, 'followers_ig', o.followers_ig, 'active_ads_meta', o.active_ads_meta)
                   FROM f360.competitor_observations o WHERE o.competitor_key = c.key ORDER BY o.observed_on DESC OFFSET 1 LIMIT 1)
    ) ORDER BY c.sort), '[]') INTO res FROM f360.competitors c;
  RETURN jsonb_build_object('brands', res, 'can_record', r.role = 'owner',
    'notes', jsonb_build_array(
      'Anuncios activos: Biblioteca de anuncios de Meta (facebook.com/ads/library), país México. Busca por palabra, así que el número es aproximado.',
      'Seguidores: el número que muestra el perfil de Instagram ese día.',
      'Vacío = no se revisó o no se pudo verificar. Nunca es 0.'));
END $$;

-- Owner records one brand's observation for a day (a second save the same day replaces that day's row).
CREATE FUNCTION public.f360_competitor_observe(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); k text; d date;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Datos no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF k NOT IN ('competitor_key', 'observed_on', 'followers_ig', 'active_ads_meta', 'price_text', 'channels', 'how_they_advertise', 'source') THEN RAISE EXCEPTION 'Campo no permitido: %', k; END IF;
  END LOOP;
  d := coalesce((p->>'observed_on')::date, (now() AT TIME ZONE 'America/Mexico_City')::date);
  IF d > (now() AT TIME ZONE 'America/Mexico_City')::date THEN RAISE EXCEPTION 'La fecha no puede ser futura.'; END IF;
  INSERT INTO f360.competitor_observations (competitor_key, observed_on, followers_ig, active_ads_meta, price_text, channels, how_they_advertise, source, recorded_by_name)
  VALUES (p->>'competitor_key', d, nullif(p->>'followers_ig', '')::int, nullif(p->>'active_ads_meta', '')::int, nullif(btrim(p->>'price_text'), ''),
          nullif(btrim(p->>'channels'), ''), nullif(btrim(p->>'how_they_advertise'), ''), coalesce(nullif(btrim(p->>'source'), ''), 'Revisión manual'), r.display_name)
  ON CONFLICT (competitor_key, observed_on) DO UPDATE SET followers_ig = EXCLUDED.followers_ig, active_ads_meta = EXCLUDED.active_ads_meta,
    price_text = coalesce(EXCLUDED.price_text, f360.competitor_observations.price_text), channels = coalesce(EXCLUDED.channels, f360.competitor_observations.channels),
    how_they_advertise = coalesce(EXCLUDED.how_they_advertise, f360.competitor_observations.how_they_advertise),
    source = EXCLUDED.source, recorded_by_name = EXCLUDED.recorded_by_name, recorded_at = now();
  RETURN jsonb_build_object('ok', true);
END $$;

ALTER TABLE f360.competitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.competitor_observations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.competitors, f360.competitor_observations FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.competitors, f360.competitor_observations TO service_role;
GRANT USAGE ON SEQUENCE f360.competitor_observations_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.f360_growth_competencia(), public.f360_competitor_observe(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_growth_competencia(), public.f360_competitor_observe(jsonb) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261105000200', 'f360_growth_competencia', '{}');
DO $$ BEGIN
  IF (SELECT count(*) FROM f360.competitor_observations) <> 11 THEN RAISE EXCEPTION 'POST: observaciones'; END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-ga4') THEN RAISE EXCEPTION 'POST: cron f360-ga4'; END IF;
  IF has_function_privilege('anon', 'public.f360_growth_recuperar(text)', 'EXECUTE') THEN RAISE EXCEPTION 'POST: anon puede leer clientas'; END IF;
  IF has_table_privilege('authenticated', 'f360.growth_outreach', 'SELECT') THEN RAISE EXCEPTION 'POST: tabla de seguimiento expuesta'; END IF;
END $$;
COMMIT;
