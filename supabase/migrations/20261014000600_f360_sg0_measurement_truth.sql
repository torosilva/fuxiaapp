-- Fuxia 360 · S-G0 Measurement Truth · MEASUREMENT HEALTH + REVENUE DEFINITIONS (D6) + the S-G0 answers (Mario 2026-10-08).
-- Spec: 02_MEASUREMENT_TRUTH.md, 03_GROWTH_COCKPIT.md, 09 §S-G0; definitions: docs/fuxia360/growth/S-G0_DELIVERY.md §D6.
-- ADDITIVE. No existing object changes; f360.commerce_orders, f360_commerce_summary and f360_exec_dashboard keep their numbers.
--   · f360.measurement_sources: registry of the 8 measured sources (configuration metadata only — NEVER credentials; API keys
--     live only as Supabase secrets). GA4 / Meta Ads / Google Ads start NOT_CONFIGURED; whether a platform HAS spend starts
--     UNKNOWN (NULL) until an owner says so.
--   · f360.measurement_runs: run log for future read-only API connectors (GA4 Data API, Meta insights, Google Ads). Empty.
--   · f360.measurement_sales (VIEW): one row per sale — online (Woo), store (F360 RPC) and legacy store (LEGACY_IMPORT registry)
--     with sales channel, capture source (realtime webhook / recovered by reconciliation / Woo history import / F360 store RPC /
--     LEGACY_IMPORT), original currency and the D6 revenue components. No PII.
--   · public.f360_measurement_health()  → per source: HEALTHY / DEGRADED / STALE / NOT_CONFIGURED / ERROR + reasons.
--   · public.f360_measurement_truth(from, to) → health + answers 1–10 (paid orders, missing vs Woo, last reconciliation,
--     capture health, realtime vs history, online / store / legacy, currency, net product revenue per currency + consolidated
--     MXN (DATA_INCOMPLETE without approved FX), spend, CAC / ROAS / MER — value NULL + DATA_INCOMPLETE, never 0).
--   · public.f360_measurement_sales_list(...) → per-sale technical list (ids, classes, currency, amounts; no PII).
--   · public.f360_measurement_source_set(...) → owner marks an API source CONFIGURED / a platform's spend as expected or not.
-- Access: owner / operator (require_role('operator')); tables / views: service role only.
-- Rollback: supabase/rollbacks/20261014000600_f360_sg0_measurement_truth.down.sql

CREATE TABLE f360.measurement_sources (
  key               text PRIMARY KEY CHECK (key IN ('woocommerce', 'order_reconciliation', 'ga4', 'meta_ads', 'google_ads', 'marketing_spend', 'store_sales', 'fx_rates')),
  label             text NOT NULL,
  kind              text NOT NULL CHECK (kind IN ('internal', 'api', 'manual')),
  config_status     text NOT NULL DEFAULT 'NOT_CONFIGURED' CHECK (config_status IN ('NOT_CONFIGURED', 'CONFIGURED')),
  spend_platform    text CHECK (spend_platform IN ('meta', 'google')),
  spend_expected    boolean,                                -- does this platform have paid spend? NULL = unknown (business decision)
  stale_after_hours integer CHECK (stale_after_hours > 0),
  notes             text CHECK (notes IS NULL OR length(notes) <= 500),
  updated_by_name   text,
  updated_at        timestamptz NOT NULL DEFAULT now()
);
INSERT INTO f360.measurement_sources (key, label, kind, config_status, spend_platform, stale_after_hours) VALUES
  ('woocommerce', 'WooCommerce (pedidos en tiempo real)', 'internal', 'CONFIGURED', NULL, NULL),
  ('order_reconciliation', 'Conciliación de pedidos Woo ↔ Fuxia 360', 'internal', 'CONFIGURED', NULL, 1),
  ('ga4', 'Google Analytics 4 (Data API)', 'api', 'NOT_CONFIGURED', NULL, 36),
  ('meta_ads', 'Meta Ads (API de solo lectura)', 'api', 'NOT_CONFIGURED', 'meta', 36),
  ('google_ads', 'Google Ads (API de solo lectura)', 'api', 'NOT_CONFIGURED', 'google', 36),
  ('marketing_spend', 'Gasto de marketing (API o CSV)', 'manual', 'CONFIGURED', NULL, 48),
  ('store_sales', 'Ventas de tienda física', 'internal', 'CONFIGURED', NULL, NULL),
  ('fx_rates', 'Tipos de cambio aprobados (mensual, base MXN)', 'manual', 'CONFIGURED', NULL, NULL);

CREATE TABLE f360.measurement_runs (
  id           bigserial PRIMARY KEY,
  source_key   text NOT NULL REFERENCES f360.measurement_sources(key) ON DELETE RESTRICT,
  started_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at  timestamptz,
  ok           boolean,
  window_from  date,
  window_to    date,
  rows         integer,
  error        text CHECK (error IS NULL OR length(error) <= 500)
);
CREATE INDEX measurement_runs_source_idx ON f360.measurement_runs (source_key, started_at DESC);

