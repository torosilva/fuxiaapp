-- Fuxia 360 · pase P0B — Measurement foundation (S-G0 schema, inert + tax pending + FX documentation + spend source state + bazaar guard)
-- PREPARED 2026-10-08 by the pre-production gate (docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md). NOT RUN. Apply ONLY with
-- scripts/f360/prod_sql.sh after Mario's explicit written approval of THIS gate (it dry-runs with ROLLBACK first).
-- Contents: the committed migrations 20261014000100, 20261014000200, 20261014000300, 20261014000400, 20261014000500, 20261014000600, 20261016000200, 20261016000300, 20261016000400, 20261016000500 verbatim, in order, each with its schema_migrations row.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production' AND is_production) THEN
    RAISE EXCEPTION 'ABORT: this pase is for PRODUCTION only (woo_production target missing)';
  END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version IN ('20261014000100', '20261014000200', '20261014000300', '20261014000400', '20261014000500', '20261014000600', '20261016000200', '20261016000300', '20261016000400', '20261016000500')) THEN
    RAISE EXCEPTION 'ABORT: part of this gate is already applied';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261012001100') THEN RAISE EXCEPTION 'ABORT: prerequisite 20261012001100 missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261010000200') THEN RAISE EXCEPTION 'ABORT: prerequisite 20261010000200 missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261008000100') THEN RAISE EXCEPTION 'ABORT: prerequisite 20261008000100 missing'; END IF;
  IF to_regclass('f360.measurement_sales') IS NOT NULL OR to_regclass('f360.fx_rates') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: S-G0 objects already exist'; END IF;
END $$;

-- ════════ 20261014000100_f360_sg0_order_reconciliation.sql ════════
-- Fuxia 360 · S-G0 Measurement Truth · D2 ORDER RECONCILIATION (Mario 2026-10-08, P0: "Woo order exists BUT Fuxia 360 order
-- missing" must be detected and recovered idempotently, with logging, health, last successful run, detected, recovered, errors).
-- Spec: docs/fuxia360/growth/09_GROWTH_IMPLEMENTATION_PLAN.md §S-G0 (1)(2); delivery: docs/fuxia360/growth/S-G0_DELIVERY.md.
-- ADDITIVE / compatible:
--   · f360.sg0_order_target(key): the order-path guard of 20261012001100 (f360.orders_target) written so it ALSO works on a
--     database where that migration is not applied yet (staging): production only when orders_mode = 'on' (read through
--     to_jsonb, no hard column reference); every other channel exactly as f360.target_by_key.
--   · commerce_sync_runs.kind gains 'reconcile' (CHECK widened; existing rows untouched).
--   · public.f360_commerce_reconcile_begin(key, lookback_hours): opens a reconcile run. Window: explicit lookback (deep check)
--     → else the cursor − 10 min (incremental) → else from the cutover order's creation − 1 day (first run in production)
--     → else the last 72 h.
--   · public.f360_commerce_reconcile_diff(key, orders[{id, date_modified_gmt}]): READ-ONLY comparison of a Woo page with Fuxia 360:
--     missing (Woo has it, F360 not, after the cutover) / outdated (Woo modified later than F360's version) /
--     before_cutover_missing (belongs to the history import, never recovered as "realtime") / current.
--     The capture itself stays the ONE existing writer (public.f360_capture_order_economics, key (target, woo_order_id)):
--     a duplicate order cannot exist.
--   · f360.commerce_source_health: production now appears when its order path is on (was hidden: `active AND NOT is_production`,
--     20261008000100:455). Same columns.
--   · public.f360_channel_mode also returns orders_mode / orders_since_id (when the column exists) so the sync function can
--     gate the reconciliation by ORDERS, not by stock (f360-woo-sync/handler.ts:59-60).
-- Nothing here touches inventory (woo_orders / inventory_events), order_shipping, loyalty or prices.
-- Rollback: supabase/rollbacks/20261014000100_f360_sg0_order_reconciliation.down.sql

CREATE FUNCTION f360.sg0_order_target(p_key text) RETURNS f360.sales_targets
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_key;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Tienda % no configurada.', p_key; END IF;
  IF t.is_production THEN
    IF coalesce(to_jsonb(t)->>'orders_mode', 'off') <> 'on' THEN RAISE EXCEPTION 'Los pedidos de la tienda de producción no están encendidos.'; END IF;
    RETURN t;
  END IF;
  RETURN f360.target_by_key(p_key);   -- every non-production channel: exactly as before (active, not production)
END $$;
REVOKE ALL ON FUNCTION f360.sg0_order_target(text) FROM PUBLIC, anon, authenticated;

-- Does this channel feed orders to Fuxia 360? (staging: active test channels; production: orders_mode = 'on')
CREATE FUNCTION f360.sg0_orders_path_on(t f360.sales_targets) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (t.active AND NOT t.is_production) OR (t.is_production AND coalesce(to_jsonb(t)->>'orders_mode', 'off') = 'on') $$;
REVOKE ALL ON FUNCTION f360.sg0_orders_path_on(f360.sales_targets) FROM PUBLIC, anon, authenticated;

ALTER TABLE f360.commerce_sync_runs DROP CONSTRAINT commerce_sync_runs_kind_check;
ALTER TABLE f360.commerce_sync_runs ADD CONSTRAINT commerce_sync_runs_kind_check CHECK (kind IN ('poll', 'backfill', 'reconcile'));

CREATE FUNCTION public.f360_commerce_reconcile_begin(p_target_key text, p_lookback_hours integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; s f360.commerce_sync_state; v_id bigint; v_after timestamptz; v_since bigint; v_mode text;
BEGIN
  t := f360.sg0_order_target(p_target_key);
  IF p_lookback_hours IS NOT NULL AND (p_lookback_hours < 1 OR p_lookback_hours > 24 * 800) THEN
    RAISE EXCEPTION 'La ventana de revisión debe ser de 1 hora a 800 días.';
  END IF;
  v_since := nullif(to_jsonb(t)->>'orders_since_id', '')::bigint;
  INSERT INTO f360.commerce_sync_state (target_id) VALUES (t.id) ON CONFLICT (target_id) DO NOTHING;
  SELECT * INTO s FROM f360.commerce_sync_state WHERE target_id = t.id FOR UPDATE;
  IF p_lookback_hours IS NOT NULL THEN
    v_after := clock_timestamp() - make_interval(hours => p_lookback_hours); v_mode := 'deep';
  ELSIF s.cursor_modified IS NOT NULL THEN
    v_after := s.cursor_modified - interval '10 minutes'; v_mode := 'incremental';
  ELSE
    -- first run: from the cutover order (production) so nothing between the cutover and the first run is skipped
    SELECT o.woo_created_at - interval '1 day' INTO v_after FROM f360.commerce_woo_orders o
      WHERE o.target_id = t.id AND v_since IS NOT NULL AND o.woo_order_id = v_since;
    v_after := coalesce(v_after, clock_timestamp() - interval '72 hours'); v_mode := 'first_run';
  END IF;
  INSERT INTO f360.commerce_sync_runs (target_id, kind, modified_after) VALUES (t.id, 'reconcile', v_after) RETURNING id INTO v_id;
  UPDATE f360.commerce_sync_state SET last_attempt_at = clock_timestamp() WHERE target_id = t.id;
  RETURN jsonb_build_object('run_id', v_id, 'modified_after', v_after, 'orders_since_id', v_since, 'mode', v_mode);
END $$;

CREATE FUNCTION public.f360_commerce_reconcile_diff(p_target_key text, p_orders jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; v_since bigint; res jsonb;
BEGIN
  t := f360.sg0_order_target(p_target_key);
  IF jsonb_typeof(p_orders) IS DISTINCT FROM 'array' OR jsonb_array_length(p_orders) > 500 THEN
    RAISE EXCEPTION 'Lista de pedidos no válida (máximo 500 por página).';
  END IF;
  v_since := nullif(to_jsonb(t)->>'orders_since_id', '')::bigint;
  WITH w AS (
    SELECT DISTINCT ON ((x->>'id')::bigint) (x->>'id')::bigint AS id, f360.commerce_ts(x->>'date_modified_gmt') AS m
    FROM jsonb_array_elements(p_orders) x WHERE (x->>'id') ~ '^[1-9][0-9]{0,17}$'),
  c AS (
    SELECT w.id, w.m, o.woo_order_id IS NOT NULL AS known, o.woo_modified_at
    FROM w LEFT JOIN f360.commerce_woo_orders o ON o.target_id = t.id AND o.woo_order_id = w.id)
  SELECT jsonb_build_object(
    'missing', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE NOT c.known AND (v_since IS NULL OR c.id > v_since)), '[]'),
    'before_cutover_missing', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE NOT c.known AND v_since IS NOT NULL AND c.id <= v_since), '[]'),
    'outdated', coalesce(jsonb_agg(c.id ORDER BY c.id) FILTER (WHERE c.known AND c.m IS NOT NULL AND c.m > c.woo_modified_at), '[]'),
    'current', count(*) FILTER (WHERE c.known AND NOT (c.m IS NOT NULL AND c.m > c.woo_modified_at)),
    'orders_since_id', v_since)
  INTO res FROM c;
  RETURN res;
END $$;

-- Production appears when its ORDER path is on (it was hidden by `active AND NOT is_production`). Same columns.
CREATE OR REPLACE VIEW f360.commerce_source_health AS
  SELECT t.key AS target_key, s.last_attempt_at, s.last_success_at, s.last_error, s.last_error_at, s.cursor_modified,
         (SELECT max(d.received_at) FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.result IN ('applied', 'not_paid', 'duplicate')) AS last_webhook_at,
         CASE WHEN s.last_success_at IS NULL THEN 'UNVERIFIED'
              WHEN s.last_success_at < now() - interval '60 minutes' THEN 'STALE'
              ELSE 'VERIFIED' END AS freshness
  FROM f360.sales_targets t LEFT JOIN f360.commerce_sync_state s ON s.target_id = t.id
  WHERE f360.sg0_orders_path_on(t);

