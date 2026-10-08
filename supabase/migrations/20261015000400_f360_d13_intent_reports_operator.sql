-- Fuxia 360 · D13 (Mario 2026-10-08) — aggregate demand / product-intent reports need OPERATOR (or owner).
-- Finding F1 (docs/fuxia360/strategy-board/14_SECURITY_MODEL.md): role_rank gives seller = viewer = 1, so these RPCs gated
-- with require_role('viewer') were callable by any vendedora straight through PostgREST, even though the admin menu hides them:
--   f360_stock_demand(text)            demand without stock (waiting customers, made-to-order pairs)     — 20261010000700
--   f360_favorites_report(text,int)    favourites intent per model incl. units sold                       — 20261012000900
--   f360_review_summary(uuid)          review facts per product                                           — 20261011000100
--   f360_store_order(text)             store ranking by units sold (last 60 days, every channel)           — 20261012000700
-- (f360_growth_plan, the Board's Plan 2027 source, is already operator+ in the live definition — checked, not touched.)
-- Change: ONLY the gate literal require_role('viewer') → require_role('operator') inside each function, taken from the LIVE
-- definition of this database (so any later redefinition in production is preserved byte for byte otherwise). Signatures,
-- grants, owners and results are unchanged. Seller flows (shift, catalog, customer find/register, record_store_sale(_for),
-- reservations) do not call these functions and are untouched.
-- Rollback: supabase/rollbacks/20261015000400_f360_d13_intent_reports_operator.down.sql (inverse replacement).

DO $$
DECLARE f text; def text; n int;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.f360_stock_demand(text)', 'public.f360_favorites_report(text,integer)', 'public.f360_review_summary(uuid)',
                           'public.f360_store_order(text)'] LOOP
    def := pg_get_functiondef(f::regprocedure);
    n := (length(def) - length(replace(def, 'require_role(''viewer'')', ''))) / length('require_role(''viewer'')');
    IF n <> 1 THEN RAISE EXCEPTION 'D13: % has % viewer gates (expected exactly 1) — review by hand', f, n; END IF;
    EXECUTE replace(def, 'require_role(''viewer'')', 'require_role(''operator'')');
  END LOOP;
END $$;
