-- Fuxia 360 · I0 Tipo de cambio diario (Mario 2026-10-11, Centro de Inteligencia §5, aprobado para STAGING).
-- Builds on 20261014000300 + 20261016000300 (f360.fx_rates: monthly, base MXN, documented, proposed → approved, immutable).
-- ADDITIVE:
--   · f360.fx_observations — append-only daily history (base MXN = pesos per 1 unit). One row per day × currency × role × source;
--     a revised figure is a NEW row (the newest retrieval wins in f360.fx_daily). Never updated or deleted.
--       role primary   = official: USD = Banxico FIX as published in the DOF; COP = FIX ÷ TRM Banco de la República (cross via USD).
--       role reference = ExchangeRate-API (open access), only to detect inconsistencies; never used for a monthly rate.
--       role manual    = typed by an owner (e.g. Mario's 0.0057 of 2026-10-11), kept for traceability; never used for a monthly rate.
--   · f360_fx_month_propose(month) — proposes the MONTHLY_AVERAGE of the primary observations of a CLOSED month into
--     f360.fx_rates (status proposed, proposer = "Sistema · lectura diaria"). It never approves.
--   · f360.approval_scopes — who may approve what (scope fx_rate | budget | close). Mario 2026-10-11: the monthly FX rate
--     "requiere aprobación de Mario"; budgets are approved by Mario; the close by Mario or Carolina. Empty scope = nobody (the
--     list is data loaded per environment, never by this migration). f360_fx_rate_approve now also requires scope fx_rate.
--   · f360.fx_rate_for_report(currency, month) — the rate the reports apply + how it was chosen (approved / provisional = last
--     approved month, only for the current open month / missing). Original currency is always kept by the callers.
--   · daily cron f360-fx-rates 14:00 UTC (08:00 CDMX), same Vault pattern as f360-meta-spend.
-- WooCommerce, Commerce Facts, orders and inventory are not touched. Rollback: supabase/rollbacks/20261024000100_f360_fx_daily.down.sql

CREATE TABLE f360.fx_observations (
  id               bigserial PRIMARY KEY,
  obs_date         date NOT NULL,
  currency         text NOT NULL REFERENCES f360.currencies(code),
  base_currency    text NOT NULL DEFAULT 'MXN' CHECK (base_currency = 'MXN'),
  rate             numeric(20,10) NOT NULL CHECK (rate > 0 AND rate < 1000000),
  role             text NOT NULL CHECK (role IN ('primary', 'reference', 'manual')),
  method           text NOT NULL CHECK (method IN ('DIRECT', 'CROSS_USD', 'MANUAL')),
  source           text NOT NULL CHECK (length(btrim(source)) BETWEEN 2 AND 160),
  source_reference text NOT NULL CHECK (length(btrim(source_reference)) BETWEEN 4 AND 500),
  inputs           jsonb NOT NULL DEFAULT '{}'::jsonb,
  retrieved_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  recorded_by      uuid,
  recorded_by_name text NOT NULL,
  notes            text CHECK (notes IS NULL OR length(notes) <= 500),
  CONSTRAINT fx_obs_not_base CHECK (currency <> base_currency),
  CONSTRAINT fx_obs_role_method CHECK ((role = 'manual') = (method = 'MANUAL'))
);
CREATE UNIQUE INDEX fx_observations_dedupe ON f360.fx_observations (obs_date, currency, role, source, rate);
CREATE INDEX fx_observations_lookup ON f360.fx_observations (currency, role, obs_date DESC, retrieved_at DESC);
COMMENT ON TABLE f360.fx_observations IS 'I0: append-only daily FX history, base MXN (pesos per 1 unit). Newest retrieval wins; nothing is overwritten.';

CREATE FUNCTION f360.fx_observations_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial de tipos de cambio no se modifica ni se borra: registra una observación nueva.';
END $$;
CREATE TRIGGER fx_observations_append_only BEFORE UPDATE OR DELETE ON f360.fx_observations
  FOR EACH ROW EXECUTE FUNCTION f360.fx_observations_immutable();

CREATE VIEW f360.fx_daily AS
SELECT DISTINCT ON (currency, obs_date) currency, obs_date, rate, method, source, source_reference, inputs, retrieved_at, id AS observation_id
FROM f360.fx_observations WHERE role = 'primary'
ORDER BY currency, obs_date, retrieved_at DESC, id DESC;

CREATE TABLE f360.approval_scopes (
  scope         text NOT NULL CHECK (scope IN ('fx_rate', 'budget', 'close')),
  auth_user_id  uuid NOT NULL,
  display_name  text NOT NULL,
  added_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  added_by_name text NOT NULL,
  note          text CHECK (note IS NULL OR length(note) <= 300),
  PRIMARY KEY (scope, auth_user_id)
);
COMMENT ON TABLE f360.approval_scopes IS 'Who approves what (Mario 2026-10-11): fx_rate = Mario; budget = Mario; close = Mario or Carolina. Loaded per environment; empty = nobody.';
CREATE FUNCTION f360.can_approve(p_scope text, p_user uuid) RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM f360.approval_scopes WHERE scope = p_scope AND auth_user_id = p_user) $$;