-- + orders_mode / orders_since_id (NULL where the column does not exist yet). Same signature, same callers.
CREATE OR REPLACE FUNCTION public.f360_channel_mode(p_target_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('key', key, 'is_production', is_production, 'active', active, 'catalog_mode', catalog_mode,
    'stock_sync_mode', stock_sync_mode, 'stock_policy', stock_policy,
    'orders_mode', to_jsonb(t)->'orders_mode', 'orders_since_id', to_jsonb(t)->'orders_since_id')
  FROM f360.sales_targets t WHERE key = p_target_key
$$;

REVOKE ALL ON FUNCTION public.f360_commerce_reconcile_begin(text, integer), public.f360_commerce_reconcile_diff(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_commerce_reconcile_begin(text, integer), public.f360_commerce_reconcile_diff(text, jsonb) TO service_role;
REVOKE ALL ON f360.commerce_source_health FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.commerce_source_health TO service_role;
REVOKE ALL ON FUNCTION public.f360_channel_mode(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_channel_mode(text) TO service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000100', 'f360_sg0_order_reconciliation', '{}');

-- ════════ 20261014000200_f360_sg0_marketing_spend.sql ════════
-- Fuxia 360 · S-G0 Measurement Truth · D3 MARKETING SPEND storage (Mario 2026-10-08). Spec: 09_GROWTH_IMPLEMENTATION_PLAN.md
-- objects 3-4, 03_GROWTH_COCKPIT.md §2.2. ADDITIVE, empty on creation: NO spend is invented or seeded.
--   · Primary source (later): read-only API connectors (Meta Marketing API insights, Google Ads) — architecture only, no
--     credentials exist; they will write through the same import tables with source = 'api'.
--   · Fallback (now): controlled CSV / manual import by an OWNER through public.f360_marketing_spend_upload. The server
--     validates every row; a file with ANY invalid row is REJECTED whole (nothing loaded) and the attempt is still logged
--     (who, when, file name, hash, errors). Same content twice = the first import (idempotent).
--   · Append-only: an import is never edited. Platforms restate spend for past days, so a newer accepted import that covers
--     a (platform, account, day) REPLACES the older one for that day in f360.marketing_spend_daily (the older rows stay as
--     history). An import can be voided (owner, with reason) and the previous one reappears.
--   · A day without a row is UNKNOWN, never zero: export days with 0 spend explicitly. Amounts in the ACCOUNT currency, never
--     converted here (FX: f360.fx_rates, 20261014000300).
--   · Aggregates only: campaign / ad set / ad / creative ids and names, spend, impressions, clicks. No personal data.
--   · Read: owner / operator (D-G1-05; spend is not for sellers / viewers). Tables: service role only.
-- Rollback: supabase/rollbacks/20261014000200_f360_sg0_marketing_spend.down.sql

CREATE TABLE f360.marketing_spend_imports (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  platform         text NOT NULL CHECK (platform IN ('meta', 'google', 'tiktok', 'other')),
  source           text NOT NULL CHECK (source IN ('csv', 'manual', 'api')),
  file_name        text CHECK (file_name IS NULL OR length(file_name) <= 200),
  content_sha256   text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
  row_count        integer NOT NULL CHECK (row_count >= 0),
  date_from        date,
  date_to          date,
  accounts         text[] NOT NULL DEFAULT '{}',
  currencies       text[] NOT NULL DEFAULT '{}',
  spend_by_currency jsonb NOT NULL DEFAULT '{}',
  status           text NOT NULL CHECK (status IN ('accepted', 'rejected', 'voided')),
  errors           jsonb,                                   -- rejected: [{row, field, error}] (first 50)
  uploaded_by      uuid NOT NULL,
  uploaded_by_name text NOT NULL,
  uploaded_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  voided_by        uuid,
  voided_by_name   text,
  voided_at        timestamptz,
  void_reason      text CHECK (void_reason IS NULL OR length(void_reason) BETWEEN 3 AND 300),
  CONSTRAINT spend_import_void CHECK ((status = 'voided') = (voided_at IS NOT NULL))
);
CREATE UNIQUE INDEX marketing_spend_imports_one_accepted ON f360.marketing_spend_imports (platform, content_sha256) WHERE status = 'accepted';

CREATE TABLE f360.marketing_spend_rows (
  import_id      uuid NOT NULL REFERENCES f360.marketing_spend_imports(id) ON DELETE RESTRICT,
  row_no         integer NOT NULL CHECK (row_no > 0),
  date           date NOT NULL,
  market         text NOT NULL CHECK (market IN ('MX', 'CO', 'ROW', 'UNKNOWN')),
  platform       text NOT NULL CHECK (platform IN ('meta', 'google', 'tiktok', 'other')),
  account_id     text NOT NULL CHECK (account_id ~ '^[A-Za-z0-9_.:-]{1,64}$'),
  campaign_id    text NOT NULL CHECK (campaign_id ~ '^[A-Za-z0-9_.:-]{1,64}$'),
  campaign_name  text CHECK (length(campaign_name) <= 300),
  adset_id       text CHECK (adset_id ~ '^[A-Za-z0-9_.:-]{1,64}$'),
  adset_name     text CHECK (length(adset_name) <= 300),
  ad_id          text CHECK (ad_id ~ '^[A-Za-z0-9_.:-]{1,64}$'),
  ad_name        text CHECK (length(ad_name) <= 300),
  creative_id    text CHECK (creative_id ~ '^[A-Za-z0-9_.:-]{1,64}$'),
  currency       text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  spend          numeric(14,2) NOT NULL CHECK (spend >= 0),
  impressions    bigint CHECK (impressions >= 0),
  clicks         bigint CHECK (clicks >= 0),
  PRIMARY KEY (import_id, row_no)
);
CREATE INDEX marketing_spend_rows_day_idx ON f360.marketing_spend_rows (platform, account_id, date);

CREATE TRIGGER marketing_spend_rows_append_only BEFORE UPDATE OR DELETE ON f360.marketing_spend_rows
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
-- imports: only accepted → voided (with who / when / why); nothing else ever changes; never deleted
CREATE FUNCTION f360.marketing_spend_import_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Una importación de gasto no se borra; se anula.'; END IF;
  IF OLD.status = 'accepted' AND NEW.status = 'voided' AND NEW.voided_at IS NOT NULL AND NEW.voided_by IS NOT NULL
     AND (to_jsonb(NEW) - ARRAY['status', 'voided_by', 'voided_by_name', 'voided_at', 'void_reason'])
       = (to_jsonb(OLD) - ARRAY['status', 'voided_by', 'voided_by_name', 'voided_at', 'void_reason']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Una importación de gasto no se modifica (solo se puede anular).';
END $$;
CREATE TRIGGER marketing_spend_imports_guard BEFORE UPDATE OR DELETE ON f360.marketing_spend_imports
  FOR EACH ROW EXECUTE FUNCTION f360.marketing_spend_import_guard();

-- Effective spend: for each (platform, account, day) the rows of the NEWEST accepted import that covers that day.
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

-- Server-side validation of one row (NULL = valid; else the error text). Pure.
CREATE FUNCTION f360.marketing_spend_row_error(x jsonb, p_today date) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d date; sp numeric;
BEGIN
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' THEN RETURN 'fila no válida'; END IF;
  IF coalesce(x->>'date', '') !~ '^\d{4}-\d{2}-\d{2}$' THEN RETURN 'date: usa AAAA-MM-DD'; END IF;
  BEGIN d := (x->>'date')::date; EXCEPTION WHEN OTHERS THEN RETURN 'date: fecha inexistente'; END;
  IF d < DATE '2020-01-01' OR d > p_today THEN RETURN 'date: fuera de rango (no futura)'; END IF;
  IF coalesce(x->>'market', '') NOT IN ('MX', 'CO', 'ROW', 'UNKNOWN') THEN RETURN 'market: MX, CO, ROW o UNKNOWN'; END IF;
  IF coalesce(x->>'account_id', '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RETURN 'account_id: requerido (letras, números, _ . : -)'; END IF;
  IF coalesce(x->>'campaign_id', '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RETURN 'campaign_id: requerido (letras, números, _ . : -)'; END IF;
  IF nullif(x->>'adset_id', '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RETURN 'adset_id: formato no válido'; END IF;
  IF nullif(x->>'ad_id', '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RETURN 'ad_id: formato no válido'; END IF;
  IF nullif(x->>'creative_id', '') !~ '^[A-Za-z0-9_.:-]{1,64}$' THEN RETURN 'creative_id: formato no válido'; END IF;
  IF length(x->>'campaign_name') > 300 OR length(x->>'adset_name') > 300 OR length(x->>'ad_name') > 300 THEN RETURN 'nombre demasiado largo (300)'; END IF;
  IF coalesce(x->>'currency', '') !~ '^[A-Z]{3}$' THEN RETURN 'currency: código ISO de 3 letras'; END IF;
  IF coalesce(x->>'spend', '') !~ '^\d{1,10}(\.\d{1,2})?$' THEN RETURN 'spend: número ≥ 0 con máximo 2 decimales (sin símbolos ni comas)'; END IF;
  sp := (x->>'spend')::numeric;
  IF nullif(x->>'impressions', '') !~ '^\d{1,15}$' THEN RETURN 'impressions: entero ≥ 0'; END IF;
  IF nullif(x->>'clicks', '') !~ '^\d{1,15}$' THEN RETURN 'clicks: entero ≥ 0'; END IF;
  RETURN NULL;
END $$;

CREATE FUNCTION public.f360_marketing_spend_upload(p_platform text, p_source text, p_file_name text, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); v_today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  v_hash text; v_errors jsonb := '[]'; v_id uuid; v_dup uuid; v_row jsonb; i int := 0; e text; n int;
BEGIN
  IF p_platform NOT IN ('meta', 'google', 'tiktok', 'other') THEN RAISE EXCEPTION 'Plataforma no válida.'; END IF;
  IF p_source NOT IN ('csv', 'manual') THEN RAISE EXCEPTION 'Origen no válido (csv o manual).'; END IF;   -- 'api' = service connectors only
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) = 0 THEN RAISE EXCEPTION 'El archivo no tiene filas.'; END IF;
  IF jsonb_array_length(p_rows) > 5000 THEN RAISE EXCEPTION 'Máximo 5,000 filas por importación.'; END IF;
  v_hash := encode(sha256(convert_to(p_platform || ':' || p_rows::text, 'UTF8')), 'hex');
  SELECT id INTO v_dup FROM f360.marketing_spend_imports WHERE platform = p_platform AND content_sha256 = v_hash AND status = 'accepted';
  IF v_dup IS NOT NULL THEN RETURN jsonb_build_object('ok', true, 'result', 'duplicate', 'import_id', v_dup); END IF;

  FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    i := i + 1;
    e := f360.marketing_spend_row_error(v_row, v_today);
    IF e IS NULL AND coalesce(v_row->>'platform', p_platform) <> p_platform THEN e := 'platform: la fila no es de ' || p_platform; END IF;
    IF e IS NOT NULL THEN v_errors := v_errors || jsonb_build_object('row', i, 'error', e); END IF;
    EXIT WHEN jsonb_array_length(v_errors) >= 50;
  END LOOP;
  IF jsonb_array_length(v_errors) = 0 THEN
    -- same (account, day, campaign, ad set, ad) twice in one file
    SELECT count(*) INTO n FROM (SELECT 1 FROM jsonb_array_elements(p_rows) x
      GROUP BY x->>'account_id', x->>'date', x->>'campaign_id', coalesce(x->>'adset_id', ''), coalesce(x->>'ad_id', '') HAVING count(*) > 1) d;
    IF n > 0 THEN v_errors := v_errors || jsonb_build_object('row', NULL, 'error', n || ' combinaciones cuenta/día/campaña/conjunto/anuncio repetidas en el archivo'); END IF;
    -- one currency per ad account
    SELECT count(*) INTO n FROM (SELECT 1 FROM jsonb_array_elements(p_rows) x GROUP BY x->>'account_id' HAVING count(DISTINCT x->>'currency') > 1) d;
    IF n > 0 THEN v_errors := v_errors || jsonb_build_object('row', NULL, 'error', 'una cuenta publicitaria con más de una moneda'); END IF;
    -- an account already loaded in another currency
    SELECT count(*) INTO n FROM (SELECT DISTINCT x->>'account_id' a, x->>'currency' c FROM jsonb_array_elements(p_rows) x) f
      WHERE EXISTS (SELECT 1 FROM f360.marketing_spend_daily d WHERE d.platform = p_platform AND d.account_id = f.a AND d.currency <> f.c);
    IF n > 0 THEN v_errors := v_errors || jsonb_build_object('row', NULL, 'error', 'la moneda no coincide con la ya cargada para esa cuenta'); END IF;
  END IF;

  IF jsonb_array_length(v_errors) > 0 THEN
    INSERT INTO f360.marketing_spend_imports (platform, source, file_name, content_sha256, row_count, status, errors, uploaded_by, uploaded_by_name)
      VALUES (p_platform, p_source, left(nullif(btrim(p_file_name), ''), 200), v_hash, jsonb_array_length(p_rows), 'rejected', v_errors, r.auth_user_id, r.display_name)
      RETURNING id INTO v_id;
    RETURN jsonb_build_object('ok', false, 'result', 'rejected', 'import_id', v_id, 'errors', v_errors);
  END IF;

  INSERT INTO f360.marketing_spend_imports (platform, source, file_name, content_sha256, row_count, date_from, date_to, accounts, currencies,
      spend_by_currency, status, uploaded_by, uploaded_by_name)
    SELECT p_platform, p_source, left(nullif(btrim(p_file_name), ''), 200), v_hash, count(*), min((x->>'date')::date), max((x->>'date')::date),
           array_agg(DISTINCT x->>'account_id'), array_agg(DISTINCT x->>'currency'),
           (SELECT jsonb_object_agg(c, s) FROM (SELECT y->>'currency' c, sum((y->>'spend')::numeric) s FROM jsonb_array_elements(p_rows) y GROUP BY 1) z),
           'accepted', r.auth_user_id, r.display_name
    FROM jsonb_array_elements(p_rows) x
    RETURNING id INTO v_id;
  INSERT INTO f360.marketing_spend_rows (import_id, row_no, date, market, platform, account_id, campaign_id, campaign_name, adset_id, adset_name,
      ad_id, ad_name, creative_id, currency, spend, impressions, clicks)
    SELECT v_id, o, (x->>'date')::date, x->>'market', p_platform, x->>'account_id', x->>'campaign_id', nullif(btrim(x->>'campaign_name'), ''),
           nullif(x->>'adset_id', ''), nullif(btrim(x->>'adset_name'), ''), nullif(x->>'ad_id', ''), nullif(btrim(x->>'ad_name'), ''),
           nullif(x->>'creative_id', ''), x->>'currency', (x->>'spend')::numeric, nullif(x->>'impressions', '')::bigint, nullif(x->>'clicks', '')::bigint
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(x, o);
  RETURN jsonb_build_object('ok', true, 'result', 'accepted', 'import_id', v_id, 'rows', jsonb_array_length(p_rows));
END $$;

CREATE FUNCTION public.f360_marketing_spend_void(p_import_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  UPDATE f360.marketing_spend_imports SET status = 'voided', voided_by = r.auth_user_id, voided_by_name = r.display_name,
      voided_at = clock_timestamp(), void_reason = left(btrim(p_reason), 300)
    WHERE id = p_import_id AND status = 'accepted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Importación no encontrada o ya anulada.'; END IF;
  RETURN jsonb_build_object('ok', true, 'import_id', p_import_id);
END $$;

-- Import log for the admin (owner / operator): who uploaded what, when, accepted / rejected / voided. No rows of spend.
CREATE FUNCTION public.f360_marketing_spend_imports(p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(i) - 'uploaded_by' - 'voided_by' - 'content_sha256' ORDER BY i.uploaded_at DESC), '[]')
          FROM (SELECT * FROM f360.marketing_spend_imports ORDER BY uploaded_at DESC LIMIT greatest(1, least(coalesce(p_limit, 50), 200))) i);
END $$;

ALTER TABLE f360.marketing_spend_imports ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.marketing_spend_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.marketing_spend_imports, f360.marketing_spend_rows, f360.marketing_spend_daily FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.marketing_spend_imports, f360.marketing_spend_rows TO service_role;
GRANT SELECT ON f360.marketing_spend_daily TO service_role;
REVOKE ALL ON FUNCTION f360.marketing_spend_row_error(jsonb, date), f360.marketing_spend_import_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_marketing_spend_upload(text, text, text, jsonb), public.f360_marketing_spend_void(uuid, text),
  public.f360_marketing_spend_imports(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_marketing_spend_upload(text, text, text, jsonb), public.f360_marketing_spend_void(uuid, text),
  public.f360_marketing_spend_imports(integer) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000200', 'f360_sg0_marketing_spend', '{}');

-- ════════ 20261014000300_f360_sg0_fx_rates.sql ════════
-- Fuxia 360 · S-G0 Measurement Truth · D7 CURRENCY (Mario 2026-10-08). Spec: 02_MEASUREMENT_TRUTH.md §2.5 (D-FX), 09 object 12.
-- ADDITIVE, empty on creation: NO rate is invented or seeded.
--   · Every sale / spend keeps its ORIGINAL currency forever; nothing is converted in storage.
--   · Base management currency = MXN. A MONTHLY rate, APPROVED by an owner, is the only rate used to show a consolidated
--     (CONVERTED) figure for Board reporting, always next to the original-currency figures.
--   · Missing approved rate for a month/currency that a consolidation needs → that consolidated figure is DATA INCOMPLETE
--     (NULL), never a silent conversion, never 0 (f360.fx_rate_for returns NULL).
--   · Versioned and append-only: a row is proposed (operator / owner), then approved (owner) or voided (owner, with reason).
--     rate / currency / period never change; a correction = void + new proposal. One live (proposed/approved) row per
--     currency × base × month.
-- Coordination: f360.fx_rates is OWNED by S-G0; Strategy & Board (SB0) references it, it does not create it.
-- Rollback: supabase/rollbacks/20261014000300_f360_sg0_fx_rates.down.sql

CREATE TABLE f360.fx_rates (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  currency         text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  base_currency    text NOT NULL DEFAULT 'MXN' CHECK (base_currency = 'MXN'),
  period           date NOT NULL CHECK (period = date_trunc('month', period)::date),   -- first day of the month
  rate             numeric(20,8) NOT NULL CHECK (rate > 0 AND rate < 1000000),       -- base units per 1 unit of currency
  source           text NOT NULL CHECK (length(btrim(source)) BETWEEN 2 AND 120),      -- e.g. "Banxico FIX promedio mensual"
  notes            text CHECK (notes IS NULL OR length(notes) <= 500),
  status           text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'approved', 'voided')),
  proposed_by      uuid NOT NULL,
  proposed_by_name text NOT NULL,
  proposed_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  approved_by      uuid,
  approved_by_name text,
  approved_at      timestamptz,
  voided_by        uuid,
  voided_by_name   text,
  voided_at        timestamptz,
  void_reason      text,
  CONSTRAINT fx_not_base CHECK (currency <> base_currency),
  CONSTRAINT fx_approved CHECK ((status = 'approved') <= (approved_at IS NOT NULL AND approved_by IS NOT NULL)),
  CONSTRAINT fx_voided CHECK ((status = 'voided') = (voided_at IS NOT NULL))
);
CREATE UNIQUE INDEX fx_rates_one_live ON f360.fx_rates (currency, base_currency, period) WHERE status IN ('proposed', 'approved');

-- Only proposed → approved, proposed/approved → voided; the economic fields never change; never deleted.
CREATE FUNCTION f360.fx_rates_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text[] := ARRAY['status', 'approved_by', 'approved_by_name', 'approved_at', 'voided_by', 'voided_by_name', 'voided_at', 'void_reason'];
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un tipo de cambio no se borra; se anula.'; END IF;
  IF (to_jsonb(NEW) - k) <> (to_jsonb(OLD) - k) THEN RAISE EXCEPTION 'Un tipo de cambio no se modifica: anúlalo y propone uno nuevo.'; END IF;
  IF NOT ((OLD.status = 'proposed' AND NEW.status IN ('approved', 'voided')) OR (OLD.status = 'approved' AND NEW.status = 'voided')) THEN
    RAISE EXCEPTION 'Cambio de estado no permitido (% → %).', OLD.status, NEW.status;
  END IF;
  IF OLD.approved_at IS NOT NULL AND (NEW.approved_at IS DISTINCT FROM OLD.approved_at OR NEW.approved_by IS DISTINCT FROM OLD.approved_by) THEN
    RAISE EXCEPTION 'La aprobación no se reescribe.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER fx_rates_guard BEFORE UPDATE OR DELETE ON f360.fx_rates FOR EACH ROW EXECUTE FUNCTION f360.fx_rates_guard();

-- The approved rate for (currency, month); 1 for the base currency; NULL when not approved (→ DATA INCOMPLETE upstream).
CREATE FUNCTION f360.fx_rate_for(p_currency text, p_period date) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN p_currency = 'MXN' THEN 1::numeric
              ELSE (SELECT rate FROM f360.fx_rates WHERE currency = p_currency AND base_currency = 'MXN'
                      AND period = date_trunc('month', p_period)::date AND status = 'approved') END $$;

CREATE FUNCTION public.f360_fx_rate_propose(p_currency text, p_period date, p_rate numeric, p_source text, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); v_id uuid; v_cur text := upper(btrim(coalesce(p_currency, '')));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = v_cur) OR v_cur = 'MXN' THEN RAISE EXCEPTION 'Moneda no válida (COP, USD…; MXN es la base).'; END IF;
  IF p_period IS NULL OR p_period > (now() AT TIME ZONE 'America/Mexico_City')::date THEN RAISE EXCEPTION 'Mes no válido (no futuro).'; END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN RAISE EXCEPTION 'El tipo de cambio debe ser mayor que 0.'; END IF;
  IF length(btrim(coalesce(p_source, ''))) < 2 THEN RAISE EXCEPTION 'Indica la fuente del tipo de cambio.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE currency = v_cur AND period = date_trunc('month', p_period)::date AND status IN ('proposed', 'approved')) THEN
    RAISE EXCEPTION 'Ya hay un tipo de cambio para % en ese mes: anúlalo antes de proponer otro.', v_cur;
  END IF;
  INSERT INTO f360.fx_rates (currency, period, rate, source, notes, proposed_by, proposed_by_name)
    VALUES (v_cur, date_trunc('month', p_period)::date, p_rate, btrim(p_source), nullif(btrim(coalesce(p_notes, '')), ''), r.auth_user_id, r.display_name)
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'status', 'proposed');
END $$;

CREATE FUNCTION public.f360_fx_rate_approve(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  UPDATE f360.fx_rates SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = clock_timestamp()
    WHERE id = p_id AND status = 'proposed';
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o no está propuesto.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved');
END $$;

CREATE FUNCTION public.f360_fx_rate_void(p_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  UPDATE f360.fx_rates SET status = 'voided', voided_by = r.auth_user_id, voided_by_name = r.display_name, voided_at = clock_timestamp(),
      void_reason = left(btrim(p_reason), 300)
    WHERE id = p_id AND status IN ('proposed', 'approved');
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o ya anulado.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'voided');
END $$;

CREATE FUNCTION public.f360_fx_rates_list() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(f) - 'proposed_by' - 'approved_by' - 'voided_by' ORDER BY f.period DESC, f.currency, f.proposed_at DESC), '[]')
          FROM f360.fx_rates f);
END $$;

ALTER TABLE f360.fx_rates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.fx_rates FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.fx_rates TO service_role;
REVOKE ALL ON FUNCTION f360.fx_rates_guard(), f360.fx_rate_for(text, date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.fx_rate_for(text, date) TO service_role;
REVOKE ALL ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text), public.f360_fx_rate_approve(uuid),
  public.f360_fx_rate_void(uuid, text), public.f360_fx_rates_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text), public.f360_fx_rate_approve(uuid),
  public.f360_fx_rate_void(uuid, text), public.f360_fx_rates_list() TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000300', 'f360_sg0_fx_rates', '{}');

