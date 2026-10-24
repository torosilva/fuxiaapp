-- Rollback of 20261102000100_f360_growth_meta_dice: back to the 20261014000200 view, the 20261023000100 import function and the
-- 20261031000100 growth function, then drop the 3 columns. Loses only the imported "Meta dice" numbers (spend is untouched).
-- Teardown once applied: run only with Mario's OK.
BEGIN;
DROP VIEW f360.marketing_spend_daily;
CREATE VIEW f360.marketing_spend_daily AS
  WITH latest AS (
    SELECT DISTINCT ON (r.platform, r.account_id, r.date) r.platform, r.account_id, r.date, r.import_id
    FROM f360.marketing_spend_rows r JOIN f360.marketing_spend_imports i ON i.id = r.import_id AND i.status = 'accepted'
    ORDER BY r.platform, r.account_id, r.date, i.uploaded_at DESC, i.id DESC)
  SELECT r.date, r.market, r.platform, r.account_id, r.campaign_id, r.campaign_name, r.adset_id, r.adset_name, r.ad_id, r.ad_name,
         r.creative_id, r.currency, r.spend, r.impressions, r.clicks, i.source AS spend_source, r.import_id, i.uploaded_at AS imported_at
  FROM f360.marketing_spend_rows r
  JOIN latest l ON l.platform = r.platform AND l.account_id = r.account_id AND l.date = r.date AND l.import_id = r.import_id
  JOIN f360.marketing_spend_imports i ON i.id = r.import_id;
COMMENT ON VIEW f360.marketing_spend_daily IS 'S-G0 D3: effective daily spend (newest accepted import per platform/account/day). Account currency, never converted. A missing day is UNKNOWN, not 0.';
REVOKE ALL ON f360.marketing_spend_daily FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.marketing_spend_daily TO service_role;
CREATE OR REPLACE FUNCTION public.f360_marketing_spend_api_import(p_platform text, p_account_id text, p_currency text, p_from date, p_to date, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_today date := (now() AT TIME ZONE 'America/Mexico_City')::date; v_src text; v_rows jsonb; v_hash text; v_dup uuid; v_id uuid;
  v_started timestamptz := clock_timestamp(); v_x jsonb; i int := 0; e text; n int;
BEGIN
  v_src := CASE p_platform WHEN 'meta' THEN 'meta_ads' WHEN 'google' THEN 'google_ads' END;
  IF v_src IS NULL THEN RAISE EXCEPTION 'Plataforma no válida.'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to OR p_to > v_today OR p_to - p_from > 62 THEN RAISE EXCEPTION 'Ventana no válida (máximo 63 días, no futura).'; END IF;
  IF coalesce(p_account_id, '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RAISE EXCEPTION 'Cuenta publicitaria no válida.'; END IF;
  IF coalesce(p_currency, '') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Moneda no válida.'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) > 5000 THEN RAISE EXCEPTION 'Filas no válidas (máximo 5,000).'; END IF;

  FOR v_x IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    i := i + 1;
    e := f360.marketing_spend_row_error(v_x, v_today);
    IF e IS NULL AND (v_x->>'account_id' <> p_account_id OR v_x->>'currency' <> p_currency) THEN e := 'cuenta o moneda distinta a la de la importación'; END IF;
    IF e IS NULL AND ((v_x->>'date')::date < p_from OR (v_x->>'date')::date > p_to) THEN e := 'fecha fuera de la ventana'; END IF;
    IF e IS NULL AND v_x->>'campaign_id' = 'sin_gasto' THEN e := 'campaign_id reservado'; END IF;
    IF e IS NOT NULL THEN RAISE EXCEPTION 'Fila % no válida: %', i, e; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM (SELECT 1 FROM jsonb_array_elements(p_rows) x
    GROUP BY x->>'date', x->>'campaign_id', x->>'market', coalesce(x->>'adset_id', ''), coalesce(x->>'ad_id', '') HAVING count(*) > 1) d;
  IF n > 0 THEN RAISE EXCEPTION '% combinaciones día/campaña/mercado repetidas.', n; END IF;
  IF EXISTS (SELECT 1 FROM f360.marketing_spend_daily d WHERE d.platform = p_platform AND d.account_id = p_account_id AND d.currency <> p_currency) THEN
    RAISE EXCEPTION 'La moneda no coincide con la ya cargada para esa cuenta.';
  END IF;

  v_rows := p_rows || coalesce((SELECT jsonb_agg(jsonb_build_object('date', g::date, 'market', 'UNKNOWN', 'account_id', p_account_id,
      'campaign_id', 'sin_gasto', 'campaign_name', '(sin gasto ese día)', 'currency', p_currency, 'spend', '0', 'impressions', '0', 'clicks', '0') ORDER BY g)
    FROM generate_series(p_from, p_to, interval '1 day') g
    WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) y WHERE (y->>'date')::date = g::date)), '[]');

  v_hash := encode(sha256(convert_to(p_platform || ':api:' || p_account_id || ':' || p_from || ':' || p_to || ':' || v_rows::text, 'UTF8')), 'hex');
  SELECT id INTO v_dup FROM f360.marketing_spend_imports WHERE platform = p_platform AND content_sha256 = v_hash AND status = 'accepted';
  IF v_dup IS NULL THEN
    INSERT INTO f360.marketing_spend_imports (platform, source, file_name, content_sha256, row_count, date_from, date_to, accounts, currencies,
        spend_by_currency, status, uploaded_by, uploaded_by_name)
      SELECT p_platform, 'api', p_platform || ' API ' || p_from || '..' || p_to, v_hash, jsonb_array_length(v_rows), p_from, p_to, ARRAY[p_account_id], ARRAY[p_currency],
             jsonb_build_object(p_currency, coalesce((SELECT sum((y->>'spend')::numeric) FROM jsonb_array_elements(v_rows) y), 0)),
             'accepted', '00000000-0000-0000-0000-000000000000', initcap(p_platform) || ' API (automático)'
      RETURNING id INTO v_id;
    INSERT INTO f360.marketing_spend_rows (import_id, row_no, date, market, platform, account_id, campaign_id, campaign_name, adset_id, adset_name,
        ad_id, ad_name, creative_id, currency, spend, impressions, clicks)
      SELECT v_id, o, (y->>'date')::date, y->>'market', p_platform, y->>'account_id', y->>'campaign_id', nullif(btrim(y->>'campaign_name'), ''),
             nullif(y->>'adset_id', ''), nullif(btrim(y->>'adset_name'), ''), nullif(y->>'ad_id', ''), nullif(btrim(y->>'ad_name'), ''),
             nullif(y->>'creative_id', ''), y->>'currency', (y->>'spend')::numeric, nullif(y->>'impressions', '')::bigint, nullif(y->>'clicks', '')::bigint
      FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS t(y, o);
  END IF;
  INSERT INTO f360.measurement_runs (source_key, started_at, finished_at, ok, window_from, window_to, rows)
    VALUES (v_src, v_started, clock_timestamp(), true, p_from, p_to, jsonb_array_length(v_rows));
  RETURN jsonb_build_object('ok', true, 'result', CASE WHEN v_dup IS NULL THEN 'accepted' ELSE 'duplicate' END,
    'import_id', coalesce(v_id, v_dup), 'rows', jsonb_array_length(v_rows), 'zero_days', jsonb_array_length(v_rows) - jsonb_array_length(p_rows));
