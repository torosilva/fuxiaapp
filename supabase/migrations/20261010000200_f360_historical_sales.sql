-- Fuxia 360 · Ventas históricas (resumen) — Carolina loads this year's store/bazaar sales made BEFORE Fuxia 360. STAGING.
-- Decision: Mario 2026-10-05. "Ventas generales": a bazaar = name + dates + amount + pairs; a store = month + amount + pairs.
-- Online history is NOT loaded here (it already comes from WooCommerce / Commerce Facts).
-- A summary is NOT a sale line: no model, size, customer, points or inventory movement. It feeds monthly/location totals
-- only, marked as "resumen histórico", never "top models" or CRM.
-- No double counting: a period is refused when the location already has sales recorded by the Fuxia 360 sale RPC
-- (offline_sales.created_by_rpc) in it, and only one active summary exists per store-month / bazaar-start.
-- MXN only (Mexican stores/bazaars). Corrections = void + new; every change is in an append-only log.
-- Rollback: supabase/rollbacks/20261010000200_f360_historical_sales.down.sql

CREATE TABLE f360.historical_sales (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             text NOT NULL CHECK (kind IN ('store_month', 'bazaar')),
  location_id      uuid REFERENCES f360.locations(id) ON DELETE RESTRICT,
  bazaar_name      text,
  period_start     date NOT NULL,
  period_end       date NOT NULL,
  amount           numeric(12,2) NOT NULL CHECK (amount > 0 AND amount < 100000000),
  currency         text NOT NULL DEFAULT 'MXN' CHECK (currency = 'MXN'),
  pairs            integer NOT NULL CHECK (pairs >= 0 AND pairs < 100000),
  pairs_estimated  boolean NOT NULL DEFAULT false,
  notes            text CHECK (notes IS NULL OR length(notes) <= 500),
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'voided')),
  created_by       uuid NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  voided_by        uuid,
  voided_at        timestamptz,
  void_reason      text,
  CONSTRAINT hist_period_order CHECK (period_end >= period_start),
  CONSTRAINT hist_store_month CHECK (kind <> 'store_month' OR (location_id IS NOT NULL AND bazaar_name IS NULL
    AND period_start = date_trunc('month', period_start)::date AND period_end = (date_trunc('month', period_start) + interval '1 month - 1 day')::date)),
  CONSTRAINT hist_bazaar CHECK (kind <> 'bazaar' OR ((location_id IS NOT NULL OR length(btrim(coalesce(bazaar_name, ''))) >= 2)
    AND period_end - period_start <= 31)),
  CONSTRAINT hist_void CHECK ((status = 'voided') = (voided_at IS NOT NULL))
);
CREATE UNIQUE INDEX historical_sales_one_store_month ON f360.historical_sales (location_id, period_start)
  WHERE status = 'active' AND kind = 'store_month';
CREATE UNIQUE INDEX historical_sales_one_bazaar ON f360.historical_sales (coalesce(location_id::text, lower(btrim(bazaar_name))), period_start)
  WHERE status = 'active' AND kind = 'bazaar';
ALTER TABLE f360.historical_sales ENABLE ROW LEVEL SECURITY;

