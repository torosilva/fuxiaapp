-- Fuxia 360 · PRODUCCIÓN · Growth P0 (Mario 2026-10-27: "pasa todo a produccion").
-- Migraciones 20261104000100 (Instagram orgánico + Clarity diario) y 20261104000200 (registro de experimentos, 06_EXPERIMENTS)
-- VERBATIM, en staging desde 2026-10-27 (pruebas G1–G8 40/40, funciones 8+6, e2e).
-- Revisado contra prod 2026-10-27: measurement_sources_key_check y f360_measurement_run_failed son los de I5 paso 1 (fx_rates) y
-- se reemplazan agregando 'instagram' y 'clarity'; Vault f360_sync_url/secret existe. Solo agrega tablas, funciones y 3 crons.
-- No toca ventas, gasto, pedidos, inventario ni campañas.
-- Reversión: supabase/rollbacks/20261104000200_…down.sql y luego 20261104000100_…down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261104000100', '20261104000200'))
     OR to_regclass('f360.ig_media') IS NOT NULL OR to_regclass('f360.growth_experiments') IS NOT NULL THEN
    RAISE EXCEPTION 'GP0 PRE: ya está instalada'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000100') THEN
    RAISE EXCEPTION 'GP0 PRE: falta FX diario (20261024000100)'; END IF;
  IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name IN ('f360_sync_url', 'f360_sync_secret')) <> 2 THEN RAISE EXCEPTION 'GP0 PRE: faltan secretos de Vault'; END IF;
END $$;

-- ═════ 20261104000100_f360_growth_instagram_clarity ═════
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261104000100', 'f360_growth_instagram_clarity', '{}');

-- ═════ 20261104000200_f360_growth_experiments ═════
-- Fuxia 360 · Growth P0-B Registro de experimentos (Mario 2026-10-27, solo staging). Implements docs/fuxia360/growth/06_EXPERIMENTS.md
-- as designed (table §2, states §3, security §4, measurement §5). ADDITIVE: 2 tables + RPCs; no change to existing objects.
-- Points the design left open, closed here (flagged in the delivery doc):
--   · "fijados antes de comenzar" (Mario): hypothesis, responsible, budget, KPI, thresholds, market, campaigns and dates are
--     frozen from APPROVED (the design froze thresholds from RUNNING); any change after approval is refused → new experiment;
--   · proposed_by / responsible: who recommended it and who executes it (mario, carolina, goyo, agencia, ia, otro), so every
--     party is judged with the same rules; the track record per party is part of the list;
--   · KPIs measurable today only from PAID Woo orders and Meta spend: paid_orders, net_revenue, cost_per_paid_order. Others in
--     §5 (favorites, ATC, …) are refused until their data exists — never a number the server cannot compute;
--   · verdict is not free: WINNER only if the success threshold was met with the minimum sample, LOSER only if the kill
--     threshold was met; anything else is INCONCLUSIVE. The result is computed by the server at closing and stored as a snapshot;
--   · evidence is labelled: attribution OBSERVED (last click of the order) or market before/after; never "causal" (no control group).
-- Rollback: supabase/rollbacks/20261104000200_f360_growth_experiments.down.sql

CREATE SEQUENCE f360.growth_experiment_seq;