END $$;

CREATE OR REPLACE FUNCTION public.f360_growth_campaigns(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
  d_to date := coalesce(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date);
  d_from date := coalesce(p_from, d_to - 89);
  f timestamptz; t timestamptz; res jsonb;
BEGIN
  IF d_from > d_to THEN RAISE EXCEPTION 'El periodo no es válido.'; END IF;
  IF d_to - d_from > 731 THEN RAISE EXCEPTION 'El periodo máximo es de dos años.'; END IF;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';

  WITH paid AS (
    SELECT o.woo_order_id, c.currency, o.net_product AS revenue, o.market,
           f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host) AS channel,
           nullif(coalesce(a.utm_id, a.utm_campaign), '') AS campaign_key,
           CASE WHEN c.currency = 'MXN' THEN 1::numeric ELSE fx.rate END AS fx_rate
    FROM f360.commerce_orders o
    CROSS JOIN LATERAL (SELECT CASE o.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END AS currency) c   -- as the War Room (corrected market)
    LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    LEFT JOIN f360.fx_rates fx ON fx.currency = c.currency AND fx.status = 'approved'
         AND fx.period = date_trunc('month', o.occurred_at AT TIME ZONE 'America/Mexico_City')::date
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= f AND o.occurred_at < t
  ), spend AS (
    SELECT d.campaign_id, max(d.campaign_name) AS campaign_name, sum(d.spend) AS spend, sum(d.impressions) AS impressions, sum(d.clicks) AS clicks,
           bool_and(d.currency = 'MXN') AS mxn, min(d.date) AS first_day, max(d.date) AS last_day,
           (array_agg(d.market ORDER BY d.spend DESC))[1] AS market
    FROM f360.marketing_spend_daily d
    WHERE d.platform = 'meta' AND d.date >= d_from AND d.date <= d_to
    GROUP BY d.campaign_id HAVING sum(d.spend) > 0
  ), sales AS (
    SELECT campaign_key, jsonb_object_agg(currency, rev) AS by_currency,
           sum(rev_mxn) AS revenue_mxn, bool_or(rev_mxn IS NULL) AS fx_missing
    FROM (SELECT campaign_key, currency, sum(revenue) AS rev,
                 sum(revenue * fx_rate) AS rev_mxn
          FROM paid WHERE campaign_key IS NOT NULL GROUP BY campaign_key, currency) q
    GROUP BY campaign_key
  ), sales_n AS (
    SELECT campaign_key, count(*) AS orders FROM paid WHERE campaign_key IS NOT NULL GROUP BY campaign_key
  ), camp AS (
    SELECT coalesce(s.campaign_id, x.campaign_key) AS campaign_id, s.campaign_name, s.market, s.spend, s.impressions, s.clicks, s.mxn,
           s.first_day, s.last_day, coalesce(n.orders, 0) AS orders, coalesce(x.by_currency, '{}') AS by_currency,
           x.revenue_mxn, coalesce(x.fx_missing, false) AS fx_missing
    FROM spend s FULL JOIN sales x ON x.campaign_key = s.campaign_id
    LEFT JOIN sales_n n ON n.campaign_key = coalesce(s.campaign_id, x.campaign_key)
  ), camp_out AS (
    SELECT jsonb_build_object('campaign_id', campaign_id, 'name', coalesce(campaign_name, 'Campaña sin gasto en este periodo'), 'market', market,
             'spend', spend, 'impressions', impressions, 'clicks', clicks, 'first_day', first_day, 'last_day', last_day,
             'paid_orders', orders, 'revenue_by_currency', by_currency, 'revenue_mxn', CASE WHEN fx_missing THEN NULL ELSE coalesce(revenue_mxn, 0) END,
             'cpa', CASE WHEN spend > 0 AND orders > 0 THEN round(spend / orders, 2) END,
             'return', CASE WHEN spend > 0 AND mxn AND NOT fx_missing THEN round(coalesce(revenue_mxn, 0) / spend, 2) END,
             'verdict', CASE WHEN spend IS NULL THEN 'sin_gasto' WHEN orders = 0 THEN 'sin_ventas' WHEN fx_missing OR NOT mxn THEN 'falta_tc'
                             WHEN revenue_mxn >= spend THEN 'recupera' ELSE 'no_recupera' END) AS j,
           coalesce(spend, 0) AS sort_spend, coalesce(revenue_mxn, 0) AS sort_rev
    FROM camp
  ), chan AS (
    SELECT channel, jsonb_object_agg(currency, rev) AS by_currency, sum(rev_mxn) AS revenue_mxn, bool_or(rev_mxn IS NULL) AS fx_missing
    FROM (SELECT channel, currency, sum(revenue) AS rev, sum(revenue * fx_rate) AS rev_mxn FROM paid GROUP BY channel, currency) q
    GROUP BY channel
  ), chan_n AS (SELECT channel, count(*) AS orders FROM paid GROUP BY channel)
  SELECT jsonb_build_object(
    'from', d_from, 'to', d_to, 'generated_at', now(),
    'campaigns', (SELECT coalesce(jsonb_agg(j ORDER BY sort_spend DESC, sort_rev DESC), '[]') FROM camp_out),
    'channels', (SELECT coalesce(jsonb_agg(jsonb_build_object('channel', c.channel, 'paid_orders', n.orders, 'revenue_by_currency', c.by_currency,
                   'revenue_mxn', CASE WHEN c.fx_missing THEN NULL ELSE c.revenue_mxn END)
                   ORDER BY n.orders DESC, c.revenue_mxn DESC NULLS LAST), '[]') FROM chan c JOIN chan_n n USING (channel)),
    'totals', jsonb_build_object(
      'spend', (SELECT sum(spend) FROM spend), 'spend_currency_ok', coalesce((SELECT bool_and(mxn) FROM spend), true),
      'paid_orders', (SELECT count(*) FROM paid),
      'revenue_by_currency', (SELECT coalesce(jsonb_object_agg(currency, rev), '{}') FROM (SELECT currency, sum(revenue) AS rev FROM paid GROUP BY currency) q),
      'revenue_mxn', CASE WHEN EXISTS (SELECT 1 FROM paid WHERE fx_rate IS NULL) THEN NULL ELSE (SELECT sum(revenue * fx_rate) FROM paid) END,
      'ad_orders', (SELECT count(*) FROM paid p WHERE EXISTS (SELECT 1 FROM spend s WHERE s.campaign_id = p.campaign_key)),
      'ad_revenue_mxn', CASE WHEN EXISTS (SELECT 1 FROM paid p WHERE p.fx_rate IS NULL AND EXISTS (SELECT 1 FROM spend s WHERE s.campaign_id = p.campaign_key)) THEN NULL
                             ELSE (SELECT coalesce(sum(p.revenue * p.fx_rate), 0) FROM paid p WHERE EXISTS (SELECT 1 FROM spend s WHERE s.campaign_id = p.campaign_key)) END,
      'no_fx_currencies', (SELECT coalesce(jsonb_agg(DISTINCT currency), '[]') FROM paid WHERE fx_rate IS NULL),
      'spend_last_day', (SELECT max(date) FROM f360.marketing_spend_daily WHERE platform = 'meta')),
    'sources', jsonb_build_object('sales', 'WooCommerce · pedidos pagados (venta neta de producto)', 'origin', 'WooCommerce Order Attribution · último clic',
                                  'spend', 'Meta Ads API (gasto diario)', 'fx', 'Tipo de cambio mensual aprobado (f360.fx_rates)'))
  INTO res;
  RETURN res;
END $$;
ALTER TABLE f360.marketing_spend_rows DROP COLUMN meta_purchases, DROP COLUMN meta_purchase_value, DROP COLUMN meta_add_to_cart;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261102000100';
COMMIT;
