-- Rollback of 20261016000300_f360_sg0_fx_source_documentation.sql. Restores the 20261014000300 propose/approve. The three
-- documentation columns are dropped ONLY if no row uses them (otherwise they are kept: they are audit evidence).
DROP FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text, date, text, text);
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
CREATE OR REPLACE FUNCTION public.f360_fx_rate_approve(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles := f360.require_role('owner');
BEGIN
  UPDATE f360.fx_rates SET status = 'approved', approved_by = r.auth_user_id, approved_by_name = r.display_name, approved_at = clock_timestamp()
    WHERE id = p_id AND status = 'proposed';
  IF NOT FOUND THEN RAISE EXCEPTION 'Tipo de cambio no encontrado o no está propuesto.'; END IF;
  RETURN jsonb_build_object('ok', true, 'id', p_id, 'status', 'approved');
END $$;
REVOKE ALL ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_fx_rate_propose(text, date, numeric, text, text) TO authenticated, service_role;
ALTER TABLE f360.fx_rates DROP CONSTRAINT fx_documented, DROP CONSTRAINT fx_retrieved_after_period;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE source_reference IS NOT NULL OR source_retrieved_on IS NOT NULL OR rate_method IS NOT NULL) THEN
    ALTER TABLE f360.fx_rates DROP COLUMN source_reference, DROP COLUMN source_retrieved_on, DROP COLUMN rate_method;
  END IF;
END $$;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261016000300';