-- ════════ 20261014000400_f360_sg0_product_cost.sql ════════
-- Fuxia 360 · S-G0 Measurement Truth · D5 PRODUCT COST (Mario 2026-10-08: Fuxia 360 is the source of product cost, VERSIONED).
-- ADDITIVE, empty on creation: NO current cost is invented or seeded.
--   · One row = one cost VERSION for a scope: product (required) + variant (optional) + market (optional), amount + currency,
--     effective_from / effective_to, source, notes, created_by, approved_by.
--   · History is never overwritten: a new cost is a NEW row. Approving a version closes the previous open approved version of the
--     same scope (its effective_to = new effective_from − 1 day) — the ONLY change ever made to an existing approved row.
--     Everything else is immutable (trigger); rows are never deleted; a wrong proposal is rejected, not edited.
--   · Approved versions must not overlap: a version that starts on or before an existing approved start of the same scope
--     is refused (backdating = an explicit decision, documented in S-G0_DELIVERY.md).
--   · Write: propose = owner / operator; approve / reject = owner. Read: owner / operator. Cost is financial data: never sellers.
-- Coordination: f360.product_cost_versions is OWNED by S-G0; Strategy & Board (SB0) reads it.
-- Rollback: supabase/rollbacks/20261014000400_f360_sg0_product_cost.down.sql

