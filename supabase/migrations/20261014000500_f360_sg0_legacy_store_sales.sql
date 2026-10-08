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