-- ── One row per sale (online / store / legacy store), original currency, D6 components ──
-- IVA: production Woo has tax disabled (total_tax = 0 on all orders, read-only check 2026-10-08) and store prices include IVA;
-- nothing here back-computes IVA. iva_treatment says whether tax was separated; product_net_before_tax is NULL when not.
CREATE VIEW f360.measurement_sales AS
  SELECT c.external_ref AS sale_ref, c.source_system,
         CASE WHEN c.channel = 'store' THEN 'store' ELSE 'online' END AS sales_channel,
         CASE WHEN c.source_system = 'f360_store' THEN 'f360_store_rpc'
              WHEN o.first_captured_via = 'webhook' THEN 'woo_realtime_webhook'
              WHEN o.first_captured_via = 'poll' THEN 'woo_reconciliation_recovered'
              WHEN o.first_captured_via = 'backfill' THEN 'woo_history_import'
              ELSE 'test_fixture' END AS capture_source,
         CASE WHEN o.first_captured_via = 'backfill' THEN 'historical_import' WHEN o.first_captured_via = 'test' THEN 'test' ELSE 'realtime' END AS timing_class,
         CASE WHEN o.first_captured_via = 'backfill' THEN o.first_captured_at END AS imported_at,
         coalesce(t.is_test, false) AS is_test_channel,
         c.target_id, c.woo_order_id, c.store_sale_id, c.location_id,
         c.occurred_at, c.paid_at, (coalesce(c.paid_at, c.occurred_at) AT TIME ZONE 'America/Mexico_City')::date AS business_date,
         c.status, c.status_class, c.payment_state, (c.status_class = 'countable') AS is_paid_sale,
         c.market, c.currency_original AS currency, o.billing_country AS country,
         c.product_gross AS gross_merchandise_value, c.discount AS discounts, c.product_net,
         CASE WHEN c.tax <> 0 THEN c.product_net END AS product_net_before_tax,
         c.tax AS tax_iva, CASE WHEN c.tax <> 0 THEN 'separated' ELSE 'included_not_separated' END AS iva_treatment,
         c.shipping AS shipping_charged, c.fees, c.refund_total AS refunds, c.refund_product AS refunds_product,
         c.net_product AS net_product_revenue, c.net_order_total AS total_collected, c.units,
         c.data_quality, c.data_quality_reasons, c.provenance
  FROM f360.commerce_orders c
  LEFT JOIN f360.commerce_woo_orders o ON o.target_id = c.target_id AND o.woo_order_id = c.woo_order_id
  LEFT JOIN f360.sales_targets t ON t.id = c.target_id
  UNION ALL
  SELECT 'legacy_store_sale:' || s.id, 'legacy_store', 'legacy_store', 'LEGACY_IMPORT', 'legacy_import', li.imported_at, false,
         NULL, NULL, s.id, li.location_id,
         s.created_at, s.created_at, (s.created_at AT TIME ZONE 'America/Mexico_City')::date,
         'legacy_recorded', CASE WHEN li.status = 'imported' THEN 'countable' ELSE 'needs_review' END, 'paid', li.status = 'imported',
         'MX', 'MXN', NULL,
         s.total, 0, s.total, NULL, 0, 'included_not_separated', 0, 0, 0, 0, s.total, s.total, coalesce((li.validation->>'units')::int, 0),
         'PARTIAL', ARRAY(SELECT jsonb_array_elements_text(li.validation->'issues')) || ARRAY['legacy_import'], 'offline_sales:legacy_import'
  FROM f360.legacy_store_sale_imports li JOIN public.offline_sales s ON s.id = li.sale_id;
COMMENT ON VIEW f360.measurement_sales IS 'S-G0: one row per sale (online / store / legacy store) with capture source and D6 revenue components, original currency. No PII.';

-- Does the database hold a production channel? (same rule as f360_exec_dashboard: test channels count only where there is none)
CREATE FUNCTION f360.sg0_include_tests() RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE is_production) $$;

-- ── Health per source (internal; the public RPC checks the role) ──
CREATE FUNCTION f360.sg0_source_health() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE out jsonb := '[]'; src record; st text; reasons text[]; detail jsonb; last_ok timestamptz; last_try timestamptz;
  tgt record; t_st text; t_reasons text[]; t_list jsonb; run f360.commerce_sync_runs; ok_run f360.commerce_sync_runs; mrun f360.measurement_runs; mok f360.measurement_runs;
  v_secrets boolean := false; v_cron boolean := false; today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  n int; n2 int; d1 date; d2 date; x jsonb; rank_of jsonb := '{"HEALTHY":0,"NOT_CONFIGURED":1,"DEGRADED":2,"STALE":3,"ERROR":4}';