CREATE TABLE f360.growth_experiments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code              text NOT NULL UNIQUE,
  name              text NOT NULL CHECK (length(btrim(name)) BETWEEN 3 AND 140),
  hypothesis        text NOT NULL CHECK (length(btrim(hypothesis)) BETWEEN 20 AND 2000),
  market            text NOT NULL CHECK (market IN ('MX', 'CO', 'ROW', 'ALL')),
  channel           text CHECK (channel IS NULL OR length(channel) <= 60),
  audience          text CHECK (audience IS NULL OR length(audience) <= 300),
  product_key       text CHECK (product_key IS NULL OR product_key ~ '^F360-[A-Z0-9-]{1,40}$'),
  product_id        uuid REFERENCES f360.products(id) ON DELETE RESTRICT,
  creative_ref      text CHECK (creative_ref IS NULL OR length(creative_ref) <= 200),
  primary_variable  text NOT NULL CHECK (length(btrim(primary_variable)) BETWEEN 3 AND 200),
  proposed_by       text NOT NULL CHECK (proposed_by IN ('mario', 'carolina', 'goyo', 'agencia', 'ia', 'otro')),
  responsible       text NOT NULL CHECK (responsible IN ('mario', 'carolina', 'goyo', 'agencia', 'ia', 'otro')),
  responsible_note  text CHECK (responsible_note IS NULL OR length(responsible_note) <= 140),
  start_date        date,
  end_date          date,                                                 -- planned end = review date
  budget            numeric(14,2) CHECK (budget IS NULL OR budget >= 0),
  budget_currency   text CHECK (budget_currency IS NULL OR budget_currency IN ('MXN', 'COP', 'USD')),
  primary_kpi       text NOT NULL CHECK (primary_kpi IN ('paid_orders', 'net_revenue', 'cost_per_paid_order')),
  secondary_kpis    text[] NOT NULL DEFAULT '{}',
  success_threshold jsonb,
  kill_threshold    jsonb,
  campaign_ids      text[] NOT NULL DEFAULT '{}' CHECK (array_length(campaign_ids, 1) IS NULL OR array_length(campaign_ids, 1) <= 30),
  utm_campaign      text CHECK (utm_campaign IS NULL OR length(utm_campaign) <= 200),
  status            text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'APPROVED', 'RUNNING', 'WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED')),
  verdict           text CHECK (verdict IS NULL OR verdict IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED')),   -- kept after ARCHIVED
  result            jsonb,
  learning          text CHECK (learning IS NULL OR length(learning) <= 2000),
  decision          text CHECK (decision IS NULL OR decision IN ('SCALE', 'ITERATE', 'KILL', 'NONE')),
  stop_reason       text CHECK (stop_reason IS NULL OR length(stop_reason) <= 500),
  created_by        uuid NOT NULL,
  created_by_name   text NOT NULL,
  approved_by       uuid,
  approved_by_name  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  approved_at       timestamptz,
  started_at        timestamptz,
  ended_at          timestamptz,
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
  CHECK ((budget IS NULL) = (budget_currency IS NULL))
);
COMMENT ON TABLE f360.growth_experiments IS 'Growth P0-B (06_EXPERIMENTS.md): hypothesis → approval → run → verdict from PAID Woo orders. Nothing is deleted.';