CREATE TABLE f360.historical_sales_log (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  summary_id    uuid NOT NULL,
  action        text NOT NULL CHECK (action IN ('created', 'voided')),
  by_auth_user  uuid NOT NULL,
  by_name       text,
  snapshot      jsonb NOT NULL,
  at            timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE f360.historical_sales_log ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER historical_sales_log_append_only BEFORE UPDATE OR DELETE ON f360.historical_sales_log
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Every active summary, with a display name for the place (MXN, Mexico City dates).
CREATE VIEW f360.historical_sales_active AS
  SELECT h.id, h.kind, h.location_id, coalesce(l.name, h.bazaar_name) AS place, coalesce(l.type, 'bazaar') AS place_type,
         h.period_start, h.period_end, h.amount, h.currency, h.pairs, h.pairs_estimated, h.notes, h.created_at,
         (SELECT display_name FROM f360.user_roles r WHERE r.auth_user_id = h.created_by) AS created_by_name
  FROM f360.historical_sales h LEFT JOIN f360.locations l ON l.id = h.location_id
  WHERE h.status = 'active';

CREATE FUNCTION f360.hist_refusal(p_code text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('ok', false, 'code', p_code, 'error', CASE p_code
    WHEN 'bad_kind' THEN 'Elige si es una tienda (mes) o un bazar.'
    WHEN 'bad_location' THEN 'Elige una tienda.'
    WHEN 'bad_bazaar' THEN 'Escribe el nombre del bazar (o elige uno existente).'
    WHEN 'bad_dates' THEN 'Revisa las fechas: el fin no puede ser antes del inicio y un bazar dura máximo 31 días.'
    WHEN 'future' THEN 'Solo se cargan periodos ya terminados (no el mes en curso ni fechas futuras).'
    WHEN 'too_old' THEN 'Solo se cargan ventas desde 2025.'
    WHEN 'before_opening' THEN 'La tienda todavía no abría en ese periodo.'
    WHEN 'bad_amount' THEN 'Escribe el monto total vendido (en pesos).'
    WHEN 'bad_pairs' THEN 'Escribe cuántos pares (aunque sea aproximado).'
    WHEN 'duplicate' THEN 'Ese periodo ya está cargado. Si hay un error, anúlalo y vuelve a cargarlo.'
    WHEN 'already_recorded' THEN 'Esa tienda ya tiene ventas registradas en Fuxia 360 en ese periodo; cargarlo las contaría dos veces.'
    WHEN 'not_found' THEN 'No encontramos esa carga.'
    WHEN 'bad_reason' THEN 'Escribe por qué se anula.'
    ELSE 'No se pudo guardar.' END)
$$;

-- Load one summary. kind 'store_month': p_location + p_month (any day of the month). kind 'bazaar': p_location (an
-- existing bazaar) or p_bazaar_name, + p_start/p_end.
CREATE FUNCTION public.f360_hist_sales_save(p_kind text, p_location uuid, p_bazaar_name text, p_start date, p_end date,
  p_amount numeric, p_pairs integer, p_pairs_estimated boolean DEFAULT false, p_notes text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); l f360.locations; s date; e date; today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  nm text := nullif(btrim(regexp_replace(coalesce(p_bazaar_name, ''), '\s+', ' ', 'g')), ''); h f360.historical_sales;
BEGIN
  IF p_kind NOT IN ('store_month', 'bazaar') THEN RETURN f360.hist_refusal('bad_kind'); END IF;
  IF p_location IS NOT NULL THEN SELECT * INTO l FROM f360.locations WHERE id = p_location; END IF;
  IF p_kind = 'store_month' THEN
    IF l.id IS NULL OR l.type <> 'store' THEN RETURN f360.hist_refusal('bad_location'); END IF;
    IF p_start IS NULL THEN RETURN f360.hist_refusal('bad_dates'); END IF;
    s := date_trunc('month', p_start)::date; e := (date_trunc('month', p_start) + interval '1 month - 1 day')::date;
    nm := NULL;
  ELSE
    IF p_location IS NOT NULL AND (l.id IS NULL OR l.type <> 'bazaar') THEN RETURN f360.hist_refusal('bad_bazaar'); END IF;
    IF p_location IS NULL AND (nm IS NULL OR length(nm) < 2 OR length(nm) > 80) THEN RETURN f360.hist_refusal('bad_bazaar'); END IF;
    IF p_location IS NOT NULL THEN nm := NULL; END IF;
    s := p_start; e := coalesce(p_end, p_start);
    IF s IS NULL OR e < s OR e - s > 31 THEN RETURN f360.hist_refusal('bad_dates'); END IF;
  END IF;
  IF e >= date_trunc('month', today)::date AND p_kind = 'store_month' OR e >= today THEN RETURN f360.hist_refusal('future'); END IF;
  IF s < date '2025-01-01' THEN RETURN f360.hist_refusal('too_old'); END IF;
  IF l.starts_on IS NOT NULL AND e < l.starts_on THEN RETURN f360.hist_refusal('before_opening'); END IF;
  IF p_amount IS NULL OR p_amount <= 0 OR p_amount >= 100000000 THEN RETURN f360.hist_refusal('bad_amount'); END IF;
  IF p_pairs IS NULL OR p_pairs < 0 OR p_pairs >= 100000 THEN RETURN f360.hist_refusal('bad_pairs'); END IF;
  IF p_location IS NOT NULL AND EXISTS (SELECT 1 FROM public.offline_sales o WHERE o.location_id = p_location AND o.created_by_rpc
       AND (o.created_at AT TIME ZONE 'America/Mexico_City')::date BETWEEN s AND e) THEN
    RETURN f360.hist_refusal('already_recorded');
  END IF;
  BEGIN
    INSERT INTO f360.historical_sales (kind, location_id, bazaar_name, period_start, period_end, amount, pairs, pairs_estimated, notes, created_by)
      VALUES (p_kind, p_location, nm, s, e, round(p_amount, 2), p_pairs, coalesce(p_pairs_estimated, false), nullif(btrim(coalesce(p_notes, '')), ''), r.auth_user_id)
      RETURNING * INTO h;
  EXCEPTION WHEN unique_violation THEN RETURN f360.hist_refusal('duplicate');
  END;
  INSERT INTO f360.historical_sales_log (summary_id, action, by_auth_user, by_name, snapshot) VALUES (h.id, 'created', r.auth_user_id, r.display_name, to_jsonb(h));
  RETURN jsonb_build_object('ok', true, 'id', h.id);
END $$;

CREATE FUNCTION public.f360_hist_sales_void(p_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); h f360.historical_sales;
BEGIN
  IF length(btrim(coalesce(p_reason, ''))) < 3 THEN RETURN f360.hist_refusal('bad_reason'); END IF;
  UPDATE f360.historical_sales SET status = 'voided', voided_by = r.auth_user_id, voided_at = now(), void_reason = btrim(p_reason)
    WHERE id = p_id AND status = 'active' RETURNING * INTO h;
  IF h.id IS NULL THEN RETURN f360.hist_refusal('not_found'); END IF;
  INSERT INTO f360.historical_sales_log (summary_id, action, by_auth_user, by_name, snapshot) VALUES (h.id, 'voided', r.auth_user_id, r.display_name, to_jsonb(h));
  RETURN jsonb_build_object('ok', true);
END $$;

-- What the "Ventas pasadas" screen shows: active loads of a year + totals per month (MXN), plus the places to choose from.
CREATE FUNCTION public.f360_hist_sales_list(p_year integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('operator'); y int := coalesce(p_year, extract(year FROM now() AT TIME ZONE 'America/Mexico_City')::int);
BEGIN
  RETURN jsonb_build_object(
    'year', y,
    'items', coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY a.period_start DESC, a.place) FROM f360.historical_sales_active a
                       WHERE extract(year FROM a.period_start) = y), '[]'),
    'by_month', coalesce((SELECT jsonb_agg(jsonb_build_object('month', m, 'amount', amt, 'pairs', prs, 'loads', n) ORDER BY m) FROM (
        SELECT to_char(date_trunc('month', period_start), 'YYYY-MM') m, sum(amount) amt, sum(pairs) prs, count(*) n
        FROM f360.historical_sales_active WHERE extract(year FROM period_start) = y GROUP BY 1) x), '[]'),
    'total', jsonb_build_object('amount', coalesce((SELECT sum(amount) FROM f360.historical_sales_active WHERE extract(year FROM period_start) = y), 0),
                                'pairs', coalesce((SELECT sum(pairs) FROM f360.historical_sales_active WHERE extract(year FROM period_start) = y), 0),
                                'currency', 'MXN'),
    'stores', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'starts_on', starts_on) ORDER BY sort, name)
                        FROM f360.locations WHERE type = 'store'), '[]'),
    'bazaars', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'name', name, 'starts_on', starts_on, 'ends_on', ends_on) ORDER BY name)
                         FROM f360.locations WHERE type = 'bazaar'), '[]'));
END $$;

REVOKE ALL ON FUNCTION f360.hist_refusal(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON f360.historical_sales, f360.historical_sales_log, f360.historical_sales_active FROM PUBLIC, anon, authenticated;
GRANT SELECT ON f360.historical_sales, f360.historical_sales_log, f360.historical_sales_active TO service_role;
REVOKE ALL ON FUNCTION public.f360_hist_sales_save(text, uuid, text, date, date, numeric, integer, boolean, text),
  public.f360_hist_sales_void(uuid, text), public.f360_hist_sales_list(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_hist_sales_save(text, uuid, text, date, date, numeric, integer, boolean, text),
  public.f360_hist_sales_void(uuid, text), public.f360_hist_sales_list(integer) TO authenticated;