BEGIN
  BEGIN
    v_secrets := (SELECT count(*) = 2 FROM vault.secrets WHERE name IN ('f360_sync_url', 'f360_sync_secret'));
  EXCEPTION WHEN OTHERS THEN v_secrets := false; END;
  BEGIN
    v_cron := EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'f360-commerce-poll' AND active);
  EXCEPTION WHEN OTHERS THEN v_cron := false; END;

  FOR src IN SELECT * FROM f360.measurement_sources ORDER BY array_position(ARRAY['woocommerce', 'order_reconciliation', 'store_sales', 'marketing_spend', 'meta_ads', 'google_ads', 'ga4', 'fx_rates'], key) LOOP
    st := 'HEALTHY'; reasons := '{}'; detail := '{}'; last_ok := NULL; last_try := NULL;

    IF src.key IN ('woocommerce', 'order_reconciliation') THEN
      t_list := '[]';
      FOR tgt IN SELECT t.* FROM f360.sales_targets t WHERE f360.sg0_orders_path_on(t) ORDER BY t.key LOOP
        t_reasons := '{}';
        IF src.key = 'woocommerce' THEN
          SELECT max(received_at), count(*) FILTER (WHERE received_at > now() - interval '24 hours'),
                 count(*) FILTER (WHERE received_at > now() - interval '24 hours' AND result IN ('error', 'rejected_signature'))
            INTO last_try, n, n2 FROM f360.woo_webhook_deliveries WHERE target_id = tgt.id;
          t_st := CASE WHEN (SELECT result FROM f360.woo_webhook_deliveries WHERE target_id = tgt.id ORDER BY id DESC LIMIT 1) = 'error' THEN 'ERROR' ELSE 'HEALTHY' END;
          IF last_try IS NULL THEN t_st := 'DEGRADED'; t_reasons := array_append(t_reasons, 'no_webhook_received_yet'); END IF;
          IF n2 > 0 THEN t_st := CASE WHEN t_st = 'ERROR' THEN t_st ELSE 'DEGRADED' END; t_reasons := array_append(t_reasons, 'webhook_errors_last_24h:' || n2); END IF;
          SELECT coalesce(sum(coalesce((r.stats->>'recovered')::int, CASE WHEN r.kind = 'poll' THEN (r.stats->>'inserted')::int END, 0)), 0) INTO n
            FROM f360.commerce_sync_runs r WHERE r.target_id = tgt.id AND r.kind IN ('poll', 'reconcile') AND r.ok AND r.started_at > now() - interval '24 hours';
          IF n > 0 THEN t_st := CASE WHEN t_st = 'ERROR' THEN t_st ELSE 'DEGRADED' END; t_reasons := array_append(t_reasons, 'orders_missed_by_webhook_recovered_last_24h:' || n); END IF;
          t_list := t_list || jsonb_build_object('target', tgt.key, 'status', t_st, 'reasons', to_jsonb(t_reasons), 'last_webhook_at', last_try,
            'deliveries_24h', (SELECT count(*) FROM f360.woo_webhook_deliveries WHERE target_id = tgt.id AND received_at > now() - interval '24 hours'));
        ELSE
          SELECT * INTO run FROM f360.commerce_sync_runs r WHERE r.target_id = tgt.id AND r.kind IN ('poll', 'reconcile') ORDER BY r.id DESC LIMIT 1;
          SELECT * INTO ok_run FROM f360.commerce_sync_runs r WHERE r.target_id = tgt.id AND r.kind IN ('poll', 'reconcile') AND r.ok ORDER BY r.id DESC LIMIT 1;
          IF NOT v_secrets OR NOT v_cron THEN t_st := 'NOT_CONFIGURED'; t_reasons := array_append(t_reasons, CASE WHEN NOT v_secrets THEN 'vault_sync_secrets_missing' ELSE 'cron_job_missing' END);
          ELSIF run.id IS NULL THEN t_st := 'NOT_CONFIGURED'; t_reasons := array_append(t_reasons, 'never_ran');
          ELSIF run.finished_at IS NOT NULL AND NOT run.ok THEN t_st := 'ERROR'; t_reasons := array_append(t_reasons, 'last_run_failed: ' || coalesce(left(run.error, 120), '?'));
          ELSIF ok_run.id IS NULL OR ok_run.finished_at < now() - interval '60 minutes' THEN t_st := 'STALE'; t_reasons := array_append(t_reasons, 'no_successful_run_in_60_min');
          ELSE
            t_st := 'HEALTHY';
            IF coalesce((ok_run.stats->>'detected_missing')::int, 0) > coalesce((ok_run.stats->>'recovered')::int, 0) THEN
              t_st := 'DEGRADED'; t_reasons := array_append(t_reasons, 'missing_orders_not_recovered:' || ((ok_run.stats->>'detected_missing')::int - coalesce((ok_run.stats->>'recovered')::int, 0)));
            END IF;
            IF coalesce((ok_run.stats->>'before_cutover_missing')::int, 0) > 0 THEN
              t_st := 'DEGRADED'; t_reasons := array_append(t_reasons, 'orders_before_cutover_not_imported:' || (ok_run.stats->>'before_cutover_missing'));
            END IF;
          END IF;
          t_list := t_list || jsonb_build_object('target', tgt.key, 'status', t_st, 'reasons', to_jsonb(t_reasons),
            'last_run', CASE WHEN run.id IS NOT NULL THEN jsonb_build_object('id', run.id, 'kind', run.kind, 'started_at', run.started_at, 'finished_at', run.finished_at, 'ok', run.ok, 'stats', run.stats) END,
            'last_success_at', ok_run.finished_at);
          last_ok := greatest(last_ok, ok_run.finished_at); last_try := greatest(last_try, run.started_at);
        END IF;
        IF (rank_of->>t_st)::int > (rank_of->>st)::int THEN st := t_st; END IF;
        reasons := reasons || ARRAY(SELECT tgt.key || ': ' || u FROM unnest(t_reasons) u);
      END LOOP;
      IF jsonb_array_length(t_list) = 0 THEN st := 'NOT_CONFIGURED'; reasons := ARRAY['no_channel_feeds_orders']; END IF;
      detail := jsonb_build_object('targets', t_list, 'vault_secrets', v_secrets, 'cron', v_cron);

    ELSIF src.kind = 'api' THEN
      SELECT * INTO mrun FROM f360.measurement_runs WHERE source_key = src.key ORDER BY id DESC LIMIT 1;
      SELECT * INTO mok FROM f360.measurement_runs WHERE source_key = src.key AND ok ORDER BY id DESC LIMIT 1;
      last_ok := mok.finished_at; last_try := mrun.started_at;
      IF src.config_status = 'NOT_CONFIGURED' THEN st := 'NOT_CONFIGURED'; reasons := ARRAY['api_not_configured_no_credentials'];
      ELSIF mrun.id IS NULL THEN st := 'DEGRADED'; reasons := ARRAY['configured_no_run_yet'];
      ELSIF mrun.finished_at IS NOT NULL AND NOT mrun.ok THEN st := 'ERROR'; reasons := ARRAY['last_run_failed: ' || coalesce(left(mrun.error, 120), '?')];
      ELSIF mok.id IS NULL OR mok.finished_at < now() - make_interval(hours => coalesce(src.stale_after_hours, 36)) THEN st := 'STALE'; reasons := ARRAY['no_successful_run_in_' || coalesce(src.stale_after_hours, 36) || 'h'];
      END IF;
      detail := jsonb_build_object('state', CASE WHEN src.config_status = 'NOT_CONFIGURED' THEN 'NOT_CONFIGURED' WHEN mrun.id IS NULL THEN 'CONFIGURED' ELSE st END);
      IF src.spend_platform IS NOT NULL THEN
        SELECT count(DISTINCT date), max(date) INTO n, d1 FROM f360.marketing_spend_daily WHERE platform = src.spend_platform;
        detail := detail || jsonb_build_object('spend_expected', src.spend_expected, 'csv_or_manual_days_loaded', n, 'last_spend_date', d1);
        IF src.spend_expected IS NULL THEN reasons := array_append(reasons, 'unknown_if_platform_has_spend'); END IF;
      END IF;

    ELSIF src.key = 'marketing_spend' THEN
      SELECT max(uploaded_at) INTO last_ok FROM f360.marketing_spend_imports WHERE status = 'accepted';
      SELECT max(uploaded_at) INTO last_try FROM f360.marketing_spend_imports;
      SELECT count(DISTINCT (platform, date)), min(date), max(date) INTO n, d1, d2 FROM f360.marketing_spend_daily;
      IF n = 0 THEN st := 'NOT_CONFIGURED'; reasons := ARRAY['no_spend_loaded'];
      ELSIF (SELECT status FROM f360.marketing_spend_imports ORDER BY uploaded_at DESC LIMIT 1) = 'rejected' THEN st := 'ERROR'; reasons := ARRAY['last_upload_rejected'];
      ELSIF d2 < today - 2 THEN st := 'STALE'; reasons := ARRAY['last_spend_day:' || d2];
      ELSE
        -- gaps: days in the last 30 (within the loaded range) without any row for a platform that has data
        SELECT count(*) INTO n2 FROM (SELECT DISTINCT platform FROM f360.marketing_spend_daily) p
          CROSS JOIN generate_series(greatest(d1, today - 30), d2, interval '1 day') g(day)
          WHERE NOT EXISTS (SELECT 1 FROM f360.marketing_spend_daily s WHERE s.platform = p.platform AND s.date = g.day::date);
        IF n2 > 0 THEN st := 'DEGRADED'; reasons := array_append(reasons, 'days_without_spend_rows_last_30:' || n2); END IF;
      END IF;
      IF EXISTS (SELECT 1 FROM f360.measurement_sources WHERE spend_platform IS NOT NULL AND spend_expected IS NULL) THEN
        IF st = 'HEALTHY' THEN st := 'DEGRADED'; END IF;
        reasons := array_append(reasons, 'platforms_with_unknown_spend:' || (SELECT string_agg(spend_platform, ',') FROM f360.measurement_sources WHERE spend_platform IS NOT NULL AND spend_expected IS NULL));
      END IF;
      detail := jsonb_build_object('platform_days', n, 'first_day', d1, 'last_day', d2,
        'imports_accepted', (SELECT count(*) FROM f360.marketing_spend_imports WHERE status = 'accepted'),
        'imports_rejected', (SELECT count(*) FROM f360.marketing_spend_imports WHERE status = 'rejected'));

    ELSIF src.key = 'store_sales' THEN
      SELECT count(*), max(created_at) INTO n, last_ok FROM public.offline_sales WHERE created_by_rpc;
      detail := jsonb_build_object('f360_rpc_sales', n, 'last_f360_sale_at', last_ok,
        'legacy_total', (SELECT count(*) FROM public.offline_sales WHERE NOT created_by_rpc),
        'legacy_imported', (SELECT count(*) FROM f360.legacy_store_sale_imports WHERE status = 'imported'),
        'legacy_needs_review', (SELECT count(*) FROM f360.legacy_store_sale_imports WHERE status = 'needs_review'),
        'legacy_pending_import', (SELECT count(*) FROM public.offline_sales o WHERE NOT o.created_by_rpc AND NOT EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports li WHERE li.sale_id = o.id)),
        'f360_stores', (SELECT count(*) FROM f360.locations WHERE status = 'active' AND sellable AND ledger_authority = 'f360'));
      IF (detail->>'f360_stores')::int = 0 THEN st := 'NOT_CONFIGURED'; reasons := ARRAY['no_f360_store'];
      ELSE
        IF (detail->>'legacy_pending_import')::int > 0 THEN st := 'DEGRADED'; reasons := array_append(reasons, 'legacy_sales_not_imported:' || (detail->>'legacy_pending_import')); END IF;
        IF (detail->>'legacy_needs_review')::int > 0 THEN st := 'DEGRADED'; reasons := array_append(reasons, 'legacy_sales_need_review:' || (detail->>'legacy_needs_review')); END IF;
      END IF;

    ELSIF src.key = 'fx_rates' THEN
      WITH need AS (
        SELECT DISTINCT m.currency, date_trunc('month', m.business_date)::date AS period FROM f360.measurement_sales m
          WHERE m.is_paid_sale AND m.currency <> 'MXN' AND (f360.sg0_include_tests() OR NOT m.is_test_channel)
        UNION SELECT DISTINCT s.currency, date_trunc('month', s.date)::date FROM f360.marketing_spend_daily s WHERE s.currency <> 'MXN'),
      miss AS (SELECT n.* FROM need n WHERE f360.fx_rate_for(n.currency, n.period) IS NULL)
      SELECT (SELECT count(*) FROM need), (SELECT count(*) FROM miss),
             coalesce((SELECT jsonb_agg(jsonb_build_object('currency', currency, 'month', to_char(period, 'YYYY-MM')) ORDER BY period DESC, currency) FROM miss), '[]'),
             (SELECT max(period) FROM miss), (SELECT max(period) FROM need)
        INTO n, n2, x, d1, d2;
      SELECT max(approved_at) INTO last_ok FROM f360.fx_rates WHERE status = 'approved';
      detail := jsonb_build_object('months_needed', n, 'months_missing', n2, 'missing', x,
        'approved_rates', (SELECT count(*) FROM f360.fx_rates WHERE status = 'approved'), 'base_currency', 'MXN');
      IF NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE status = 'approved') THEN st := 'NOT_CONFIGURED'; reasons := ARRAY['no_approved_rate'];
        IF n2 > 0 THEN reasons := array_append(reasons, 'consolidation_needs_' || n2 || '_currency_months'); END IF;
      ELSIF n2 > 0 AND d1 = d2 THEN st := 'STALE'; reasons := ARRAY['latest_month_without_rate:' || to_char(d1, 'YYYY-MM')];
      ELSIF n2 > 0 THEN st := 'DEGRADED'; reasons := ARRAY['older_months_without_rate:' || n2];
      END IF;
    END IF;

    out := out || jsonb_build_object('key', src.key, 'label', src.label, 'kind', src.kind, 'status', st, 'reasons', to_jsonb(reasons),
      'last_success_at', last_ok, 'last_attempt_at', last_try, 'detail', detail);
  END LOOP;
  RETURN out;