-- the system identity that proposes monthly averages (no auth user; never an approver)
CREATE FUNCTION f360.fx_system_proposer() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0000-000000000360'::uuid $$;

-- ── recording (service role only: the daily function) ─────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_fx_observations_record(p_from date, p_to date, p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_started timestamptz := clock_timestamp(); x jsonb; n_new int := 0; n_dup int := 0; i int := 0; v_id bigint;
  v_dev jsonb;
BEGIN
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN RAISE EXCEPTION 'Ventana no válida.'; END IF;
  IF jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) > 5000 THEN RAISE EXCEPTION 'Filas no válidas.'; END IF;
  FOR x IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
    i := i + 1;
    IF x->>'role' NOT IN ('primary', 'reference') OR x->>'method' NOT IN ('DIRECT', 'CROSS_USD') OR x->>'currency' NOT IN ('USD', 'COP')
       OR (x->>'obs_date') !~ '^\d{4}-\d{2}-\d{2}$' OR (x->>'rate') !~ '^\d+(\.\d+)?$' OR (x->>'rate')::numeric <= 0
       OR ((x->>'obs_date')::date NOT BETWEEN p_from - 7 AND p_to + 1) THEN
      RAISE EXCEPTION 'Fila % no válida.', i;
    END IF;
    INSERT INTO f360.fx_observations (obs_date, currency, rate, role, method, source, source_reference, inputs, recorded_by_name)
      VALUES ((x->>'obs_date')::date, x->>'currency', (x->>'rate')::numeric, x->>'role', x->>'method', btrim(x->>'source'),
              btrim(x->>'source_reference'), coalesce(x->'inputs', '{}'::jsonb), 'Sistema · lectura diaria')
      ON CONFLICT (obs_date, currency, role, source, rate) DO NOTHING RETURNING id INTO v_id;
    IF v_id IS NULL THEN n_dup := n_dup + 1; ELSE n_new := n_new + 1; END IF;
    v_id := NULL;
  END LOOP;
  -- consistency: reference vs official the same day, more than 3 % apart (reported, never "fixed")
  SELECT coalesce(jsonb_agg(jsonb_build_object('fecha', r.obs_date, 'moneda', r.currency, 'oficial', d.rate, 'referencia', r.rate,
           'diferencia_pct', round(abs(r.rate - d.rate) / d.rate * 100, 2)) ORDER BY r.obs_date, r.currency), '[]') INTO v_dev
    FROM f360.fx_observations r JOIN f360.fx_daily d ON d.currency = r.currency AND d.obs_date = r.obs_date
   WHERE r.role = 'reference' AND r.obs_date BETWEEN p_from - 7 AND p_to + 1 AND abs(r.rate - d.rate) / d.rate > 0.03;
  INSERT INTO f360.measurement_runs (source_key, started_at, finished_at, ok, window_from, window_to, rows)
    VALUES ('fx_rates', v_started, clock_timestamp(), true, p_from, p_to, n_new);
  RETURN jsonb_build_object('ok', true, 'new', n_new, 'duplicates', n_dup, 'inconsistencias', v_dev);
END $$;

