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
