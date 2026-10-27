-- Fuxia 360 · Growth P0-A Instagram orgánico + P0-C Clarity diario (Mario 2026-10-27: "no quiero otro módulo… quiero terminar el
-- Growth que ya construimos"; autorizado SOLO en staging). ADDITIVE: new tables + functions inside the existing Growth / Medición.
-- Reuses (no duplicates):
--   · f360.measurement_sources / measurement_runs: two new API sources ('instagram', 'clarity'); their health appears in
--     Growth → Medición through the existing generic `kind = 'api'` branch of f360.sg0_source_health();
--   · f360.commerce_orders + f360.commerce_woo_attribution: the only sales evidence (paid Woo orders, last touch);
--   · f360.require_role / user_roles: operator+ reads (same as War Room / Campañas, D-G1-05); service role writes;
--   · vault f360_sync_url / f360_sync_secret + pg_net + pg_cron: same scheduler pattern as f360-meta-spend.
-- Truth rules:
--   · Instagram metrics are what the Instagram Graph API returns, stored as captured (lifetime numbers per post are snapshots
--     by capture day). A missing metric is NULL, never 0;
--   · a sale is linked to a post ONLY when the order's own attribution names it (utm_content = media id or permalink shortcode).
--     Otherwise it is an "Instagram sale without an identifiable post". No modelled / inferred conversions per post;
--   · Clarity: the export API only answers the last 1–3 days (verified 2026-10-27: numOfDays=4 and 30 → HTTP 400) and has no date
--     parameter, so history exists only if it is captured every day. Rows are stored raw per call (aggregates; no personal data).
-- Rollback: supabase/rollbacks/20261104000100_f360_growth_instagram_clarity.down.sql

-- ── Sources registry ──────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE f360.measurement_sources DROP CONSTRAINT measurement_sources_key_check;
ALTER TABLE f360.measurement_sources ADD CONSTRAINT measurement_sources_key_check CHECK (key IN ('woocommerce', 'order_reconciliation', 'ga4',
  'meta_ads', 'google_ads', 'marketing_spend', 'store_sales', 'fx_rates', 'instagram', 'clarity'));
INSERT INTO f360.measurement_sources (key, label, kind, config_status, spend_platform, stale_after_hours, notes) VALUES
  ('instagram', 'Instagram orgánico (Graph API, solo lectura)', 'api', 'NOT_CONFIGURED', NULL, 36,
   'Requiere que el usuario del sistema tenga asignada la cuenta de Instagram y los permisos instagram_basic + instagram_manage_insights.'),
  ('clarity', 'Microsoft Clarity (export API, últimos 1–3 días)', 'api', 'NOT_CONFIGURED', NULL, 36,
   'La API solo da los últimos 1–3 días: lo que no se captura cada día se pierde. 10 llamadas al día por proyecto.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.f360_measurement_run_failed(p_source_key text, p_from date, p_to date, p_error text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_source_key NOT IN ('meta_ads', 'google_ads', 'ga4', 'fx_rates', 'instagram', 'clarity') THEN RAISE EXCEPTION 'Fuente no válida.'; END IF;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, error)
    VALUES (p_source_key, clock_timestamp(), false, p_from, p_to, left(coalesce(nullif(btrim(p_error), ''), 'error sin detalle'), 500));
END $$;

-- ── Instagram ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE f360.ig_account_daily (
  ig_user_id         text NOT NULL CHECK (ig_user_id ~ '^\d{5,25}$'),
  date               date NOT NULL,
  followers_count    integer CHECK (followers_count >= 0),     -- only on the day it was captured (the API has no follower history)
  reach              integer CHECK (reach >= 0),
  views              integer CHECK (views >= 0),
  profile_views      integer CHECK (profile_views >= 0),
  website_clicks     integer CHECK (website_clicks >= 0),
  accounts_engaged   integer CHECK (accounts_engaged >= 0),
  total_interactions integer CHECK (total_interactions >= 0),
  follows            integer CHECK (follows >= 0),
  unfollows          integer CHECK (unfollows >= 0),
  captured_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (ig_user_id, date)
);
COMMENT ON TABLE f360.ig_account_daily IS 'Growth P0-A: Instagram account insights per day as returned by the Graph API (NULL = not returned, never 0).';

CREATE TABLE f360.ig_media (
  media_id           text PRIMARY KEY CHECK (media_id ~ '^\d{5,25}$'),
  ig_user_id         text NOT NULL CHECK (ig_user_id ~ '^\d{5,25}$'),
  kind               text NOT NULL CHECK (kind IN ('post', 'carousel', 'reel', 'story')),
  media_type         text CHECK (media_type IS NULL OR media_type ~ '^[A-Z_]{2,30}$'),
  media_product_type text CHECK (media_product_type IS NULL OR media_product_type ~ '^[A-Z_]{2,30}$'),
  posted_at          timestamptz NOT NULL,
  permalink          text CHECK (permalink IS NULL OR permalink ~ '^https://(www\.)?instagram\.com/'),
  shortcode          text CHECK (shortcode IS NULL OR shortcode ~ '^[A-Za-z0-9_-]{5,40}$'),
  caption            text CHECK (caption IS NULL OR length(caption) <= 2200),
  first_seen_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ig_media_posted_idx ON f360.ig_media (posted_at DESC);
COMMENT ON TABLE f360.ig_media IS 'Growth P0-A: published Instagram content (posts, carousels, reels, stories). Brand content only; no follower data.';

CREATE TABLE f360.ig_media_metrics (
  media_id           text NOT NULL REFERENCES f360.ig_media(media_id) ON DELETE CASCADE,
  captured_on        date NOT NULL,
  reach              integer CHECK (reach >= 0),
  views              integer CHECK (views >= 0),
  likes              integer CHECK (likes >= 0),
  comments           integer CHECK (comments >= 0),
  saves              integer CHECK (saves >= 0),
  shares             integer CHECK (shares >= 0),
  total_interactions integer CHECK (total_interactions >= 0),
  replies            integer CHECK (replies >= 0),
  profile_visits     integer CHECK (profile_visits >= 0),
  follows            integer CHECK (follows >= 0),
  avg_watch_ms       integer CHECK (avg_watch_ms >= 0),
  captured_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (media_id, captured_on)
);
COMMENT ON TABLE f360.ig_media_metrics IS 'Growth P0-A: lifetime metrics of each piece of content, one snapshot per capture day (stories: the last one before they expire).';

-- jsonb → non-negative integer or NULL; anything else is rejected (the import is all-or-nothing).
CREATE FUNCTION f360.ig_int(p jsonb, k text) RETURNS integer LANGUAGE plpgsql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
DECLARE v jsonb := p->k;
BEGIN
  IF v IS NULL OR v = 'null'::jsonb THEN RETURN NULL; END IF;
  IF jsonb_typeof(v) <> 'number' OR (v #>> '{}')::numeric < 0 OR (v #>> '{}')::numeric > 2147483647 OR (v #>> '{}')::numeric <> trunc((v #>> '{}')::numeric) THEN
    RAISE EXCEPTION 'Valor no válido en %: %', k, v;
  END IF;
  RETURN (v #>> '{}')::integer;
END $$;

-- Service role only (f360-instagram). p_account: [{date, reach, views, …}], p_media: [{media_id, kind, …, metrics:{…}}].
CREATE FUNCTION public.f360_instagram_import(p_ig_user_id text, p_from date, p_to date, p_account jsonb, p_media jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_today date := (now() AT TIME ZONE 'America/Mexico_City')::date; x jsonb; na int := 0; nm int := 0; v_kind text;
BEGIN
  IF coalesce(p_ig_user_id, '') !~ '^\d{5,25}$' THEN RAISE EXCEPTION 'Cuenta de Instagram no válida.'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to OR p_to > v_today THEN RAISE EXCEPTION 'Ventana no válida.'; END IF;
  IF jsonb_typeof(p_account) IS DISTINCT FROM 'array' OR jsonb_array_length(p_account) > 1000 THEN RAISE EXCEPTION 'Días no válidos (máximo 1,000).'; END IF;
  IF jsonb_typeof(p_media) IS DISTINCT FROM 'array' OR jsonb_array_length(p_media) > 5000 THEN RAISE EXCEPTION 'Contenido no válido (máximo 5,000).'; END IF;

  FOR x IN SELECT * FROM jsonb_array_elements(p_account) LOOP
    IF coalesce(x->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' OR (x->>'date')::date < p_from OR (x->>'date')::date > p_to THEN RAISE EXCEPTION 'Día fuera de la ventana: %', x->>'date'; END IF;
    INSERT INTO f360.ig_account_daily AS t (ig_user_id, date, followers_count, reach, views, profile_views, website_clicks, accounts_engaged, total_interactions, follows, unfollows)
    VALUES (p_ig_user_id, (x->>'date')::date, f360.ig_int(x, 'followers_count'), f360.ig_int(x, 'reach'), f360.ig_int(x, 'views'), f360.ig_int(x, 'profile_views'),
            f360.ig_int(x, 'website_clicks'), f360.ig_int(x, 'accounts_engaged'), f360.ig_int(x, 'total_interactions'), f360.ig_int(x, 'follows'), f360.ig_int(x, 'unfollows'))
    ON CONFLICT (ig_user_id, date) DO UPDATE SET   -- a newer read wins, but a metric the newer read did not return keeps its value
      followers_count = coalesce(EXCLUDED.followers_count, t.followers_count), reach = coalesce(EXCLUDED.reach, t.reach), views = coalesce(EXCLUDED.views, t.views),
      profile_views = coalesce(EXCLUDED.profile_views, t.profile_views), website_clicks = coalesce(EXCLUDED.website_clicks, t.website_clicks),
      accounts_engaged = coalesce(EXCLUDED.accounts_engaged, t.accounts_engaged), total_interactions = coalesce(EXCLUDED.total_interactions, t.total_interactions),
      follows = coalesce(EXCLUDED.follows, t.follows), unfollows = coalesce(EXCLUDED.unfollows, t.unfollows), captured_at = now();
    na := na + 1;
  END LOOP;

  FOR x IN SELECT * FROM jsonb_array_elements(p_media) LOOP
    v_kind := x->>'kind';
    IF v_kind NOT IN ('post', 'carousel', 'reel', 'story') THEN RAISE EXCEPTION 'Tipo de contenido no válido: %', v_kind; END IF;
    INSERT INTO f360.ig_media AS t (media_id, ig_user_id, kind, media_type, media_product_type, posted_at, permalink, shortcode, caption)
    VALUES (x->>'media_id', p_ig_user_id, v_kind, x->>'media_type', x->>'media_product_type', (x->>'posted_at')::timestamptz,
            x->>'permalink', x->>'shortcode', left(x->>'caption', 2200))
    ON CONFLICT (media_id) DO UPDATE SET kind = EXCLUDED.kind, media_type = EXCLUDED.media_type, media_product_type = EXCLUDED.media_product_type,
      permalink = coalesce(EXCLUDED.permalink, t.permalink), shortcode = coalesce(EXCLUDED.shortcode, t.shortcode),
      caption = coalesce(EXCLUDED.caption, t.caption), last_seen_at = now()
    WHERE t.ig_user_id = EXCLUDED.ig_user_id;
    IF jsonb_typeof(x->'metrics') = 'object' THEN
      INSERT INTO f360.ig_media_metrics AS t (media_id, captured_on, reach, views, likes, comments, saves, shares, total_interactions, replies, profile_visits, follows, avg_watch_ms)
      SELECT x->>'media_id', v_today, f360.ig_int(m, 'reach'), f360.ig_int(m, 'views'), f360.ig_int(m, 'likes'), f360.ig_int(m, 'comments'), f360.ig_int(m, 'saves'),
             f360.ig_int(m, 'shares'), f360.ig_int(m, 'total_interactions'), f360.ig_int(m, 'replies'), f360.ig_int(m, 'profile_visits'), f360.ig_int(m, 'follows'),
             f360.ig_int(m, 'avg_watch_ms')
      FROM (SELECT x->'metrics' AS m) q
      ON CONFLICT (media_id, captured_on) DO UPDATE SET
        reach = coalesce(EXCLUDED.reach, t.reach), views = coalesce(EXCLUDED.views, t.views), likes = coalesce(EXCLUDED.likes, t.likes),
        comments = coalesce(EXCLUDED.comments, t.comments), saves = coalesce(EXCLUDED.saves, t.saves), shares = coalesce(EXCLUDED.shares, t.shares),
        total_interactions = coalesce(EXCLUDED.total_interactions, t.total_interactions), replies = coalesce(EXCLUDED.replies, t.replies),
        profile_visits = coalesce(EXCLUDED.profile_visits, t.profile_visits), follows = coalesce(EXCLUDED.follows, t.follows),
        avg_watch_ms = coalesce(EXCLUDED.avg_watch_ms, t.avg_watch_ms), captured_at = now();
    END IF;
    nm := nm + 1;
  END LOOP;

  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, rows) VALUES ('instagram', clock_timestamp(), true, p_from, p_to, na + nm);
  UPDATE f360.measurement_sources SET config_status = 'CONFIGURED', updated_by_name = 'f360-instagram', updated_at = now()
    WHERE key = 'instagram' AND config_status <> 'CONFIGURED';   -- the first successful read proves the permissions
  RETURN jsonb_build_object('ok', true, 'days', na, 'media', nm);
END $$;

-- Is this order's last touch Instagram without paying for it? (Instagram only: Facebook is not mixed in.)
CREATE FUNCTION f360.is_instagram_organic(p_source_type text, p_utm_source text, p_utm_medium text, p_referrer text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN f360.classify_channel_v1(p_source_type, p_utm_source, p_utm_medium, p_referrer) = 'Meta (UTM no pagado)' THEN lower(coalesce(p_utm_source, '')) IN ('ig', 'instagram')
    WHEN f360.classify_channel_v1(p_source_type, p_utm_source, p_utm_medium, p_referrer) = 'Instagram / Facebook orgánico' THEN coalesce(p_referrer, '') ~* 'instagram'
    ELSE false END
$$;

-- Growth → Instagram (operator+). Daily account metrics, content by type, and the paid orders whose last touch was Instagram.
CREATE FUNCTION public.f360_growth_instagram(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
  d_to date := coalesce(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date);
  d_from date := coalesce(p_from, d_to - 29);
  f timestamptz; t timestamptz; src f360.measurement_sources; last_ok timestamptz; last_run f360.measurement_runs; res jsonb;
BEGIN
  IF d_from > d_to THEN RAISE EXCEPTION 'El periodo no es válido.'; END IF;
  IF d_to - d_from > 731 THEN RAISE EXCEPTION 'El periodo máximo es de dos años.'; END IF;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  SELECT * INTO src FROM f360.measurement_sources WHERE key = 'instagram';
  SELECT max(finished_at) INTO last_ok FROM f360.measurement_runs WHERE source_key = 'instagram' AND ok;
  SELECT * INTO last_run FROM f360.measurement_runs WHERE source_key = 'instagram' ORDER BY id DESC LIMIT 1;

  WITH ig_orders AS (
    SELECT o.woo_order_id, o.market, (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date AS day, o.net_product,
           CASE o.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END AS currency,
           a.utm_content,
           (SELECT m.media_id FROM f360.ig_media m WHERE a.utm_content IS NOT NULL AND (m.media_id = a.utm_content OR m.shortcode = a.utm_content) LIMIT 1) AS media_id
    FROM f360.commerce_orders o
    JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= f AND o.occurred_at < t
      AND f360.is_instagram_organic(a.source_type, a.utm_source, a.utm_medium, a.referrer_host)
  ), latest AS (
    SELECT DISTINCT ON (mm.media_id) mm.* FROM f360.ig_media_metrics mm ORDER BY mm.media_id, mm.captured_on DESC
  ), media AS (
    SELECT m.media_id, m.kind, m.posted_at, m.permalink, left(m.caption, 140) AS caption, l.captured_on, l.reach, l.views, l.likes, l.comments, l.saves, l.shares,
           l.total_interactions, l.replies, l.profile_visits, l.follows, l.avg_watch_ms,
           (SELECT count(*) FROM ig_orders io WHERE io.media_id = m.media_id) AS paid_orders_with_evidence
    FROM f360.ig_media m LEFT JOIN latest l ON l.media_id = m.media_id
    WHERE m.posted_at >= f AND m.posted_at < t
  ), days AS (
    SELECT g::date AS day FROM generate_series(d_from, d_to, interval '1 day') g
  )
  SELECT jsonb_build_object(
    'from', d_from, 'to', d_to, 'generated_at', now(),
    'source', jsonb_build_object('config_status', src.config_status, 'last_success_at', last_ok,
       'last_error', CASE WHEN last_run.ok IS FALSE THEN last_run.error END, 'last_try_at', last_run.started_at, 'notes', src.notes),
    'daily', (SELECT coalesce(jsonb_agg(jsonb_build_object('date', d.day, 'reach', a.reach, 'views', a.views, 'profile_views', a.profile_views,
         'website_clicks', a.website_clicks, 'accounts_engaged', a.accounts_engaged, 'total_interactions', a.total_interactions, 'follows', a.follows,
         'unfollows', a.unfollows, 'followers_count', a.followers_count,
         'published', jsonb_build_object('post', (SELECT count(*) FROM media WHERE kind = 'post' AND (posted_at AT TIME ZONE 'America/Mexico_City')::date = d.day),
                                         'carousel', (SELECT count(*) FROM media WHERE kind = 'carousel' AND (posted_at AT TIME ZONE 'America/Mexico_City')::date = d.day),
                                         'reel', (SELECT count(*) FROM media WHERE kind = 'reel' AND (posted_at AT TIME ZONE 'America/Mexico_City')::date = d.day),
                                         'story', (SELECT count(*) FROM media WHERE kind = 'story' AND (posted_at AT TIME ZONE 'America/Mexico_City')::date = d.day)),
         'ig_paid_orders', (SELECT count(*) FROM ig_orders io WHERE io.day = d.day)) ORDER BY d.day), '[]')
       FROM days d LEFT JOIN f360.ig_account_daily a ON a.date = d.day),
    'by_kind', (SELECT coalesce(jsonb_agg(jsonb_build_object('kind', k.kind, 'count', k.n, 'with_metrics', k.wm, 'reach_avg', k.reach_avg,
         'views_avg', k.views_avg, 'saves', k.saves, 'shares', k.shares) ORDER BY k.kind), '[]')
       FROM (SELECT kind, count(*) AS n, count(captured_on) AS wm, round(avg(reach)) AS reach_avg, round(avg(views)) AS views_avg,
                    sum(saves) AS saves, sum(shares) AS shares FROM media GROUP BY kind) k),
    'media', (SELECT coalesce(jsonb_agg(to_jsonb(m) ORDER BY m.posted_at DESC), '[]') FROM (SELECT * FROM media ORDER BY posted_at DESC LIMIT 200) m),
    'sales', jsonb_build_object(
       'paid_orders', (SELECT count(*) FROM ig_orders),
       'by_market', (SELECT coalesce(jsonb_agg(jsonb_build_object('market', market, 'currency', currency, 'paid_orders', n, 'revenue', rev) ORDER BY market), '[]')
                     FROM (SELECT market, currency, count(*) AS n, sum(net_product) AS rev FROM ig_orders GROUP BY market, currency) q),
       'with_post_evidence', (SELECT count(*) FROM ig_orders WHERE media_id IS NOT NULL),
       'without_post', (SELECT count(*) FROM ig_orders WHERE media_id IS NULL),
       'rule', 'Venta pagada cuyo último clic vino de Instagram sin anuncio (enlace de la bio, historias o publicaciones). Facebook no se suma. Una venta se liga a una publicación solo si el enlace del pedido trae su identificador (utm_content).'),
    'limitations', jsonb_build_array(
       'Instagram no pasa el identificador de la publicación en los enlaces de la bio ni de las historias: esas ventas se ven como "Instagram" sin publicación.',
       'Las historias solo se pueden leer mientras están publicadas (24 horas); las que no se capturaron se pierden.',
       'El número de seguidores no tiene historial en la API: solo existe desde el día en que se empezó a capturar.',
       'Las métricas de cada publicación son acumuladas; se guarda una foto por día.',
       'Último clic: una clienta que vio una publicación y regresó después por Google o directo no le suma a Instagram.')
  ) INTO res;
  RETURN res;
END $$;

-- ── Clarity (minimal daily capture; no screen yet) ────────────────────────────────────────────────────────────────────────
CREATE TABLE f360.clarity_snapshots (
  id            bigserial PRIMARY KEY,
  captured_at   timestamptz NOT NULL DEFAULT now(),
  window_end    date NOT NULL,                                           -- CDMX day of the capture; the window is the 24 h before it
  num_days      smallint NOT NULL CHECK (num_days BETWEEN 1 AND 3),
  dimension     text NOT NULL CHECK (dimension ~ '^[A-Za-z ]{0,40}$'),   -- '' = no breakdown; 'Source', 'Device', 'URL', …
  metric_name   text NOT NULL CHECK (metric_name ~ '^[A-Za-z]{2,60}$'),
  information   jsonb NOT NULL CHECK (jsonb_typeof(information) = 'array'),
  UNIQUE (window_end, num_days, dimension, metric_name)
);
COMMENT ON TABLE f360.clarity_snapshots IS 'Growth P0-C: raw Clarity export API answers (aggregates, no personal data), one per capture day × breakdown × metric.';

CREATE FUNCTION public.f360_clarity_import(p_window_end date, p_num_days int, p_dimension text, p_metrics jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE x jsonb; n int := 0;
BEGIN
  IF p_window_end IS NULL OR p_window_end > (now() AT TIME ZONE 'America/Mexico_City')::date + 1 OR p_window_end < '2026-01-01' THEN RAISE EXCEPTION 'Fecha no válida.'; END IF;
  IF p_num_days NOT BETWEEN 1 AND 3 THEN RAISE EXCEPTION 'Clarity solo da 1 a 3 días.'; END IF;
  IF jsonb_typeof(p_metrics) IS DISTINCT FROM 'array' OR jsonb_array_length(p_metrics) > 50 THEN RAISE EXCEPTION 'Respuesta no válida.'; END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(p_metrics) LOOP
    IF jsonb_array_length(x->'information') > 2000 THEN RAISE EXCEPTION 'Demasiadas filas en %.', x->>'metricName'; END IF;
    INSERT INTO f360.clarity_snapshots (window_end, num_days, dimension, metric_name, information)
      VALUES (p_window_end, p_num_days, coalesce(p_dimension, ''), x->>'metricName', x->'information')
    ON CONFLICT (window_end, num_days, dimension, metric_name) DO UPDATE SET information = EXCLUDED.information, captured_at = now();
    n := n + 1;
  END LOOP;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, rows)
    VALUES ('clarity', clock_timestamp(), true, p_window_end - p_num_days, p_window_end, n);
  UPDATE f360.measurement_sources SET config_status = 'CONFIGURED', updated_by_name = 'f360-clarity', updated_at = now()
    WHERE key = 'clarity' AND config_status <> 'CONFIGURED';
  RETURN jsonb_build_object('ok', true, 'metrics', n);
END $$;

-- ── Schedules (same vault secrets as f360-meta-spend; the functions answer 503 and spend no API call without their token) ──
CREATE FUNCTION f360.growth_source_tick(p_function text, p_body jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  IF p_function NOT IN ('f360-instagram', 'f360-clarity') THEN RETURN; END IF;
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/' || p_function) INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ ('/functions/v1/' || p_function || '$') THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url, headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := p_body, timeout_milliseconds := 55000);
END $$;
-- Instagram: account + posts daily 09:00 UTC (03:00 CDMX); stories every 4 h (they disappear after 24 h).
SELECT cron.schedule('f360-instagram', '0 9 * * *', $$SELECT f360.growth_source_tick('f360-instagram', '{"action":"daily"}'::jsonb)$$);
SELECT cron.schedule('f360-instagram-stories', '15 */4 * * *', $$SELECT f360.growth_source_tick('f360-instagram', '{"action":"stories"}'::jsonb)$$);
-- Clarity: once a day 06:10 UTC (00:10 CDMX), last 24 h, 3 calls (Source, Device, URL) of the 10 allowed per day.
SELECT cron.schedule('f360-clarity', '10 6 * * *', $$SELECT f360.growth_source_tick('f360-clarity', '{"action":"daily"}'::jsonb)$$);

-- ── Permissions ───────────────────────────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE f360.ig_account_daily ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.ig_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.ig_media_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.clarity_snapshots ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.ig_account_daily, f360.ig_media, f360.ig_media_metrics, f360.clarity_snapshots FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.ig_account_daily, f360.ig_media, f360.ig_media_metrics, f360.clarity_snapshots TO service_role;
GRANT USAGE ON SEQUENCE f360.clarity_snapshots_id_seq TO service_role;
REVOKE ALL ON FUNCTION f360.ig_int(jsonb, text), f360.is_instagram_organic(text, text, text, text), f360.growth_source_tick(text, jsonb),
  public.f360_instagram_import(text, date, date, jsonb, jsonb), public.f360_clarity_import(date, int, text, jsonb),
  public.f360_growth_instagram(date, date), public.f360_measurement_run_failed(text, date, date, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_instagram_import(text, date, date, jsonb, jsonb), public.f360_clarity_import(date, int, text, jsonb),
  public.f360_measurement_run_failed(text, date, date, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_growth_instagram(date, date) TO authenticated, service_role;
