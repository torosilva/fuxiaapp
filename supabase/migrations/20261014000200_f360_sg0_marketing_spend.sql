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