CREATE TABLE f360.product_cost_versions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id       uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  variant_id       uuid REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  market           text CHECK (market IN ('MX', 'CO', 'ROW')),
  cost_amount      numeric(12,2) NOT NULL CHECK (cost_amount > 0 AND cost_amount < 10000000),
  currency         text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  effective_from   date NOT NULL,
  effective_to     date,
  source           text NOT NULL CHECK (source IN ('supplier_invoice', 'production_order', 'accounting', 'owner_estimate', 'other')),
  notes            text CHECK (notes IS NULL OR length(notes) <= 500),
  status           text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'approved', 'rejected')),
  created_by       uuid NOT NULL,
  created_by_name  text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  approved_by      uuid,
  approved_by_name text,
  approved_at      timestamptz,
  rejected_reason  text,
  CONSTRAINT pcv_period CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CONSTRAINT pcv_approval CHECK ((status IN ('approved', 'rejected')) = (approved_at IS NOT NULL AND approved_by IS NOT NULL))
);
CREATE INDEX product_cost_versions_scope_idx ON f360.product_cost_versions (product_id, variant_id, market, effective_from);
COMMENT ON TABLE f360.product_cost_versions IS 'S-G0 D5: versioned product cost (source of truth = Fuxia 360). New cost = new row; history never overwritten.';
COMMENT ON COLUMN f360.product_cost_versions.approved_by IS 'Owner who approved OR rejected the version (status says which).';

CREATE FUNCTION f360.product_cost_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text[] := ARRAY['status', 'approved_by', 'approved_by_name', 'approved_at', 'rejected_reason', 'effective_to'];
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Un costo no se borra: el historial se conserva.'; END IF;
  IF (to_jsonb(NEW) - k) <> (to_jsonb(OLD) - k) THEN RAISE EXCEPTION 'Un costo no se modifica: registra una versión nueva.'; END IF;
  IF OLD.status = 'proposed' AND NEW.status IN ('approved', 'rejected') AND NEW.effective_to IS NOT DISTINCT FROM OLD.effective_to THEN RETURN NEW; END IF;
  -- closing an approved open version when the next one is approved (only effective_to, only once)
  IF OLD.status = 'approved' AND NEW.status = 'approved' AND OLD.effective_to IS NULL AND NEW.effective_to IS NOT NULL
     AND NEW.approved_at = OLD.approved_at AND NEW.approved_by = OLD.approved_by THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'Cambio no permitido en un costo (% → %).', OLD.status, NEW.status;
END $$;
CREATE TRIGGER product_cost_versions_guard BEFORE UPDATE OR DELETE ON f360.product_cost_versions
  FOR EACH ROW EXECUTE FUNCTION f360.product_cost_guard();

-- Approved cost timeline (what was valid when). Never includes proposals.
CREATE VIEW f360.product_cost_effective AS
  SELECT c.id, c.product_id, c.variant_id, c.market, c.cost_amount, c.currency, c.effective_from, c.effective_to, c.source,
         c.created_by_name, c.approved_by_name, c.approved_at
  FROM f360.product_cost_versions c WHERE c.status = 'approved';

CREATE FUNCTION public.f360_product_cost_propose(p_product_id uuid, p_variant_id uuid, p_market text, p_amount numeric, p_currency text,
  p_effective_from date, p_source text, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); v_id uuid; v_cur text := upper(btrim(coalesce(p_currency, '')));
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF p_variant_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = p_variant_id AND product_id = p_product_id) THEN
    RAISE EXCEPTION 'La variante no es de este producto.';
  END IF;
  IF p_market IS NOT NULL AND p_market NOT IN ('MX', 'CO', 'ROW') THEN RAISE EXCEPTION 'Mercado no válido (MX, CO, ROW o vacío).'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) THEN RAISE EXCEPTION 'El costo debe ser mayor que 0 (máximo 2 decimales).'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = v_cur) THEN RAISE EXCEPTION 'Moneda no válida.'; END IF;
  IF p_effective_from IS NULL THEN RAISE EXCEPTION 'Indica desde cuándo vale este costo.'; END IF;
  IF p_source NOT IN ('supplier_invoice', 'production_order', 'accounting', 'owner_estimate', 'other') THEN RAISE EXCEPTION 'Fuente del costo no válida.'; END IF;
  INSERT INTO f360.product_cost_versions (product_id, variant_id, market, cost_amount, currency, effective_from, source, notes, created_by, created_by_name)
    VALUES (p_product_id, p_variant_id, p_market, p_amount, v_cur, p_effective_from, p_source, nullif(btrim(coalesce(p_notes, '')), ''), r.auth_user_id, r.display_name)
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'status', 'proposed');
END $$;

CREATE FUNCTION public.f360_product_cost_decide(p_id uuid, p_approve boolean, p_reason text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); v f360.product_cost_versions; v_closed uuid;
BEGIN
  SELECT * INTO v FROM f360.product_cost_versions WHERE id = p_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'proposed' THEN RAISE EXCEPTION 'Costo no encontrado o ya decidido.'; END IF;
  IF NOT coalesce(p_approve, false) THEN
    IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Escribe el motivo del rechazo.'; END IF;
    UPDATE f360.product_cost_versions SET status = 'rejected', approved_by = r.auth_user_id, approved_by_name = r.display_name,
        approved_at = clock_timestamp(), rejected_reason = left(btrim(p_reason), 300) WHERE id = p_id;
    RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'rejected');
  END IF;
  -- one decision at a time per scope
  PERFORM pg_advisory_xact_lock(hashtextextended('product_cost:' || v.product_id || ':' || coalesce(v.variant_id::text, '') || ':' || coalesce(v.market, ''), 0));
  IF EXISTS (SELECT 1 FROM f360.product_cost_versions c WHERE c.status = 'approved' AND c.product_id = v.product_id
               AND c.variant_id IS NOT DISTINCT FROM v.variant_id AND c.market IS NOT DISTINCT FROM v.market AND c.effective_from >= v.effective_from) THEN
    RAISE EXCEPTION 'Ya hay un costo aprobado que empieza en esa fecha o después: no se reescribe la historia.';
  END IF;
  UPDATE f360.product_cost_versions c SET effective_to = v.effective_from - 1
    WHERE c.status = 'approved' AND c.product_id = v.product_id AND c.variant_id IS NOT DISTINCT FROM v.variant_id
      AND c.market IS NOT DISTINCT FROM v.market AND c.effective_to IS NULL
    RETURNING c.id INTO v_closed;
  UPDATE f360.product_cost_versions SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name,
      approved_at = clock_timestamp() WHERE id = p_id;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved', 'closed_previous', v_closed);
END $$;

CREATE FUNCTION public.f360_product_cost_history(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(to_jsonb(c) - 'created_by' - 'approved_by' ORDER BY c.variant_id NULLS FIRST, c.market NULLS FIRST, c.effective_from DESC, c.created_at DESC), '[]')
          FROM f360.product_cost_versions c WHERE c.product_id = p_product_id);
END $$;

