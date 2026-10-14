-- Fuxia 360 · PRODUCCIÓN · Growth → pestaña "Campañas" (Mario 2026-10-14: "dale"). Migración 20261031000100 (03d3336), igual a staging.
-- Solo agrega UNA función de lectura (public.f360_growth_campaigns, owner/operator). No crea tablas ni cambia datos, pedidos,
-- WooCommerce, gasto ni tipos de cambio. Reversión: supabase/rollbacks/20261031000100_f360_growth_campaigns.down.sql
--   + DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261031000100';
BEGIN;
DO $$ BEGIN
  IF to_regprocedure('public.f360_growth_campaigns(date,date)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261031000100') THEN
    RAISE EXCEPTION 'CAMPANAS PRE: ya está instalada'; END IF;
  IF to_regprocedure('f360.classify_channel_v1(text,text,text,text)') IS NULL OR to_regclass('f360.marketing_spend_daily') IS NULL
     OR to_regclass('f360.commerce_woo_attribution') IS NULL OR to_regclass('f360.fx_rates') IS NULL THEN
    RAISE EXCEPTION 'CAMPANAS PRE: faltan objetos de Growth'; END IF;
END $$;

CREATE FUNCTION public.f360_growth_campaigns(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
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
REVOKE ALL ON FUNCTION public.f360_growth_campaigns(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_growth_campaigns(date, date) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('20261031000100', 'f360_growth_campaigns');
DO $$ BEGIN
  IF has_function_privilege('anon', 'public.f360_growth_campaigns(date,date)', 'EXECUTE') THEN RAISE EXCEPTION 'CAMPANAS POST: anon puede ejecutar'; END IF;
  IF NOT has_function_privilege('authenticated', 'public.f360_growth_campaigns(date,date)', 'EXECUTE') THEN RAISE EXCEPTION 'CAMPANAS POST: sin permiso'; END IF;
END $$;
COMMIT;
