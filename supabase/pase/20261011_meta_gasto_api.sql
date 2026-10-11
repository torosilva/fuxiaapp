-- PASE · Meta Ads gasto por API (Mario 2026-10-11: "si dale" — historial desde mayo + lectura diaria en PRODUCCIÓN).
-- = supabase/migrations/20261023000100_f360_meta_spend_api.sql + its schema_migrations row, in ONE transaction.
-- Applied with scripts/f360/prod_sql.sh (dry-run first). It loads NO spend and does NOT mark meta_ads CONFIGURED:
-- the history is read by the function afterwards, then 20261011_meta_gasto_api_activar.sql flips the source.
BEGIN;

CREATE FUNCTION public.f360_marketing_spend_api_import(p_platform text, p_account_id text, p_currency text, p_from date, p_to date, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_today date := (now() AT TIME ZONE 'America/Mexico_City')::date; v_src text; v_rows jsonb; v_hash text; v_dup uuid; v_id uuid;
  v_started timestamptz := clock_timestamp(); x jsonb; i int := 0; e text; n int;
BEGIN
  v_src := CASE p_platform WHEN 'meta' THEN 'meta_ads' WHEN 'google' THEN 'google_ads' END;
  IF v_src IS NULL THEN RAISE EXCEPTION 'Plataforma no válida.'; END IF;
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to OR p_to > v_today OR p_to - p_from > 62 THEN RAISE EXCEPTION 'Ventana no válida (máximo 63 días, no futura).'; END IF;
  IF coalesce(p_account_id, '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RAISE EXCEPTION 'Cuenta publicitaria no válida.'; END IF;
  IF coalesce(p_currency, '') !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Moneda no válida.'; END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) > 5000 THEN RAISE EXCEPTION 'Filas no válidas (máximo 5,000).'; END IF;

  FOR x IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    i := i + 1;
    e := f360.marketing_spend_row_error(x, v_today);
    IF e IS NULL AND (x->>'account_id' <> p_account_id OR x->>'currency' <> p_currency) THEN e := 'cuenta o moneda distinta a la de la importación'; END IF;
    IF e IS NULL AND ((x->>'date')::date < p_from OR (x->>'date')::date > p_to) THEN e := 'fecha fuera de la ventana'; END IF;
    IF e IS NULL AND x->>'campaign_id' = 'sin_gasto' THEN e := 'campaign_id reservado'; END IF;
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

CREATE FUNCTION public.f360_measurement_run_failed(p_source_key text, p_from date, p_to date, p_error text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_source_key NOT IN ('meta_ads', 'google_ads', 'ga4') THEN RAISE EXCEPTION 'Fuente no válida.'; END IF;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, error)
    VALUES (p_source_key, clock_timestamp(), false, p_from, p_to, left(coalesce(nullif(btrim(p_error), ''), 'error sin detalle'), 500));
END $$;

CREATE FUNCTION f360.meta_spend_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-meta-spend') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-meta-spend$' THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"daily"}'::jsonb, timeout_milliseconds := 55000);
END $$;
SELECT cron.schedule('f360-meta-spend', '30 8 * * *', 'SELECT f360.meta_spend_tick()');

REVOKE ALL ON FUNCTION public.f360_marketing_spend_api_import(text, text, text, date, date, jsonb), public.f360_measurement_run_failed(text, date, date, text),
  f360.meta_spend_tick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_marketing_spend_api_import(text, text, text, date, date, jsonb), public.f360_measurement_run_failed(text, date, date, text)
  TO service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261023000100', 'f360_meta_spend_api', '{}');

-- Post-checks (same transaction)
DO $$ BEGIN
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'f360-meta-spend' AND schedule = '30 8 * * *') <> 1 THEN RAISE EXCEPTION 'ABORT: cron job'; END IF;
  IF NOT EXISTS (SELECT 1 FROM vault.decrypted_secrets WHERE name = 'f360_sync_url' AND decrypted_secret ~ '/functions/v1/[^/]+$') THEN
    RAISE EXCEPTION 'ABORT: f360_sync_url no termina en /functions/v1/<función>; el tick no tendría a quién llamar';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.marketing_spend_imports) THEN RAISE EXCEPTION 'ABORT: este pase no carga gasto'; END IF;
  IF (SELECT config_status FROM f360.measurement_sources WHERE key = 'meta_ads') <> 'NOT_CONFIGURED' THEN RAISE EXCEPTION 'ABORT: meta_ads cambió'; END IF;
  IF has_function_privilege('authenticated', 'public.f360_marketing_spend_api_import(text,text,text,date,date,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.f360_measurement_run_failed(text,date,date,text)', 'EXECUTE') THEN RAISE EXCEPTION 'ABORT: grants'; END IF;
END $$;
COMMIT;