ALTER TABLE f360.product_cost_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.product_cost_versions, f360.product_cost_effective FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.product_cost_versions TO service_role;
GRANT SELECT ON f360.product_cost_effective TO service_role;
REVOKE ALL ON FUNCTION f360.product_cost_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_product_cost_propose(uuid, uuid, text, numeric, text, date, text, text), public.f360_product_cost_decide(uuid, boolean, text),
  public.f360_product_cost_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_product_cost_propose(uuid, uuid, text, numeric, text, date, text, text), public.f360_product_cost_decide(uuid, boolean, text),
  public.f360_product_cost_history(uuid) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000400', 'f360_sg0_product_cost', '{}');

-- ════════ 20261014000500_f360_sg0_legacy_store_sales.sql ════════
-- Fuxia 360 · S-G0 Measurement Truth · D8 LEGACY STORE SALES (Mario 2026-10-08: incorporate the legacy store sales — the
-- public.offline_sales rows NOT created by the Fuxia 360 sale RPC (created_by_rpc = false; legacy channel_inventory flow) —
-- for commercial history, unmistakably source = LEGACY_IMPORT; never pretend they came from the current flow).
-- ADDITIVE. NO COPY of the sale: public.offline_sales stays the record (one source of truth). This table is the audited
-- DECISION that a legacy sale enters commercial history, with the validation that was run on it:
--   · imported      → counts in the measurement layer (f360.measurement_sales, 20261014000600) as LEGACY_IMPORT, quality PARTIAL;
--   · needs_review  → does NOT count until a person decides (e.g. its day falls inside one of Carolina's bazaar / store-month
--                     summaries in f360.historical_sales → it may already be inside that summary: counting both = double count).
-- Validation (server-side, f360.legacy_sale_check): not an RPC sale; total > 0; items present with quantity > 0 and price ≥ 0;
-- Σ quantity × unit_price = total (± 0.01); date sane; location resolved through locations.legacy_channel_id (else PARTIAL);
-- possible overlap with an active historical summary of the same place / a bazaar on the same days (→ needs_review).
-- Importing is idempotent (a sale is registered once; re-running registers only new legacy sales) and owner-only, with a
-- dry run that changes nothing. f360.commerce_orders / f360_commerce_summary / f360_exec_dashboard are NOT changed:
-- their numbers stay exactly as before (CLAUDE.md rule 13); legacy sales appear only in the S-G0 measurement layer.
-- Rollback: supabase/rollbacks/20261014000500_f360_sg0_legacy_store_sales.down.sql

CREATE TABLE f360.legacy_store_sale_imports (
  sale_id          uuid PRIMARY KEY REFERENCES public.offline_sales(id) ON DELETE RESTRICT,
  source           text NOT NULL DEFAULT 'LEGACY_IMPORT' CHECK (source = 'LEGACY_IMPORT'),
  status           text NOT NULL CHECK (status IN ('imported', 'needs_review')),
  location_id      uuid REFERENCES f360.locations(id) ON DELETE RESTRICT,   -- resolved via locations.legacy_channel_id (NULL = unresolved)
  validation       jsonb NOT NULL,                                          -- {issues:[...], total, items_total, units, sale_date}
  batch_id         uuid NOT NULL,
  imported_by      uuid NOT NULL,
  imported_by_name text NOT NULL,
  imported_at      timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TRIGGER legacy_store_sale_imports_append_only BEFORE UPDATE OR DELETE ON f360.legacy_store_sale_imports
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
COMMENT ON TABLE f360.legacy_store_sale_imports IS 'S-G0 D8: audited decision that a legacy store sale (offline_sales, created_by_rpc=false) enters commercial history as LEGACY_IMPORT. Not a copy.';

-- Validation of ONE legacy sale (pure read). Returns {ok_to_import, issues[], location_id, total, items_total, units, sale_date}.
CREATE FUNCTION f360.legacy_sale_check(p_sale_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s public.offline_sales; v_items numeric := 0; v_units int := 0; v_bad int := 0; v_n int := 0; v_loc uuid; v_ch_type text;
  v_day date; issues text[] := '{}'; blocking text[] := '{}';
BEGIN
  SELECT * INTO s FROM public.offline_sales WHERE id = p_sale_id;
  IF s.id IS NULL THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('sale_not_found')); END IF;
  IF s.created_by_rpc THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('not_legacy_created_by_f360_rpc')); END IF;
  v_day := (s.created_at AT TIME ZONE 'America/Mexico_City')::date;
  IF jsonb_typeof(s.items) = 'array' THEN
    SELECT count(*), coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'
                                        THEN (e->>'quantity')::numeric * (e->>'unit_price')::numeric END), 0),
           coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' THEN (e->>'quantity')::int END), 0),
           count(*) FILTER (WHERE NOT ((e->>'quantity') ~ '^[1-9]\d*$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'))
      INTO v_n, v_items, v_units, v_bad
      FROM jsonb_array_elements(s.items) e;
  END IF;
  IF v_n = 0 THEN blocking := array_append(blocking, 'no_items'); END IF;
  IF v_bad > 0 THEN blocking := array_append(blocking, 'item_quantity_or_price_invalid'); END IF;
  IF s.total IS NULL OR s.total <= 0 THEN blocking := array_append(blocking, 'total_not_positive'); END IF;
  IF v_n > 0 AND abs(coalesce(s.total, 0) - v_items) > 0.01 THEN blocking := array_append(blocking, 'total_does_not_match_items'); END IF;
  IF v_day < DATE '2020-01-01' OR s.created_at > now() THEN blocking := array_append(blocking, 'date_out_of_range'); END IF;
  SELECT l.id INTO v_loc FROM f360.locations l WHERE s.channel_id IS NOT NULL AND l.legacy_channel_id = s.channel_id LIMIT 1;
  SELECT c.type INTO v_ch_type FROM public.channels c WHERE c.id = s.channel_id;
  IF v_loc IS NULL THEN issues := array_append(issues, 'location_unresolved'); END IF;
  -- possible double count with Carolina's historical summaries (same place / a bazaar on the same days)
  IF EXISTS (SELECT 1 FROM f360.historical_sales h WHERE h.status = 'active' AND v_day BETWEEN h.period_start AND h.period_end
               AND ((v_loc IS NOT NULL AND h.location_id = v_loc) OR (h.location_id IS NULL AND h.kind = 'bazaar' AND coalesce(v_ch_type, '') IN ('bazar', 'bazaar')))) THEN
    blocking := array_append(blocking, 'possible_overlap_historical_summary');
  END IF;
  issues := array_append(blocking || issues, 'currency_implied_mxn');
  RETURN jsonb_build_object('ok_to_import', cardinality(blocking) = 0, 'issues', to_jsonb(issues), 'location_id', v_loc,
    'total', s.total, 'items_total', round(v_items, 2), 'units', v_units, 'sale_date', v_day);
END $$;

-- Owner only. p_dry_run (default TRUE) reports and changes nothing. Real run: registers every legacy sale not registered yet:
-- valid → 'imported'; any blocking issue → 'needs_review'. Re-running is a no-op for sales already registered.
CREATE FUNCTION public.f360_legacy_store_sales_import(p_dry_run boolean DEFAULT true) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); v_batch uuid := gen_random_uuid(); s record; chk jsonb;
  n_cand int := 0; n_imp int := 0; n_rev int := 0; issues jsonb := '{}'::jsonb; i text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('legacy_store_sales_import', 0));
  FOR s IN SELECT o.id FROM public.offline_sales o
           WHERE NOT o.created_by_rpc AND NOT EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports li WHERE li.sale_id = o.id)
           ORDER BY o.created_at, o.id LOOP
    n_cand := n_cand + 1;
    chk := f360.legacy_sale_check(s.id);
    FOR i IN SELECT jsonb_array_elements_text(chk->'issues') LOOP
      issues := jsonb_set(issues, ARRAY[i], to_jsonb(coalesce((issues->>i)::int, 0) + 1));
    END LOOP;
    IF (chk->>'ok_to_import')::boolean THEN n_imp := n_imp + 1; ELSE n_rev := n_rev + 1; END IF;
    IF NOT coalesce(p_dry_run, true) THEN
      INSERT INTO f360.legacy_store_sale_imports (sale_id, status, location_id, validation, batch_id, imported_by, imported_by_name)
        VALUES (s.id, CASE WHEN (chk->>'ok_to_import')::boolean THEN 'imported' ELSE 'needs_review' END,
                nullif(chk->>'location_id', '')::uuid, chk - 'ok_to_import' - 'location_id', v_batch, r.auth_user_id, r.display_name)
        ON CONFLICT (sale_id) DO NOTHING;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('dry_run', coalesce(p_dry_run, true), 'batch_id', CASE WHEN NOT coalesce(p_dry_run, true) THEN v_batch END,
    'candidates', n_cand, 'imported', n_imp, 'needs_review', n_rev, 'issues', issues,
    'already_registered', (SELECT count(*) FROM f360.legacy_store_sale_imports),
    'legacy_total', (SELECT count(*) FROM public.offline_sales WHERE NOT created_by_rpc));
END $$;