END $$;

-- ── MER / ROAS / CAC: value only when every input is present; otherwise DATA_INCOMPLETE with value NULL (never 0) ──
CREATE FUNCTION f360.sg0_efficiency_kpis(p_from date, p_to date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE spend_missing text[] := '{}'; fx_missing text[] := '{}'; v_to date; v_rev numeric; v_spend numeric; v_days int; p record; n int;
  incl boolean := f360.sg0_include_tests();
BEGIN
  IF p_from IS NULL OR p_to IS NULL THEN spend_missing := ARRAY['bounded_period_required'];
  ELSE
    v_to := least(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date - 1);         -- today's spend is never complete
    IF v_to < p_from THEN spend_missing := ARRAY['period_has_no_closed_day'];
    ELSE
      v_days := v_to - p_from + 1;
      IF NOT EXISTS (SELECT 1 FROM f360.marketing_spend_daily WHERE date BETWEEN p_from AND v_to) THEN spend_missing := ARRAY['marketing_spend_missing']; END IF;
      FOR p IN SELECT key, spend_platform, spend_expected FROM f360.measurement_sources WHERE spend_platform IS NOT NULL ORDER BY key LOOP
        IF p.spend_expected IS NULL THEN spend_missing := array_append(spend_missing, 'unknown_if_' || p.key || '_has_spend');
        ELSIF p.spend_expected THEN
          SELECT count(DISTINCT date) INTO n FROM f360.marketing_spend_daily WHERE platform = p.spend_platform AND date BETWEEN p_from AND v_to;
          IF n < v_days THEN spend_missing := array_append(spend_missing, p.key || '_spend_days_missing:' || (v_days - n)); END IF;
        END IF;
      END LOOP;
      IF EXISTS (SELECT 1 FROM f360.marketing_spend_daily WHERE date BETWEEN p_from AND v_to AND market = 'UNKNOWN') THEN
        spend_missing := array_append(spend_missing, 'spend_rows_without_market');
      END IF;
    END IF;
  END IF;
  -- MER (total, base MXN): Σ paid net product revenue (online + store + legacy imported) ÷ Σ spend, both in MXN with approved FX
  IF cardinality(spend_missing) = 0 THEN
    SELECT array_agg(DISTINCT currency || ':' || to_char(date_trunc('month', d), 'YYYY-MM')) INTO fx_missing FROM (
      SELECT m.currency, m.business_date d FROM f360.measurement_sales m WHERE m.is_paid_sale AND m.business_date BETWEEN p_from AND v_to AND (incl OR NOT m.is_test_channel)
      UNION ALL SELECT s.currency, s.date FROM f360.marketing_spend_daily s WHERE s.date BETWEEN p_from AND v_to) z
      WHERE f360.fx_rate_for(currency, d) IS NULL;
    fx_missing := coalesce(fx_missing, '{}');
    IF cardinality(fx_missing) = 0 THEN
      SELECT sum(m.net_product_revenue * f360.fx_rate_for(m.currency, m.business_date)) INTO v_rev FROM f360.measurement_sales m
        WHERE m.is_paid_sale AND m.business_date BETWEEN p_from AND v_to AND (incl OR NOT m.is_test_channel);
      SELECT sum(s.spend * f360.fx_rate_for(s.currency, s.date)) INTO v_spend FROM f360.marketing_spend_daily s WHERE s.date BETWEEN p_from AND v_to;
    END IF;
  END IF;
  RETURN jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', v_to),
    'mer', CASE WHEN cardinality(spend_missing) = 0 AND cardinality(fx_missing) = 0 AND coalesce(v_spend, 0) > 0
                THEN jsonb_build_object('status', 'OK', 'value', round(coalesce(v_rev, 0) / v_spend, 2), 'revenue_mxn', round(coalesce(v_rev, 0), 2), 'spend_mxn', round(v_spend, 2),
                                        'basis', 'paid_net_product_revenue ÷ marketing_spend (MXN, approved monthly FX)')
                ELSE jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL,
                       'missing', to_jsonb(spend_missing || ARRAY(SELECT 'fx_rate_missing:' || f FROM unnest(fx_missing) f) ||
                                           CASE WHEN cardinality(spend_missing) = 0 AND cardinality(fx_missing) = 0 THEN ARRAY['spend_total_is_zero'] ELSE '{}'::text[] END)) END,
    'roas', jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL,
              'missing', to_jsonb(ARRAY['channel_attribution_rules_v1_not_built (S-G1)'] || spend_missing)),
    'cac', jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL,
              'missing', to_jsonb(ARRAY['new_customer_identification_not_built (history + identity, S-G1)'] || spend_missing)));
