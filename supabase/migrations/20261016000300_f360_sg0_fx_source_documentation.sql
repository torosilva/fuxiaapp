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