ALTER TABLE f360.legacy_store_sale_imports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.legacy_store_sale_imports FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.legacy_store_sale_imports TO service_role;
REVOKE ALL ON FUNCTION f360.legacy_sale_check(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_legacy_store_sales_import(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_legacy_store_sales_import(boolean) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000500', 'f360_sg0_legacy_store_sales', '{}');

-- ════════ 20261014000600_f360_sg0_measurement_truth.sql ════════
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

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261014000600', 'f360_sg0_measurement_truth', '{}');

-- ════════ 20261016000200_f360_sg0_tax_pending.sql ════════
-- Fuxia 360 · S-G0 · TAX STATUS = PENDING ACCOUNTING CONFIRMATION (Mario 2026-10-08, pre-production gate decision 7).
-- Corrects 20261014000600 where it ASSUMED a tax treatment:
--   · its comment said "store prices include IVA" and labelled every sale without a Woo tax line 'included_not_separated'
--     — an unproven assumption (Woo tax = 0 does NOT prove there is no IVA, nor that IVA is included);
--   · product_net_before_tax was filled from product_net whenever Woo reported a tax line — a net-of-tax figure built on the
--     assumption that Woo's tax configuration is the accounting truth.
-- Now (view keeps the same columns, same order, + tax_status at the end; CREATE OR REPLACE, dependants untouched):
--   · every amount stays the RAW transaction amount in its original currency (nothing recomputed, nothing removed);
--   · product_net_before_tax = NULL for every sale (DATA INCOMPLETE until accounting confirms the treatment);
--   · iva_treatment only states a FACT about the source: 'tax_amount_reported_by_source' / 'tax_not_separated_by_source';
--   · tax_status = 'PENDING_ACCOUNTING_CONFIRMATION' on every sale; f360_measurement_truth.q8 says the basis is RAW and
--     returns net_of_tax = DATA_INCOMPLETE (value NULL); f360_measurement_sales_list returns tax_status.
--   · the Board metric catalog definition of revenue_net_product says the same (only if SB0 is present).
-- Open accounting questions (docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md §IVA): MX web prices include IVA? store prices?
-- Colombia equivalent? shipping tax? discount tax? No figure, rule or default is changed beyond the labels above.
-- Rollback: supabase/rollbacks/20261016000200_f360_sg0_tax_pending.down.sql

CREATE OR REPLACE VIEW f360.measurement_sales AS
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
         NULL::numeric AS product_net_before_tax,                                   -- DATA INCOMPLETE until accounting confirms
         c.tax AS tax_iva, CASE WHEN c.tax <> 0 THEN 'tax_amount_reported_by_source' ELSE 'tax_not_separated_by_source' END AS iva_treatment,
         c.shipping AS shipping_charged, c.fees, c.refund_total AS refunds, c.refund_product AS refunds_product,
         c.net_product AS net_product_revenue, c.net_order_total AS total_collected, c.units,
         c.data_quality, c.data_quality_reasons, c.provenance,
         'PENDING_ACCOUNTING_CONFIRMATION'::text AS tax_status
  FROM f360.commerce_orders c
  LEFT JOIN f360.commerce_woo_orders o ON o.target_id = c.target_id AND o.woo_order_id = c.woo_order_id
  LEFT JOIN f360.sales_targets t ON t.id = c.target_id
  UNION ALL
  SELECT 'legacy_store_sale:' || s.id, 'legacy_store', 'legacy_store', 'LEGACY_IMPORT', 'legacy_import', li.imported_at, false,
         NULL, NULL, s.id, li.location_id,
         s.created_at, s.created_at, (s.created_at AT TIME ZONE 'America/Mexico_City')::date,
         'legacy_recorded', CASE WHEN li.status = 'imported' THEN 'countable' ELSE 'needs_review' END, 'paid', li.status = 'imported',
         'MX', 'MXN', NULL,
         s.total, 0, s.total, NULL::numeric, 0, 'tax_not_separated_by_source', 0, 0, 0, 0, s.total, s.total, coalesce((li.validation->>'units')::int, 0),
         'PARTIAL', ARRAY(SELECT jsonb_array_elements_text(li.validation->'issues')) || ARRAY['legacy_import'], 'offline_sales:legacy_import',
         'PENDING_ACCOUNTING_CONFIRMATION'::text
  FROM f360.legacy_store_sale_imports li JOIN public.offline_sales s ON s.id = li.sale_id;

CREATE OR REPLACE FUNCTION public.f360_measurement_truth(p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
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
      'basis', 'net_product_revenue = Σ line totals after coupons, before shipping, minus product refunds; paid sales only; RAW transaction amounts as charged (tax treatment PENDING ACCOUNTING CONFIRMATION — not net of tax)',
      'tax_status', 'PENDING_ACCOUNTING_CONFIRMATION', 'net_of_tax', jsonb_build_object('status', 'DATA_INCOMPLETE', 'value', NULL, 'missing', jsonb_build_array('accounting_confirmation_of_iva_treatment'))),
    -- 9 · do we have spend?
    'q9_spend', jsonb_build_object(
      'status', (SELECT s->>'status' FROM jsonb_array_elements(h) s WHERE s->>'key' = 'marketing_spend'),
      'by_currency', (SELECT coalesce(jsonb_agg(jsonb_build_object('platform', platform, 'currency', currency, 'spend', v, 'days', d) ORDER BY platform, currency), '[]') FROM (
          SELECT platform, currency, sum(spend) v, count(DISTINCT date) d FROM f360.marketing_spend_daily
          WHERE (p_from IS NULL OR date >= p_from) AND (p_to IS NULL OR date <= p_to) GROUP BY 1, 2) y)),
    -- 10 · efficiency KPIs: never 0 when an input is missing
    'q10_efficiency', f360.sg0_efficiency_kpis(p_from, p_to)));
END $$;

CREATE OR REPLACE FUNCTION public.f360_measurement_sales_list(p_limit integer DEFAULT 100, p_from date DEFAULT NULL, p_to date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); incl boolean := f360.sg0_include_tests();
BEGIN
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY x->>'business_date' DESC, x->>'sale_ref' DESC), '[]') FROM (
    SELECT jsonb_build_object('sale_ref', m.sale_ref, 'sales_channel', m.sales_channel, 'capture_source', m.capture_source, 'timing', m.timing_class,
      'imported_at', m.imported_at, 'business_date', m.business_date, 'status', m.status, 'status_class', m.status_class, 'paid', m.is_paid_sale,
      'market', m.market, 'currency', m.currency, 'net_product_revenue', m.net_product_revenue, 'total_collected', m.total_collected,
      'iva_treatment', m.iva_treatment, 'tax_status', m.tax_status, 'quality', m.data_quality, 'quality_reasons', to_jsonb(m.data_quality_reasons), 'test_channel', m.is_test_channel) AS x
    FROM f360.measurement_sales m
    WHERE (incl OR NOT m.is_test_channel) AND (p_from IS NULL OR m.business_date >= p_from) AND (p_to IS NULL OR m.business_date <= p_to)
    ORDER BY m.business_date DESC, m.sale_ref DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 500))) q);
END $$;

DO $$ BEGIN
  IF to_regclass('f360_board.metric_catalog') IS NOT NULL THEN
    UPDATE f360_board.metric_catalog
       SET definition = 'Producto cobrado − cupones − reembolsos de producto, pedidos countable, en moneda original. Montos BRUTOS tal como se cobraron: tratamiento de IVA PENDIENTE DE CONFIRMACIÓN CONTABLE (no es neto de impuestos).'
     WHERE metric_key = 'revenue_net_product';
  END IF;
END $$;

COMMENT ON VIEW f360.measurement_sales IS 'S-G0: one row per sale (online / store / legacy store) with capture source and D6 revenue components, original currency, RAW amounts; tax_status PENDING_ACCOUNTING_CONFIRMATION (no net-of-tax figure). No PII.';
REVOKE ALL ON f360.measurement_sales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.measurement_sales TO service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261016000200', 'f360_sg0_tax_pending', '{}');

-- ════════ 20261016000300_f360_sg0_fx_source_documentation.sql ════════
-- Fuxia 360 · S-G0 · FX: DOCUMENTED / OFFICIAL SOURCE + MONTHLY LOAD + APPROVAL (Mario 2026-10-08, pre-production decision 6).
-- Builds on 20261014000300 (f360.fx_rates: monthly, base MXN, proposed → approved by an owner, void with reason, immutable).
-- Adds the documentation every rate must carry so anyone can re-derive it:
--   · source_reference   URL or document reference of the publication (e.g. Banxico SIE series SF43718 page, Banco de la
--                        República TRM page, or the accountant's file name);
--   · source_retrieved_on the date the figure was read from that source;
--   · rate_method        how the monthly figure was obtained: MONTHLY_AVERAGE | MONTH_END | OTHER (OTHER needs notes).
-- f360_fx_rate_propose now REQUIRES them (new signature; the old 5-argument one is dropped — nothing in the admin or the
-- functions calls it; only test_sg0_measurement.sql, updated in the same change). The table must be empty when this runs
-- (it is: 0 rows in staging; not yet created in production); a CHECK then makes the documentation mandatory for every row.
-- Base MXN; initially COP→MXN and USD→MXN (f360.currencies decides which codes are valid). NO rate is seeded or invented:
-- months without an approved rate stay DATA INCOMPLETE (f360.fx_rate_for returns NULL). Monthly procedure:
-- docs/fuxia360/PRE_PRODUCTION_GATE_S-G0_SB0.md §FX.
-- Rollback: supabase/rollbacks/20261016000300_f360_sg0_fx_source_documentation.down.sql

ALTER TABLE f360.fx_rates
  ADD COLUMN source_reference    text CHECK (source_reference IS NULL OR length(btrim(source_reference)) BETWEEN 4 AND 500),
  ADD COLUMN source_retrieved_on date,
  ADD COLUMN rate_method         text CHECK (rate_method IS NULL OR rate_method IN ('MONTHLY_AVERAGE', 'MONTH_END', 'OTHER'));
-- Every row must be documented. The table is empty in staging and does not exist yet in production (created empty by
-- 20261014000300 in the same gate), so the constraint is validated; if a row existed the migration would stop here (safe).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.fx_rates) THEN RAISE EXCEPTION 'ABORT: f360.fx_rates has rows; document or void them first.'; END IF;
END $$;
ALTER TABLE f360.fx_rates ADD CONSTRAINT fx_documented
  CHECK (source_reference IS NOT NULL AND source_retrieved_on IS NOT NULL AND rate_method IS NOT NULL);
ALTER TABLE f360.fx_rates ADD CONSTRAINT fx_retrieved_after_period CHECK (source_retrieved_on >= period);
COMMENT ON COLUMN f360.fx_rates.source IS 'Source NAME (e.g. "Banxico FIX promedio mensual", "Banco de la República TRM promedio mensual (cruce vía USD)")';

DROP FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text);
CREATE FUNCTION public.f360_fx_rate_propose(p_currency text, p_period date, p_rate numeric, p_source text, p_source_reference text,
  p_retrieved_on date, p_rate_method text, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); v_id uuid; v_cur text := upper(btrim(coalesce(p_currency, '')));
  v_method text := upper(btrim(coalesce(p_rate_method, ''))); today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.currencies WHERE code = v_cur) OR v_cur = 'MXN' THEN RAISE EXCEPTION 'Moneda no válida (COP, USD…; MXN es la base).'; END IF;
  IF p_period IS NULL OR p_period > today THEN RAISE EXCEPTION 'Mes no válido (no futuro).'; END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN RAISE EXCEPTION 'El tipo de cambio debe ser mayor que 0.'; END IF;
  IF length(btrim(coalesce(p_source, ''))) < 2 THEN RAISE EXCEPTION 'Indica la fuente del tipo de cambio.'; END IF;
  IF length(btrim(coalesce(p_source_reference, ''))) < 4 THEN RAISE EXCEPTION 'Indica la referencia de la fuente (liga o documento).'; END IF;
  IF p_retrieved_on IS NULL OR p_retrieved_on > today OR p_retrieved_on < date_trunc('month', p_period)::date THEN
    RAISE EXCEPTION 'Indica la fecha en que se consultó la fuente (no futura, no antes del mes).';
  END IF;
  IF v_method NOT IN ('MONTHLY_AVERAGE', 'MONTH_END', 'OTHER') THEN RAISE EXCEPTION 'Método: MONTHLY_AVERAGE, MONTH_END u OTHER.'; END IF;
  IF v_method = 'OTHER' AND length(btrim(coalesce(p_notes, ''))) < 5 THEN RAISE EXCEPTION 'Con método OTHER explica cómo se obtuvo en las notas.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE currency = v_cur AND period = date_trunc('month', p_period)::date AND status IN ('proposed', 'approved')) THEN
    RAISE EXCEPTION 'Ya hay un tipo de cambio para % en ese mes: anúlalo antes de proponer otro.', v_cur;
  END IF;
  INSERT INTO f360.fx_rates (currency, period, rate, source, notes, proposed_by, proposed_by_name, source_reference, source_retrieved_on, rate_method)
    VALUES (v_cur, date_trunc('month', p_period)::date, p_rate, btrim(p_source), nullif(btrim(coalesce(p_notes, '')), ''), r.auth_user_id, r.display_name,
            btrim(p_source_reference), p_retrieved_on, v_method)
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'status', 'proposed');
END $$;