END $$;

CREATE FUNCTION public.f360_measurement_health() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN jsonb_build_object('generated_at', now(), 'sources', f360.sg0_source_health());
END $$;

CREATE FUNCTION public.f360_measurement_truth(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); incl boolean := f360.sg0_include_tests(); h jsonb := f360.sg0_source_health();
  fx_missing jsonb; v_cons numeric; rec jsonb;
BEGIN
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN RAISE EXCEPTION 'Periodo no válido.'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'month', to_char(period, 'YYYY-MM')) ORDER BY period, currency), '[]') INTO fx_missing
    FROM (SELECT DISTINCT currency, date_trunc('month', business_date)::date AS period FROM f360.measurement_sales m
          WHERE m.is_paid_sale AND m.currency <> 'MXN' AND (incl OR NOT m.is_test_channel)
            AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to)) z
    WHERE f360.fx_rate_for(currency, period) IS NULL;
  IF jsonb_array_length(fx_missing) = 0 THEN
    SELECT coalesce(sum(m.net_product_revenue * f360.fx_rate_for(m.currency, m.business_date)), 0) INTO v_cons FROM f360.measurement_sales m
      WHERE m.is_paid_sale AND (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to);
  END IF;
  SELECT jsonb_build_object('targets', coalesce(jsonb_agg(t), '[]')) INTO rec
    FROM jsonb_array_elements((SELECT s->'detail'->'targets' FROM jsonb_array_elements(h) s WHERE s->>'key' = 'order_reconciliation')) t;

  RETURN (WITH ms AS (SELECT * FROM f360.measurement_sales m
      WHERE (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to))
  SELECT jsonb_build_object(
    'kind', 'ACTUAL', 'from', p_from, 'to', p_to, 'generated_at', now(), 'includes_test_data', incl, 'timezone', 'America/Mexico_City',
    'health', h,
    -- 1 · which paid orders Fuxia 360 knows (by channel × capture source × currency; D6 components)
    'q1_paid_orders', jsonb_build_object('total', (SELECT count(*) FROM ms WHERE is_paid_sale),
      'groups', (SELECT coalesce(jsonb_agg(g ORDER BY g->>'sales_channel', g->>'capture_source', g->>'currency'), '[]') FROM (
        SELECT jsonb_build_object('sales_channel', sales_channel, 'capture_source', capture_source, 'currency', currency, 'paid_orders', count(*), 'units', sum(units),
          'gross_merchandise_value', sum(gross_merchandise_value), 'discounts', sum(discounts), 'product_net', sum(product_net),
          'tax_iva', sum(tax_iva), 'shipping_charged', sum(shipping_charged), 'refunds', sum(refunds),
          'net_product_revenue', sum(net_product_revenue), 'total_collected', sum(total_collected)) AS g
        FROM ms WHERE is_paid_sale GROUP BY sales_channel, capture_source, currency) q),
      'not_paid', (SELECT coalesce(jsonb_object_agg(status_class, n), '{}') FROM (SELECT status_class, count(*) n FROM ms WHERE NOT is_paid_sale GROUP BY 1) y)),
    -- 2 + 3 · missing vs Woo and the last reconciliation (per channel feeding orders)
    'q2_q3_reconciliation', rec,
    -- 4 · capture health
    'q4_capture_health', (SELECT coalesce(jsonb_agg(jsonb_build_object('key', s->>'key', 'status', s->>'status', 'reasons', s->'reasons')), '[]')
                          FROM jsonb_array_elements(h) s WHERE s->>'key' IN ('woocommerce', 'order_reconciliation', 'store_sales')),
    -- 5 · realtime vs historical import
    'q5_timing', (SELECT coalesce(jsonb_object_agg(timing_class, jsonb_build_object('sales', n, 'paid', p)), '{}') FROM (
        SELECT timing_class, count(*) n, count(*) FILTER (WHERE is_paid_sale) p FROM ms GROUP BY 1) y),
    -- 6 · online vs store vs legacy
    'q6_channels', (SELECT coalesce(jsonb_object_agg(sales_channel, jsonb_build_object('paid', p, 'not_counted', n - p)), '{}') FROM (
        SELECT sales_channel, count(*) n, count(*) FILTER (WHERE is_paid_sale) p FROM ms GROUP BY 1) y),
    -- 7 · currency of each sale (counts; per sale: f360_measurement_sales_list)
    'q7_currencies', (SELECT coalesce(jsonb_object_agg(currency, n), '{}') FROM (SELECT currency, count(*) n FROM ms WHERE is_paid_sale GROUP BY 1) y),
    -- 8 · paid net product revenue per ORIGINAL currency + consolidated MXN only with approved FX
    'q8_net_product_revenue', jsonb_build_object(
      'by_currency', (SELECT coalesce(jsonb_agg(jsonb_build_object('currency', currency, 'net_product_revenue', v, 'total_collected', tc, 'paid_orders', n) ORDER BY currency), '[]') FROM (
          SELECT currency, sum(net_product_revenue) v, sum(total_collected) tc, count(*) n FROM ms WHERE is_paid_sale GROUP BY 1) y),
      'consolidated_mxn', CASE WHEN jsonb_array_length(fx_missing) = 0
          THEN jsonb_build_object('status', 'OK', 'value', round(v_cons, 2), 'kind', 'CONVERTED', 'basis', 'approved monthly FX, base MXN')
          ELSE jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL, 'missing', jsonb_build_array('fx_rate_missing'), 'fx_missing', fx_missing) END,
      'basis', 'net_product_revenue = Σ line totals after coupons, before shipping, minus product refunds; paid sales only; IVA not separated when Woo does not separate it'),
    -- 9 · do we have spend?
    'q9_spend', jsonb_build_object(
      'status', (SELECT s->>'status' FROM jsonb_array_elements(h) s WHERE s->>'key' = 'marketing_spend'),
      'by_currency', (SELECT coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'currency', currency, 'spend', v, 'days', d) ORDER BY platform, currency), '[]') FROM (
          SELECT platform, currency, sum(spend) v, count(DISTINCT date) d FROM f360.marketing_spend_daily
          WHERE (p_from IS NULL OR date >= p_from) AND (p_to IS NULL OR date <= p_to) GROUP BY 1, 2) y)),
    -- 10 · efficiency KPIs: never 0 when an input is missing
    'q10_efficiency', f360.sg0_efficiency_kpis(p_from, p_to)));