CREATE TABLE f360.growth_experiment_changes (
  id            bigserial PRIMARY KEY,
  experiment_id uuid NOT NULL REFERENCES f360.growth_experiments(id) ON DELETE RESTRICT,
  from_status   text,
  to_status     text,
  field         text,
  old           jsonb,
  new           jsonb,
  actor         uuid,
  actor_name    text NOT NULL,
  reason        text CHECK (reason IS NULL OR length(reason) <= 500),
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX growth_experiment_changes_exp_idx ON f360.growth_experiment_changes (experiment_id, id);

CREATE FUNCTION f360.growth_experiment_changes_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'La bitácora de experimentos no se edita ni se borra.'; END $$;
CREATE TRIGGER growth_experiment_changes_no_update BEFORE UPDATE OR DELETE ON f360.growth_experiment_changes
  FOR EACH ROW EXECUTE FUNCTION f360.growth_experiment_changes_append_only();
CREATE TRIGGER growth_experiments_no_delete BEFORE DELETE ON f360.growth_experiments
  FOR EACH ROW EXECUTE FUNCTION f360.growth_experiment_changes_append_only();

-- Threshold = {"op": ">=" | "<=", "value": number ≥ 0, "min_sample": integer ≥ 1} (the KPI is the experiment's primary KPI).
CREATE FUNCTION f360.growth_threshold_error(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR jsonb_typeof(p) <> 'object' THEN 'falta el umbral'
    WHEN p->>'op' NOT IN ('>=', '<=') THEN 'el operador debe ser >= o <='
    WHEN jsonb_typeof(p->'value') <> 'number' OR (p->>'value')::numeric < 0 THEN 'el valor debe ser un número ≥ 0'
    WHEN jsonb_typeof(p->'min_sample') <> 'number' OR (p->>'min_sample')::numeric < 1 OR (p->>'min_sample')::numeric <> trunc((p->>'min_sample')::numeric) THEN 'la muestra mínima debe ser un entero ≥ 1'
    WHEN EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN ('op', 'value', 'min_sample')) THEN 'el umbral solo lleva op, value y min_sample'
  END
$$;

-- Server-side measurement (never from the client). Window = start_date .. the earliest of planned end, closing day and today.
CREATE FUNCTION f360.growth_experiment_measure(e f360.growth_experiments) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  d_from date := e.start_date; d_to date; len int; f timestamptz; t timestamptz; bf timestamptz;
  scoped boolean := cardinality(e.campaign_ids) > 0 OR e.utm_campaign IS NOT NULL;
  m_orders int; m_rev jsonb; b_orders int; s_orders int; s_rev jsonb; s_rev_n numeric; spend numeric; spend_cur_ok boolean; kpi numeric; sample int;
  succ boolean; kill boolean; cur text := CASE e.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' WHEN 'MX' THEN 'MXN' END;
BEGIN
  IF d_from IS NULL THEN RETURN jsonb_build_object('status', 'SIN_FECHA'); END IF;
  d_to := least(coalesce(e.end_date, today), coalesce((e.ended_at AT TIME ZONE 'America/Mexico_City')::date, today), today);   -- the review date fixed at approval; earlier if stopped
  IF d_to < d_from THEN RETURN jsonb_build_object('status', 'NO_EMPEZADO', 'from', d_from); END IF;
  len := d_to - d_from + 1;
  f := d_from::timestamp AT TIME ZONE 'America/Mexico_City'; t := (d_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  bf := (d_from - len)::timestamp AT TIME ZONE 'America/Mexico_City';

  WITH o AS (
    SELECT o.market, o.net_product, o.occurred_at, nullif(coalesce(a.utm_id, a.utm_campaign), '') AS campaign_key, a.utm_campaign
    FROM f360.commerce_orders o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.status_class = 'countable' AND o.occurred_at >= bf AND o.occurred_at < t
      AND (e.market = 'ALL' OR o.market = e.market)
  )
  SELECT count(*) FILTER (WHERE occurred_at >= f),
         (SELECT coalesce(jsonb_object_agg(c, v), '{}') FROM (SELECT CASE o2.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END c, sum(o2.net_product) v
            FROM o o2 WHERE o2.occurred_at >= f GROUP BY 1) q),
         count(*) FILTER (WHERE occurred_at < f),
         count(*) FILTER (WHERE occurred_at >= f AND scoped AND (campaign_key = ANY (e.campaign_ids) OR (e.utm_campaign IS NOT NULL AND utm_campaign = e.utm_campaign))),
         (SELECT coalesce(jsonb_object_agg(c, v), '{}') FROM (SELECT CASE o2.market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END c, sum(o2.net_product) v
            FROM o o2 WHERE o2.occurred_at >= f AND scoped AND (o2.campaign_key = ANY (e.campaign_ids) OR (e.utm_campaign IS NOT NULL AND o2.utm_campaign = e.utm_campaign)) GROUP BY 1) q)
    INTO m_orders, m_rev, b_orders, s_orders, s_rev FROM o;

  IF cardinality(e.campaign_ids) > 0 THEN
    SELECT sum(sd.spend), bool_and(sd.currency = 'MXN') INTO spend, spend_cur_ok FROM f360.marketing_spend_daily sd
      WHERE sd.platform = 'meta' AND sd.campaign_id = ANY (e.campaign_ids) AND sd.date >= d_from AND sd.date <= d_to AND (e.market = 'ALL' OR sd.market = e.market);
  END IF;

  sample := CASE WHEN scoped THEN s_orders ELSE m_orders END;
  s_rev_n := CASE WHEN cur IS NULL THEN NULL ELSE ((CASE WHEN scoped THEN s_rev ELSE m_rev END)->>cur)::numeric END;
  kpi := CASE e.primary_kpi
    WHEN 'paid_orders' THEN sample
    WHEN 'net_revenue' THEN coalesce(s_rev_n, CASE WHEN cur IS NOT NULL THEN 0 END)                    -- ALL markets: not summed across currencies
    WHEN 'cost_per_paid_order' THEN CASE WHEN spend_cur_ok AND s_orders > 0 THEN round(spend / s_orders, 2) END END;
  succ := kpi IS NOT NULL AND sample >= (e.success_threshold->>'min_sample')::int
          AND CASE e.success_threshold->>'op' WHEN '>=' THEN kpi >= (e.success_threshold->>'value')::numeric ELSE kpi <= (e.success_threshold->>'value')::numeric END;
  kill := kpi IS NOT NULL AND sample >= (e.kill_threshold->>'min_sample')::int
          AND CASE e.kill_threshold->>'op' WHEN '>=' THEN kpi >= (e.kill_threshold->>'value')::numeric ELSE kpi <= (e.kill_threshold->>'value')::numeric END;
  -- cost per sale with spend and zero attributed sales: the kill side of a "<=" cost goal is met once spend exceeds the kill value
  IF e.primary_kpi = 'cost_per_paid_order' AND kpi IS NULL AND spend_cur_ok AND coalesce(s_orders, 0) = 0 AND e.kill_threshold->>'op' = '>=' AND spend >= (e.kill_threshold->>'value')::numeric THEN
    kill := true;
  END IF;

  RETURN jsonb_build_object(
    'status', 'OK', 'from', d_from, 'to', d_to, 'days', len, 'measured_at', now(),
    'kpi', e.primary_kpi, 'kpi_value', kpi, 'kpi_currency', CASE WHEN e.primary_kpi = 'net_revenue' THEN cur WHEN e.primary_kpi = 'cost_per_paid_order' THEN 'MXN' END,
    'sample', sample, 'success_met', coalesce(succ, false), 'kill_met', coalesce(kill, false),
    'market_paid_orders', m_orders, 'market_revenue', m_rev, 'baseline_paid_orders', b_orders,
    'baseline_period', jsonb_build_array(d_from - len, d_from - 1),
    'attributed_paid_orders', CASE WHEN scoped THEN s_orders END, 'attributed_revenue', CASE WHEN scoped THEN s_rev END,
    'spend_mxn', spend, 'spend_status', CASE WHEN cardinality(e.campaign_ids) = 0 THEN 'SIN_CAMPAÑAS' WHEN spend IS NULL THEN 'SIN_DATOS' WHEN NOT spend_cur_ok THEN 'OTRA_MONEDA' ELSE 'OK' END,
    'evidence', CASE WHEN scoped THEN 'atribucion_observada' ELSE 'antes_despues_mercado' END,
    'evidence_note', CASE WHEN scoped
      THEN 'Ventas pagadas cuyo último clic fue la campaña del experimento (atribución observada). No demuestra causalidad: no hay grupo de control.'
      ELSE 'Ventas pagadas del mercado durante el experimento contra el mismo número de días justo antes. Es una comparación antes/después: no demuestra causalidad.' END,
    'source', 'Pedidos pagados de WooCommerce (f360.commerce_orders) · gasto de Meta (f360.marketing_spend_daily)');
END $$;

-- Writable fields while DRAFT (create when p_id IS NULL). Identity from the session, never the payload.
CREATE FUNCTION public.f360_experiment_save(p_id uuid, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); e f360.growth_experiments; n f360.growth_experiments; k text; v_id uuid;
  allowed text[] := ARRAY['name', 'hypothesis', 'market', 'channel', 'audience', 'product_key', 'creative_ref', 'primary_variable', 'proposed_by', 'responsible',
    'responsible_note', 'start_date', 'end_date', 'budget', 'budget_currency', 'primary_kpi', 'success_threshold', 'kill_threshold', 'campaign_ids', 'utm_campaign'];
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Datos no válidos.'; END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF NOT k = ANY (allowed) THEN RAISE EXCEPTION 'Campo no permitido: %', k; END IF;
  END LOOP;
  IF p ? 'success_threshold' AND p->'success_threshold' <> 'null'::jsonb AND f360.growth_threshold_error(p->'success_threshold') IS NOT NULL THEN
    RAISE EXCEPTION 'Meta de éxito: %', f360.growth_threshold_error(p->'success_threshold'); END IF;
  IF p ? 'kill_threshold' AND p->'kill_threshold' <> 'null'::jsonb AND f360.growth_threshold_error(p->'kill_threshold') IS NOT NULL THEN
    RAISE EXCEPTION 'Criterio para cancelar: %', f360.growth_threshold_error(p->'kill_threshold'); END IF;
  IF p ? 'campaign_ids' AND (jsonb_typeof(p->'campaign_ids') <> 'array' OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(p->'campaign_ids') c WHERE c !~ '^\d{5,25}$')) THEN
    RAISE EXCEPTION 'Las campañas son IDs numéricos de Meta.'; END IF;

  IF p_id IS NULL THEN
    INSERT INTO f360.growth_experiments (code, name, hypothesis, market, primary_variable, proposed_by, responsible, primary_kpi, created_by, created_by_name)
    VALUES ('EXP-' || to_char(now() AT TIME ZONE 'America/Mexico_City', 'YYYY') || '-' || lpad(nextval('f360.growth_experiment_seq')::text, 3, '0'),
            p->>'name', p->>'hypothesis', p->>'market', p->>'primary_variable', p->>'proposed_by', p->>'responsible', p->>'primary_kpi', r.auth_user_id, r.display_name)
    RETURNING id INTO v_id;
    INSERT INTO f360.growth_experiment_changes (experiment_id, to_status, actor, actor_name, reason) VALUES (v_id, 'DRAFT', r.auth_user_id, r.display_name, 'creado');
  ELSE
    v_id := p_id;
  END IF;
  SELECT * INTO e FROM f360.growth_experiments WHERE id = v_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Experimento no encontrado.'; END IF;
  IF e.status <> 'DRAFT' THEN RAISE EXCEPTION 'Solo se edita en borrador. Después de aprobado no cambia nada: crea un experimento nuevo.'; END IF;

  n := jsonb_populate_record(e, p - 'campaign_ids');
  IF p ? 'campaign_ids' THEN n.campaign_ids := ARRAY(SELECT jsonb_array_elements_text(p->'campaign_ids')); END IF;
  FOR k IN SELECT jsonb_object_keys(p) LOOP
    IF to_jsonb(e)->k IS DISTINCT FROM to_jsonb(n)->k AND p_id IS NOT NULL THEN
      INSERT INTO f360.growth_experiment_changes (experiment_id, from_status, to_status, field, old, new, actor, actor_name)
        VALUES (e.id, 'DRAFT', 'DRAFT', k, to_jsonb(e)->k, to_jsonb(n)->k, r.auth_user_id, r.display_name);
    END IF;
  END LOOP;
  UPDATE f360.growth_experiments SET name = n.name, hypothesis = n.hypothesis, market = n.market, channel = n.channel, audience = n.audience,
      product_key = n.product_key, product_id = (SELECT id FROM f360.products WHERE code = n.product_key), creative_ref = n.creative_ref,
      primary_variable = n.primary_variable, proposed_by = n.proposed_by, responsible = n.responsible, responsible_note = n.responsible_note,
      start_date = n.start_date, end_date = n.end_date, budget = n.budget, budget_currency = n.budget_currency, primary_kpi = n.primary_kpi,
      success_threshold = n.success_threshold, kill_threshold = n.kill_threshold, campaign_ids = n.campaign_ids, utm_campaign = n.utm_campaign, updated_at = now()
    WHERE id = e.id;
  RETURN jsonb_build_object('ok', true, 'id', e.id, 'code', e.code);
END $$;

CREATE FUNCTION public.f360_experiment_transition(p_id uuid, p_to text, p_learning text DEFAULT NULL, p_decision text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); e f360.growth_experiments; res jsonb; today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  owner_only boolean := p_to IN ('APPROVED', 'WINNER', 'LOSER', 'INCONCLUSIVE', 'ARCHIVED');
BEGIN
  IF owner_only THEN PERFORM f360.require_role('owner'); END IF;
  SELECT * INTO e FROM f360.growth_experiments WHERE id = p_id FOR UPDATE;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Experimento no encontrado.'; END IF;
  IF NOT ((e.status = 'DRAFT' AND p_to = 'APPROVED') OR (e.status = 'APPROVED' AND p_to IN ('RUNNING', 'STOPPED'))
       OR (e.status = 'RUNNING' AND p_to IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED'))
       OR (e.status IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED') AND p_to = 'ARCHIVED')) THEN
    RAISE EXCEPTION 'No se puede pasar de % a %.', e.status, p_to;
  END IF;

  IF p_to = 'APPROVED' THEN   -- everything that judges the experiment is fixed here, before it starts
    IF e.start_date IS NULL OR e.end_date IS NULL THEN RAISE EXCEPTION 'Falta la fecha de inicio o la de revisión.'; END IF;
    IF e.budget IS NULL THEN RAISE EXCEPTION 'Falta el presupuesto (puede ser 0).'; END IF;
    IF f360.growth_threshold_error(e.success_threshold) IS NOT NULL THEN RAISE EXCEPTION 'Meta de éxito: %', f360.growth_threshold_error(e.success_threshold); END IF;
    IF f360.growth_threshold_error(e.kill_threshold) IS NOT NULL THEN RAISE EXCEPTION 'Criterio para cancelar: %', f360.growth_threshold_error(e.kill_threshold); END IF;
    IF e.primary_kpi = 'cost_per_paid_order' AND cardinality(e.campaign_ids) = 0 THEN RAISE EXCEPTION 'El costo por venta necesita las campañas de Meta del experimento.'; END IF;
    IF e.primary_kpi = 'net_revenue' AND e.market = 'ALL' THEN RAISE EXCEPTION 'La venta en dinero se mide por mercado (no se suman monedas).'; END IF;
    UPDATE f360.growth_experiments SET status = 'APPROVED', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = now(), updated_at = now() WHERE id = e.id;
  ELSIF p_to = 'RUNNING' THEN
    IF e.start_date > today THEN RAISE EXCEPTION 'Empieza el %: todavía no corre.', e.start_date; END IF;
    UPDATE f360.growth_experiments SET status = 'RUNNING', started_at = now(), updated_at = now() WHERE id = e.id;
  ELSIF p_to IN ('WINNER', 'LOSER', 'INCONCLUSIVE') THEN
    IF length(btrim(coalesce(p_learning, ''))) < 10 THEN RAISE EXCEPTION 'Escribe qué aprendimos.'; END IF;
    e.ended_at := now();
    res := f360.growth_experiment_measure(e);
    IF p_to = 'WINNER' AND NOT (res->>'success_met')::boolean THEN RAISE EXCEPTION 'No cumplió la meta de éxito con la muestra mínima: el resultado es INCONCLUSIVE o LOSER.'; END IF;
    IF p_to = 'LOSER' AND NOT (res->>'kill_met')::boolean THEN RAISE EXCEPTION 'No llegó al criterio para cancelar: el resultado es INCONCLUSIVE.'; END IF;
    IF p_to = 'INCONCLUSIVE' AND (res->>'success_met')::boolean AND NOT (res->>'kill_met')::boolean THEN RAISE EXCEPTION 'Cumplió la meta de éxito: ciérralo como WINNER.'; END IF;
    UPDATE f360.growth_experiments SET status = p_to, verdict = p_to, result = res, learning = btrim(p_learning), ended_at = e.ended_at, updated_at = now() WHERE id = e.id;
  ELSIF p_to = 'STOPPED' THEN
    IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'Escribe por qué se detiene.'; END IF;
    e.ended_at := now();
    UPDATE f360.growth_experiments SET status = 'STOPPED', verdict = 'STOPPED', stop_reason = btrim(p_reason), ended_at = e.ended_at,
        result = CASE WHEN e.status = 'RUNNING' THEN f360.growth_experiment_measure(e) END, learning = nullif(btrim(coalesce(p_learning, '')), ''), updated_at = now()
      WHERE id = e.id;
  ELSIF p_to = 'ARCHIVED' THEN
    IF p_decision IS NULL OR p_decision NOT IN ('SCALE', 'ITERATE', 'KILL', 'NONE') THEN RAISE EXCEPTION 'Falta la decisión: escalar, ajustar, matar o ninguna.'; END IF;
    UPDATE f360.growth_experiments SET status = 'ARCHIVED', decision = p_decision, updated_at = now() WHERE id = e.id;
  END IF;
  INSERT INTO f360.growth_experiment_changes (experiment_id, from_status, to_status, actor, actor_name, reason, new)
    VALUES (e.id, e.status, p_to, r.auth_user_id, r.display_name, nullif(btrim(coalesce(p_reason, '')), ''),
            CASE WHEN p_decision IS NOT NULL THEN jsonb_build_object('decision', p_decision) END);
  RETURN jsonb_build_object('ok', true, 'id', e.id, 'status', p_to);
END $$;

-- List (operator+): closed results and the track record per party first, then open experiments with a live measurement.
CREATE FUNCTION public.f360_experiments_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN jsonb_build_object(
    'generated_at', now(), 'can_approve', r.role = 'owner',
    'track_record', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'party'), '[]') FROM (
       SELECT jsonb_build_object('party', p.party, 'proposed', count(*) FILTER (WHERE e.proposed_by = p.party), 'responsible', count(*) FILTER (WHERE e.responsible = p.party),
         'winner', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'WINNER'),
         'loser', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'LOSER'),
         'inconclusive', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'INCONCLUSIVE'),
         'stopped', count(*) FILTER (WHERE e.proposed_by = p.party AND e.verdict = 'STOPPED'),
         'open', count(*) FILTER (WHERE e.proposed_by = p.party AND e.status IN ('DRAFT', 'APPROVED', 'RUNNING')),
         'budget_mxn', sum(e.budget) FILTER (WHERE e.proposed_by = p.party AND e.budget_currency = 'MXN' AND e.status <> 'DRAFT')) AS x
       FROM (VALUES ('mario'), ('carolina'), ('goyo'), ('agencia'), ('ia'), ('otro')) p(party)
       LEFT JOIN f360.growth_experiments e ON e.proposed_by = p.party OR e.responsible = p.party
       GROUP BY p.party HAVING count(e.id) > 0) q),
    'experiments', (SELECT coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object(
         'live', CASE WHEN e.status = 'RUNNING' THEN f360.growth_experiment_measure(e) END,
         'history', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', c.at, 'from', c.from_status, 'to', c.to_status, 'field', c.field, 'old', c.old, 'new', c.new,
                       'by', c.actor_name, 'reason', c.reason) ORDER BY c.id), '[]') FROM f360.growth_experiment_changes c WHERE c.experiment_id = e.id))
       ORDER BY CASE WHEN e.status IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED') THEN 0 ELSE 1 END, coalesce(e.ended_at, e.created_at) DESC), '[]')
       FROM f360.growth_experiments e));