CREATE OR REPLACE FUNCTION public.f360_fx_rate_approve(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE id = p_id AND status = 'proposed'
               AND (source_reference IS NULL OR source_retrieved_on IS NULL OR rate_method IS NULL)) THEN
    RAISE EXCEPTION 'Este tipo de cambio no tiene la fuente documentada (referencia, fecha de consulta, método): anúlalo y propón uno documentado.';
  END IF;
  UPDATE f360.fx_rates SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = clock_timestamp()
    WHERE id = p_id AND status = 'proposed';
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o no está propuesto.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved');
END $$;

REVOKE ALL ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text, date, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text, date, text, text) TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261016000300', 'f360_sg0_fx_source_documentation', '{}');

-- ════════ 20261016000400_f360_sg0_spend_sources_state.sql ════════
-- Fuxia 360 · S-G0 · MARKETING SPEND SOURCE STATE (Mario 2026-10-08, pre-production decision 5). CONFIGURATION ONLY.
--   · Meta Ads: Fuxia DOES spend on Meta (spend_expected = true) but there is NO reliable integrated source yet →
--     config_status stays NOT_CONFIGURED until a valid CSV is loaded (f360_marketing_spend_upload) or a read-only API exists.
--     Effect: marketing_spend health stays NOT_CONFIGURED (no rows) and MER / CAC / ROAS keep value NULL + DATA_INCOMPLETE
--     with "meta_ads_spend_days_missing" (never 0, never computed without Meta's spend).
--   · Google Ads: spend NOT CONFIRMED → spend_expected stays NULL (UNKNOWN), config NOT_CONFIGURED; never assumed $0
--     (efficiency KPIs report "unknown_if_google_ads_has_spend").
-- Values are set by key; nothing else in measurement_sources changes. Later changes go through f360_measurement_source_set
-- (owner) as before.
-- Rollback: supabase/rollbacks/20261016000400_f360_sg0_spend_sources_state.down.sql
UPDATE f360.measurement_sources
   SET spend_expected = true, config_status = 'NOT_CONFIGURED',
       notes = 'Mario 2026-10-08: hay gasto en Meta; sin fuente integrada confiable → NOT_CONFIGURED hasta CSV válido o API de solo lectura.',
       updated_by_name = 'migración 20261016000400 (decisión Mario 2026-10-08)', updated_at = now()
 WHERE key = 'meta_ads';
UPDATE f360.measurement_sources
   SET spend_expected = NULL, config_status = 'NOT_CONFIGURED',
       notes = 'Mario 2026-10-08: gasto en Google Ads NO confirmado → desconocido (nunca $0) hasta confirmarlo.',
       updated_by_name = 'migración 20261016000400 (decisión Mario 2026-10-08)', updated_at = now()
 WHERE key = 'google_ads';
DO $$ BEGIN
  IF (SELECT count(*) FROM f360.measurement_sources WHERE key IN ('meta_ads', 'google_ads')) <> 2 THEN
    RAISE EXCEPTION 'ABORT: measurement_sources rows meta_ads / google_ads missing (20261014000600 first).';
  END IF;
END $$;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261016000400', 'f360_sg0_spend_sources_state', '{}');

-- ════════ 20261016000500_f360_sg0_bazaar_reconciliation.sql ════════
-- Fuxia 360 · S-G0 · BAZAAR LEGACY SALES ⇄ CAROLINA'S BAZAAR SUMMARIES — RECONCILIATION PREVIEW + GUARD
-- (Mario 2026-10-08, pre-production decision 8). READ-ONLY preview; nothing is imported, summed, written or deleted.
-- Problem: production has 28 legacy individual sales on the legacy bazaar channel "Guadalajara" (public.offline_sales,
-- created_by_rpc = false, legacy POS app) AND Carolina's 2 bazaar summaries in f360.historical_sales (GDL 22–24 Sep,
-- Querétaro El Campanario 29 Sep–1 Oct). Adding both would double count whatever the summary already contains.
-- Classification of every legacy BAZAAR sale (channel type bazar/bazaar) against ACTIVE bazaar summaries:
--   · UNMATCHED        no summary within 2 days of the sale day → the individual sale is the only record (may count, after the
--                      normal legacy validation of 20261014000500);
--   · MATCHED          inside ONE summary's dates, same place, and the individual sales inside that window add up to the
--                      summary amount (±1 %) → the summary and the sales are the same money: the SUMMARY is the record, the
--                      individual sale never counts on top;
--   · LIKELY_DUPLICATE inside ONE summary's dates, same place, totals do not reconcile → the summary probably contains it;
--   · AMBIGUOUS        near a summary's dates (±2 days), or a summary of ANOTHER place on the same days, or several summaries.
--   Place = normalized words of the legacy channel name/location vs the summary name (accents, punctuation, GDL/QRO/MTY/CDMX
--   aliases); dates in America/Mexico_City.
-- GUARD (financial truth): only UNMATCHED legacy bazaar sales can ever count. MATCHED / LIKELY_DUPLICATE / AMBIGUOUS
--   · are blocking issues in f360.legacy_sale_check → f360_legacy_store_sales_import registers them as needs_review;
--   · are excluded LIVE in f360.measurement_sales (is_paid_sale false, status_class needs_review) even if an earlier import
--     registered them as 'imported' (e.g. Carolina loads a summary later). Resolution = a person's decision (future step).
-- Objects: f360.bazaar_sale_classification() (same SELECT as tools/preprod/bazaar_preview_prod.sql, run read-only on prod),
-- public.f360_bazaar_reconciliation_preview() (owner / operator; no customer data: sale ids, days, channel, amounts only).
-- Rollback: supabase/rollbacks/20261016000500_f360_sg0_bazaar_reconciliation.down.sql