END $$;

CREATE FUNCTION public.f360_measurement_sales_list(p_limit integer DEFAULT 100, p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); incl boolean := f360.sg0_include_tests();
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x->>'business_date' DESC, x->>'sale_ref' DESC), '[]') FROM (
    SELECT jsonb_build_object('sale_ref', m.sale_ref, 'sales_channel', m.sales_channel, 'capture_source', m.capture_source, 'timing', m.timing_class,
      'imported_at', m.imported_at, 'business_date', m.business_date, 'status', m.status, 'status_class', m.status_class, 'paid', m.is_paid_sale,
      'market', m.market, 'currency', m.currency, 'net_product_revenue', m.net_product_revenue, 'total_collected', m.total_collected,
      'iva_treatment', m.iva_treatment, 'quality', m.data_quality, 'quality_reasons', to_jsonb(m.data_quality_reasons), 'test_channel', m.is_test_channel) AS x
    FROM f360.measurement_sales m
    WHERE (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to)
    ORDER BY m.business_date DESC, m.sale_ref DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) q);
END $$;

CREATE FUNCTION public.f360_measurement_source_set(p_key text, p_config_status text DEFAULT NULL, p_spend_expected boolean DEFAULT NULL,
  p_clear_spend_expected boolean DEFAULT false, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); s f360.measurement_sources;