END $$;

ALTER TABLE f360.growth_experiments ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.growth_experiment_changes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.growth_experiments, f360.growth_experiment_changes FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON f360.growth_experiments, f360.growth_experiment_changes TO service_role;
REVOKE ALL ON SEQUENCE f360.growth_experiment_seq FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION f360.growth_threshold_error(jsonb), f360.growth_experiment_measure(f360.growth_experiments), f360.growth_experiment_changes_append_only(),
  public.f360_experiment_save(uuid, jsonb), public.f360_experiment_transition(uuid, text, text, text, text), public.f360_experiments_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION f360.growth_threshold_error(jsonb), f360.growth_experiment_measure(f360.growth_experiments) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.f360_experiment_save(uuid, jsonb), public.f360_experiment_transition(uuid, text, text, text, text), public.f360_experiments_list()
  TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261104000200', 'f360_growth_experiments', '{}');
DO $$ BEGIN
  IF to_regclass('f360.ig_account_daily') IS NULL OR to_regclass('f360.ig_media_metrics') IS NULL OR to_regclass('f360.clarity_snapshots') IS NULL
     OR to_regclass('f360.growth_experiments') IS NULL OR to_regclass('f360.growth_experiment_changes') IS NULL THEN RAISE EXCEPTION 'GP0 POST: tablas'; END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobname IN ('f360-instagram', 'f360-instagram-stories', 'f360-clarity')) <> 3 THEN RAISE EXCEPTION 'GP0 POST: crons'; END IF;
  IF (SELECT count(*) FROM f360.measurement_sources WHERE key IN ('instagram', 'clarity')) <> 2 THEN RAISE EXCEPTION 'GP0 POST: fuentes'; END IF;
  IF has_function_privilege('anon', 'public.f360_experiments_list()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.f360_instagram_import(text,date,date,jsonb,jsonb)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'f360.growth_experiments', 'SELECT') THEN RAISE EXCEPTION 'GP0 POST: permisos'; END IF;
END $$;
COMMIT;