CREATE FUNCTION f360.bazaar_sale_classification()
RETURNS TABLE (sale_id uuid, sale_day date, total numeric, channel_name text, summary_id uuid, summary_name text, class text, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH s AS (
    SELECT o.id AS sale_id, (o.created_at AT TIME ZONE 'America/Mexico_City')::date AS sale_day, o.total, c.name AS channel_name,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(c.name || ' ' || coalesce(c.location, ''), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS place_norm
    FROM public.offline_sales o LEFT JOIN public.channels c ON c.id = o.channel_id
    WHERE NOT o.created_by_rpc AND lower(coalesce(c.type, '')) IN ('bazar', 'bazaar')),
  h AS (
    SELECT hs.id AS summary_id, coalesce(l.name, hs.bazaar_name) AS summary_name, hs.period_start, hs.period_end, hs.amount, hs.pairs,
           regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(' ' || btrim(regexp_replace(translate(lower(coalesce(coalesce(l.name, hs.bazaar_name), '')), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', ' ', 'g')) || ' ', ' gdl ', ' guadalajara ', 'g'), ' qro ', ' queretaro ', 'g'), ' mty ', ' monterrey ', 'g'), ' cdmx ', ' ciudad de mexico ', 'g'), ' df ', ' ciudad de mexico ', 'g') AS name_norm
    FROM f360.historical_sales hs LEFT JOIN f360.locations l ON l.id = hs.location_id
    WHERE hs.status = 'active' AND hs.kind = 'bazaar'),
  cand AS (
    SELECT s.sale_id, h.summary_id, s.sale_day BETWEEN h.period_start AND h.period_end AS in_window,
           EXISTS (SELECT 1 FROM regexp_split_to_table(btrim(s.place_norm), ' ') w
                   WHERE length(w) >= 4 AND w NOT IN ('bazar', 'bazaar', 'tienda', 'fuxia', 'store', 'ciudad', 'mexico')
                     AND position(' ' || w || ' ' IN h.name_norm) > 0) AS name_match
    FROM s JOIN h ON s.sale_day BETWEEN h.period_start - 2 AND h.period_end + 2),
  agg AS (
    SELECT s.sale_id, count(c.summary_id) AS n_cand, count(c.summary_id) FILTER (WHERE c.in_window AND c.name_match) AS n_strict,
           (array_agg(c.summary_id ORDER BY (c.in_window AND c.name_match) DESC, c.name_match DESC) FILTER (WHERE c.summary_id IS NOT NULL))[1] AS summary_id,
           bool_or(c.in_window AND NOT c.name_match) AS other_place_same_days, bool_or(NOT c.in_window) AS near_edge
    FROM s LEFT JOIN cand c ON c.sale_id = s.sale_id GROUP BY s.sale_id),
  win AS (
    SELECT c.summary_id, sum(s.total) AS sales_total, count(*) AS sales_n
    FROM cand c JOIN s ON s.sale_id = c.sale_id WHERE c.in_window AND c.name_match GROUP BY c.summary_id),
  cls AS (
    SELECT s.sale_id, s.sale_day, s.total, s.channel_name, a.summary_id, h.summary_name,
           CASE WHEN a.n_cand = 0 THEN 'UNMATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'MATCHED'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'LIKELY_DUPLICATE'
                ELSE 'AMBIGUOUS' END AS class,
           CASE WHEN a.n_cand = 0 THEN 'no_bazaar_summary_within_2_days'
                WHEN a.n_cand = 1 AND a.n_strict = 1 AND abs(w.sales_total - h.amount) <= greatest(1, 0.01 * h.amount) THEN 'window_sales_total_equals_summary_amount'
                WHEN a.n_cand = 1 AND a.n_strict = 1 THEN 'inside_summary_dates_same_place'
                WHEN a.n_cand > 1 THEN 'several_summaries_nearby'
                WHEN a.other_place_same_days THEN 'summary_of_another_place_on_same_days'
                WHEN a.near_edge THEN 'within_2_days_of_summary_dates'
                ELSE 'unclear' END AS reason
    FROM s JOIN agg a ON a.sale_id = s.sale_id LEFT JOIN h ON h.summary_id = a.summary_id LEFT JOIN win w ON w.summary_id = a.summary_id)
  SELECT sale_id, sale_day, total, channel_name, summary_id, summary_name, class, reason FROM cls
$$;
COMMENT ON FUNCTION f360.bazaar_sale_classification() IS 'S-G0 pre-prod: classification of legacy bazaar sales vs active bazaar summaries (UNMATCHED / MATCHED / LIKELY_DUPLICATE / AMBIGUOUS). Read-only.';

CREATE FUNCTION public.f360_bazaar_reconciliation_preview() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN (WITH c AS (SELECT * FROM f360.bazaar_sale_classification())
  SELECT jsonb_build_object(
    'kind', 'PREVIEW_READ_ONLY', 'generated_at', now(), 'timezone', 'America/Mexico_City', 'currency', 'MXN',
    'rule', 'Only UNMATCHED legacy bazaar sales may count; MATCHED (summary is the record), LIKELY_DUPLICATE and AMBIGUOUS never count until a person resolves them.',
    'by_class', (SELECT coalesce(jsonb_object_agg(class, x), '{}') FROM (
        SELECT class, jsonb_build_object('sales', count(*), 'total', sum(total), 'first_day', min(sale_day), 'last_day', max(sale_day),
                 'channels', jsonb_agg(DISTINCT channel_name), 'counts_in_financial_truth', class = 'UNMATCHED') x
        FROM c GROUP BY class) q),
    'summaries', (SELECT coalesce(jsonb_agg(jsonb_build_object('summary_id', h.id, 'name', coalesce(l.name, h.bazaar_name), 'from', h.period_start, 'to', h.period_end,
          'amount', h.amount, 'pairs', h.pairs,
          'legacy_sales_linked', (SELECT count(*) FROM c WHERE c.summary_id = h.id),
          'legacy_total_linked', (SELECT coalesce(sum(total), 0) FROM c WHERE c.summary_id = h.id),
          'linked_by_class', (SELECT coalesce(jsonb_object_agg(class, n), '{}') FROM (SELECT class, count(*) n FROM c WHERE c.summary_id = h.id GROUP BY class) y))
          ORDER BY h.period_start), '[]')
        FROM f360.historical_sales h LEFT JOIN f360.locations l ON l.id = h.location_id WHERE h.status = 'active' AND h.kind = 'bazaar'),
    'sales', (SELECT coalesce(jsonb_agg(jsonb_build_object('sale_ref', sale_id, 'day', sale_day, 'channel', channel_name, 'total', total,
          'class', class, 'reason', reason, 'summary', summary_name) ORDER BY sale_day, sale_id), '[]') FROM c)));
END $$;

CREATE OR REPLACE FUNCTION f360.legacy_sale_check(p_sale_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s public.offline_sales; v_items numeric := 0; v_units int := 0; v_bad int := 0; v_n int := 0; v_loc uuid; v_ch_type text;
  v_day date; issues text[] := '{}'; blocking text[] := '{}'; v_bz text;
BEGIN
  SELECT * INTO s FROM public.offline_sales WHERE id = p_sale_id;
  IF s.id IS NULL THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('sale_not_found')); END IF;
  IF s.created_by_rpc THEN RETURN jsonb_build_object('ok_to_import', false, 'issues', jsonb_build_array('not_legacy_created_by_f360_rpc')); END IF;
  v_day := (s.created_at AT TIME ZONE 'America/Mexico_City')::date;
  IF jsonb_typeof(s.items) = 'array' THEN
    SELECT count(*), coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'
                                        THEN (e->>'quantity')::numeric * (e->>'unit_price')::numeric END), 0),
           coalesce(sum(CASE WHEN (e->>'quantity') ~ '^\d+$' THEN (e->>'quantity')::int END), 0),
           count(*) FILTER (WHERE NOT ((e->>'quantity') ~ '^[1-9]\d*$' AND (e->>'unit_price') ~ '^\d+(\.\d+)?$'))
      INTO v_n, v_items, v_units, v_bad
      FROM jsonb_array_elements(s.items) e;
  END IF;
  IF v_n = 0 THEN blocking := array_append(blocking, 'no_items'); END IF;
  IF v_bad > 0 THEN blocking := array_append(blocking, 'item_quantity_or_price_invalid'); END IF;
  IF s.total IS NULL OR s.total <= 0 THEN blocking := array_append(blocking, 'total_not_positive'); END IF;
  IF v_n > 0 AND abs(coalesce(s.total, 0) - v_items) > 0.01 THEN blocking := array_append(blocking, 'total_does_not_match_items'); END IF;
  IF v_day < DATE '2020-01-01' OR s.created_at > now() THEN blocking := array_append(blocking, 'date_out_of_range'); END IF;
  SELECT l.id INTO v_loc FROM f360.locations l WHERE s.channel_id IS NOT NULL AND l.legacy_channel_id = s.channel_id LIMIT 1;
  SELECT c.type INTO v_ch_type FROM public.channels c WHERE c.id = s.channel_id;
  IF v_loc IS NULL THEN issues := array_append(issues, 'location_unresolved'); END IF;
  -- possible double count with Carolina's historical summaries (same place / a bazaar on the same days)
  IF EXISTS (SELECT 1 FROM f360.historical_sales h WHERE h.status = 'active' AND v_day BETWEEN h.period_start AND h.period_end
               AND ((v_loc IS NOT NULL AND h.location_id = v_loc) OR (h.location_id IS NULL AND h.kind = 'bazaar' AND coalesce(v_ch_type, '') IN ('bazar', 'bazaar')))) THEN
    blocking := array_append(blocking, 'possible_overlap_historical_summary');
  END IF;
  -- pre-prod decision 8: a legacy BAZAAR sale counts only when no Carolina bazaar summary may contain it
  SELECT bc.class INTO v_bz FROM f360.bazaar_sale_classification() bc WHERE bc.sale_id = p_sale_id;
  IF v_bz IS NOT NULL AND v_bz <> 'UNMATCHED' THEN blocking := array_append(blocking, 'bazaar_reconciliation_' || lower(v_bz)); END IF;
  issues := array_append(blocking || issues, 'currency_implied_mxn');
  RETURN jsonb_build_object('ok_to_import', cardinality(blocking) = 0, 'issues', to_jsonb(issues), 'location_id', v_loc,
    'total', s.total, 'items_total', round(v_items, 2), 'units', v_units, 'sale_date', v_day);
END $$;

CREATE OR REPLACE VIEW f360.measurement_sales AS
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
         NULL::numeric AS product_net_before_tax,                                   -- DATA INCOMPLETE until accounting confirms
         c.tax AS tax_iva, CASE WHEN c.tax <> 0 THEN 'tax_amount_reported_by_source' ELSE 'tax_not_separated_by_source' END AS iva_treatment,
         c.shipping AS shipping_charged, c.fees, c.refund_total AS refunds, c.refund_product AS refunds_product,
         c.net_product AS net_product_revenue, c.net_order_total AS total_collected, c.units,
         c.data_quality, c.data_quality_reasons, c.provenance,
         'PENDING_ACCOUNTING_CONFIRMATION'::text AS tax_status
  FROM f360.commerce_orders c
  LEFT JOIN f360.commerce_woo_orders o ON o.target_id = c.target_id AND o.woo_order_id = c.woo_order_id
  LEFT JOIN f360.sales_targets t ON t.id = c.target_id
  UNION ALL
  SELECT 'legacy_store_sale:' || s.id, 'legacy_store', 'legacy_store', 'LEGACY_IMPORT', 'legacy_import', li.imported_at, false,
         NULL, NULL, s.id, li.location_id,
         s.created_at, s.created_at, (s.created_at AT TIME ZONE 'America/Mexico_City')::date,
         'legacy_recorded', CASE WHEN li.status = 'imported' AND coalesce(bc.class, 'UNMATCHED') = 'UNMATCHED' THEN 'countable' ELSE 'needs_review' END, 'paid',
         li.status = 'imported' AND coalesce(bc.class, 'UNMATCHED') = 'UNMATCHED',
         'MX', 'MXN', NULL,
         s.total, 0, s.total, NULL::numeric, 0, 'tax_not_separated_by_source', 0, 0, 0, 0, s.total, s.total, coalesce((li.validation->>'units')::int, 0),
         'PARTIAL', ARRAY(SELECT jsonb_array_elements_text(li.validation->'issues')) || ARRAY['legacy_import']
           || CASE WHEN bc.class IS NOT NULL AND bc.class <> 'UNMATCHED' THEN ARRAY['bazaar_reconciliation_' || lower(bc.class)] ELSE '{}'::text[] END, 'offline_sales:legacy_import',
         'PENDING_ACCOUNTING_CONFIRMATION'::text
  FROM f360.legacy_store_sale_imports li JOIN public.offline_sales s ON s.id = li.sale_id
  LEFT JOIN f360.bazaar_sale_classification() bc ON bc.sale_id = s.id;

REVOKE ALL ON f360.measurement_sales FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.measurement_sales TO service_role;
REVOKE ALL ON FUNCTION f360.bazaar_sale_classification() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION f360.bazaar_sale_classification() TO service_role;
REVOKE ALL ON FUNCTION public.f360_bazaar_reconciliation_preview() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_bazaar_reconciliation_preview() TO authenticated, service_role;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261016000500', 'f360_sg0_bazaar_reconciliation', '{}');

-- Post-checks (inside the same transaction): nothing was imported or activated by this gate.
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports) OR EXISTS (SELECT 1 FROM f360.fx_rates) OR EXISTS (SELECT 1 FROM f360.marketing_spend_imports)
     OR EXISTS (SELECT 1 FROM f360.product_cost_versions) THEN RAISE EXCEPTION 'ABORT: P0B must not load data'; END IF;
  IF EXISTS (SELECT 1 FROM f360.commerce_sync_runs WHERE kind = 'reconcile') THEN RAISE EXCEPTION 'ABORT: reconciliation ran inside P0B'; END IF;
  IF (SELECT stock_sync_mode FROM f360.sales_targets WHERE key = 'woo_production') <> 'off' THEN RAISE EXCEPTION 'ABORT: stock sync changed'; END IF;
  IF (SELECT count(*) FROM f360.measurement_sales WHERE tax_status <> 'PENDING_ACCOUNTING_CONFIRMATION' OR product_net_before_tax IS NOT NULL) > 0 THEN RAISE EXCEPTION 'ABORT: tax status'; END IF;
END $$;
COMMIT;