BEGIN
  SELECT * INTO s FROM f360.measurement_sources WHERE key = p_key FOR UPDATE;
  IF s.key IS NULL THEN RAISE EXCEPTION 'Fuente no encontrada.'; END IF;
  IF p_config_status IS NOT NULL AND (s.kind <> 'api' OR p_config_status NOT IN ('NOT_CONFIGURED', 'CONFIGURED')) THEN
    RAISE EXCEPTION 'Solo una fuente por API se marca como configurada / no configurada.';
  END IF;
  IF (p_spend_expected IS NOT NULL OR p_clear_spend_expected) AND s.spend_platform IS NULL THEN RAISE EXCEPTION 'Esta fuente no es una plataforma de anuncios.'; END IF;
  UPDATE f360.measurement_sources SET config_status = coalesce(p_config_status, config_status),
      spend_expected = CASE WHEN p_clear_spend_expected THEN NULL ELSE coalesce(p_spend_expected, spend_expected) END,
      notes = coalesce(nullif(btrim(coalesce(p_notes, '')), ''), notes), updated_by_name = r.display_name, updated_at = now()
    WHERE key = p_key;
  RETURN jsonb_build_object('ok', true, 'key', p_key);
END $$;

ALTER TABLE f360.measurement_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.measurement_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.measurement_sources, f360.measurement_runs, f360.measurement_sales FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.measurement_sources, f360.measurement_runs TO service_role;
GRANT USAGE ON SEQUENCE f360.measurement_runs_id_seq TO service_role;
GRANT SELECT ON f360.measurement_sales TO service_role;
REVOKE ALL ON FUNCTION f360.sg0_include_tests(), f360.sg0_source_health(), f360.sg0_efficiency_kpis(date, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_measurement_health(), public.f360_measurement_truth(date, date), public.f360_measurement_sales_list(integer, date, date),
  public.f360_measurement_source_set(text, text, boolean, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_measurement_health(), public.f360_measurement_truth(date, date), public.f360_measurement_sales_list(integer, date, date),
  public.f360_measurement_source_set(text, text, boolean, boolean, text) TO authenticated, service_role;