-- f360_measurement_run_failed learns 'fx_rates' (same body otherwise)
CREATE OR REPLACE FUNCTION public.f360_measurement_run_failed(p_source_key text, p_from date, p_to date, p_error text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF p_source_key NOT IN ('meta_ads', 'google_ads', 'ga4', 'fx_rates') THEN RAISE EXCEPTION 'Fuente no válida.'; END IF;
  INSERT INTO f360.measurement_runs (source_key, finished_at, ok, window_from, window_to, error)
    VALUES (p_source_key, clock_timestamp(), false, p_from, p_to, left(coalesce(nullif(btrim(p_error), ''), 'error sin detalle'), 500));
END $$;

-- ── manual observation (owner; kept for traceability, never averaged) ─────────────────────────────────────────────────────
CREATE FUNCTION public.f360_fx_observation_manual(p_date date, p_currency text, p_rate numeric, p_source text, p_source_reference text,
  p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner'); v_id bigint; v_cur text := upper(btrim(coalesce(p_currency, '')));
BEGIN
  IF v_cur NOT IN ('USD', 'COP') THEN RAISE EXCEPTION 'Moneda no válida (USD o COP; MXN es la base).'; END IF;
  IF p_date IS NULL OR p_date > (now() AT TIME ZONE 'America/Mexico_City')::date THEN RAISE EXCEPTION 'Fecha no válida (no futura).'; END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN RAISE EXCEPTION 'El tipo de cambio debe ser mayor que 0.'; END IF;
  IF length(btrim(coalesce(p_source, ''))) < 2 OR length(btrim(coalesce(p_source_reference, ''))) < 4 THEN RAISE EXCEPTION 'Indica la fuente y su referencia.'; END IF;
  INSERT INTO f360.fx_observations (obs_date, currency, rate, role, method, source, source_reference, recorded_by, recorded_by_name, notes)
    VALUES (p_date, v_cur, p_rate, 'manual', 'MANUAL', btrim(p_source), btrim(p_source_reference), r.auth_user_id, r.display_name,
            nullif(btrim(coalesce(p_notes, '')), ''))
    RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END $$;

-- ── monthly proposal (service role, or an owner) ─────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_fx_month_propose(p_month date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v_month date := date_trunc('month', p_month)::date; v_cur text; n int; v_avg numeric; d1 date; d2 date; v_ret date;
  v_ref text; out jsonb := '[]'; v_id uuid;
BEGIN
  IF coalesce(auth.role(), '') <> 'service_role' THEN PERFORM f360.require_role('owner'); END IF;
  IF p_month IS NULL OR v_month >= date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City'))::date THEN
    RETURN jsonb_build_object('ok', false, 'skipped', 'El mes no ha cerrado: la tasa mensual se propone al terminar el mes.');
  END IF;
  FOREACH v_cur IN ARRAY ARRAY['USD', 'COP'] LOOP
    IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE currency = v_cur AND period = v_month AND status IN ('proposed', 'approved')) THEN
      out := out || jsonb_build_object('moneda', v_cur, 'resultado', 'ya existe'); CONTINUE;
    END IF;
    SELECT count(*), avg(rate), min(obs_date), max(obs_date), max(retrieved_at)::date, min(source_reference)
      INTO n, v_avg, d1, d2, v_ret, v_ref
      FROM f360.fx_daily WHERE currency = v_cur AND obs_date >= v_month AND obs_date < (v_month + interval '1 month')::date;
    IF n < 10 THEN out := out || jsonb_build_object('moneda', v_cur, 'resultado', 'pocas observaciones', 'dias', n); CONTINUE; END IF;
    INSERT INTO f360.fx_rates (currency, period, rate, source, notes, proposed_by, proposed_by_name, source_reference, source_retrieved_on, rate_method)
      VALUES (v_cur, v_month, round(v_avg, 8),
              CASE v_cur WHEN 'USD' THEN 'Promedio mensual: FIX de Banxico publicado en el DOF'
                         ELSE 'Promedio mensual: FIX de Banxico (DOF) ÷ TRM del Banco de la República (cruce vía USD)' END,
              format('%s observaciones diarias del %s al %s (f360.fx_observations, rol primary).', n, d1, d2),
              f360.fx_system_proposer(), 'Sistema · lectura diaria', left(v_ref, 500), greatest(v_ret, v_month), 'MONTHLY_AVERAGE')
      RETURNING id INTO v_id;
    out := out || jsonb_build_object('moneda', v_cur, 'resultado', 'propuesta', 'id', v_id, 'tasa', round(v_avg, 8), 'dias', n);
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'mes', v_month, 'monedas', out);
END $$;

-- ── approval: owner AND scope fx_rate in f360.approval_scopes (Mario) ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.f360_fx_rate_approve(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  IF NOT f360.can_approve('fx_rate', r.auth_user_id) THEN
    RAISE EXCEPTION 'Solo quien está autorizado para tipos de cambio puede aprobar la tasa mensual.' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.fx_rates WHERE id = p_id AND status = 'proposed'
               AND (source_reference IS NULL OR source_retrieved_on IS NULL OR rate_method IS NULL)) THEN
    RAISE EXCEPTION 'Este tipo de cambio no tiene la fuente documentada (referencia, fecha de consulta, método): anúlalo y propón uno documentado.';
  END IF;
  UPDATE f360.fx_rates SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = clock_timestamp()
    WHERE id = p_id AND status = 'proposed';
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o no está propuesto.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved');
END $$;

-- ── the rate a report applies, and why ───────────────────────────────────────────────────────────────────────────────────
-- approved: the month's approved rate · provisional: the current OPEN month uses the last approved month (labelled) ·
-- missing: no conversion (the report shows the original currency only).
CREATE FUNCTION f360.fx_rate_for_report(p_currency text, p_month date) RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT CASE
    WHEN p_currency = 'MXN' THEN jsonb_build_object('rate', 1, 'status', 'base', 'month', date_trunc('month', p_month)::date)
    WHEN a.id IS NOT NULL THEN jsonb_build_object('rate', a.rate, 'status', 'approved', 'month', a.period, 'source', a.source,
                                                  'approved_by', a.approved_by_name, 'approved_at', a.approved_at, 'id', a.id)
    WHEN date_trunc('month', p_month) = date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City')) AND p.id IS NOT NULL
      THEN jsonb_build_object('rate', p.rate, 'status', 'provisional', 'month', p.period, 'source', p.source,
                              'note', 'Mes en curso: se usa la última tasa mensual aprobada hasta que cierre el mes.', 'id', p.id)
    ELSE jsonb_build_object('rate', NULL, 'status', 'missing', 'month', date_trunc('month', p_month)::date) END
  FROM (SELECT 1) one
  LEFT JOIN f360.fx_rates a ON a.currency = p_currency AND a.period = date_trunc('month', p_month)::date AND a.status = 'approved'
  LEFT JOIN LATERAL (SELECT * FROM f360.fx_rates x WHERE x.currency = p_currency AND x.status = 'approved' AND x.period < date_trunc('month', p_month)::date
                     ORDER BY x.period DESC LIMIT 1) p ON true
$$;

-- ── status for the panel (owner / operator) ──────────────────────────────────────────────────────────────────────────────
CREATE FUNCTION public.f360_fx_status() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator');
BEGIN
  RETURN jsonb_build_object(
    'can_approve', f360.can_approve('fx_rate', r.auth_user_id),
    'approvers', (SELECT coalesce(jsonb_agg(display_name ORDER BY display_name), '[]') FROM f360.approval_scopes WHERE scope = 'fx_rate'),
    'latest', (SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', currency, 'fecha', obs_date, 'tasa', rate, 'fuente', source, 'leida', retrieved_at)
                 ORDER BY currency), '[]')
               FROM (SELECT DISTINCT ON (currency) * FROM f360.fx_daily ORDER BY currency, obs_date DESC) l),
    'last_run', (SELECT jsonb_build_object('ok', ok, 'at', finished_at, 'error', error) FROM f360.measurement_runs
                 WHERE source_key = 'fx_rates' ORDER BY id DESC LIMIT 1),
    'months', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'moneda', currency, 'mes', period, 'tasa', rate, 'estado', status,
                 'fuente', source, 'notas', notes, 'propuesta_por', proposed_by_name, 'aprobada_por', approved_by_name, 'aprobada', approved_at)
                 ORDER BY period DESC, currency), '[]') FROM f360.fx_rates WHERE status <> 'voided'),
    'manual', (SELECT coalesce(jsonb_agg(jsonb_build_object('moneda', currency, 'fecha', obs_date, 'tasa', rate, 'fuente', source, 'por', recorded_by_name)
                 ORDER BY obs_date DESC), '[]') FROM f360.fx_observations WHERE role = 'manual'));
END $$;

-- ── daily cron (same Vault pattern as f360-meta-spend) ───────────────────────────────────────────────────────────────────
CREATE FUNCTION f360.fx_daily_tick() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_url text; v_secret text;
BEGIN
  SELECT regexp_replace(decrypted_secret, '/functions/v1/[^/]+$', '/functions/v1/f360-fx-rates') INTO v_url FROM vault.decrypted_secrets WHERE name = 'f360_sync_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'f360_sync_secret';
  IF v_url IS NULL OR v_secret IS NULL OR v_url !~ '/functions/v1/f360-fx-rates$' THEN RETURN; END IF;
  PERFORM net.http_post(url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := '{"action":"daily"}'::jsonb, timeout_milliseconds := 55000);
END $$;
SELECT cron.schedule('f360-fx-rates', '0 14 * * *', 'SELECT f360.fx_daily_tick()');

ALTER TABLE f360.fx_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.approval_scopes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.fx_observations, f360.approval_scopes, f360.fx_daily FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.fx_observations, f360.approval_scopes TO service_role;
GRANT SELECT ON f360.fx_daily TO service_role;
GRANT USAGE ON SEQUENCE f360.fx_observations_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.f360_fx_observations_record(date, date, jsonb), public.f360_fx_month_propose(date), public.f360_fx_observation_manual(date, text, numeric, text, text, text),
  public.f360_fx_status(), f360.fx_daily_tick(), f360.fx_rate_for_report(text, date), f360.fx_system_proposer(), f360.fx_observations_immutable(), f360.can_approve(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_fx_observations_record(date, date, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_fx_month_propose(date), public.f360_fx_observation_manual(date, text, numeric, text, text, text), public.f360_fx_status()
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION f360.fx_rate_for_report(text, date), f360.fx_system_proposer(), f360.can_approve(text, uuid) TO service_role;
