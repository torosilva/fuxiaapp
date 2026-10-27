-- Fuxia 360 · PRODUCCIÓN · 20261024000700_f360_finance_access VERBATIM (Mario 2026-10-27: "pasa todo a produccion" / "de acuerdo").
-- Plan: docs/fuxia360/intelligence/I5_PLAN_PRODUCCION.md (earn-in: strategy-board/SB_EARNIN_DELIVERY.md). En staging desde oct.
-- Reversión: supabase/rollbacks/20261024000700_f360_finance_access.down.sql
BEGIN;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000700') THEN RAISE EXCEPTION 'PRE: 20261024000700 ya está'; END IF;
  IF NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261024000600') THEN RAISE EXCEPTION 'PRE: falta 20261024000600'; END IF;
END $$;
-- Fuxia 360 · Centro de Inteligencia · 0700 — acceso de la contadora con MÍNIMO PRIVILEGIO (Mario 2026-10-11, D2; STAGING primero).
-- Design (I5_PLAN_PRODUCCION.md §4): the contadora has NO row in f360.user_roles, so she passes no require_role() gate (the
-- 66 viewer-level functions, sales, inventory, products, customers, users stay closed). Her only identity is
-- f360_board.finance_preparers (can_close / can_budget) + the board's second-factor rule. ADDITIVE:
--   · f360_board.finance_preparers_guard: a preparer cannot be registered (or re-activated) while she has an F360 role;
--   · f360_board.require_finance_capture (same signature): the preparer path also requires "no F360 role" (defense in depth if a
--     role were granted later by mistake: she then loses finance capture instead of gaining the role's functions);
--   · public.f360_finance_access_state(): the CALLER's own status only (no data about anyone else) so the admin can route her to
--     /cierre-contable before / after the second factor — replaces the I2 heuristic "every viewer might be the contadora".
-- f360.user_roles is NOT modified (no trigger, no constraint on another module's table). No data change.
-- Rollback: supabase/rollbacks/20261024000700_f360_finance_access.down.sql

CREATE FUNCTION f360_board.finance_preparers_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  IF NEW.active AND EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = NEW.auth_user_id) THEN
    RAISE EXCEPTION 'Mínimo privilegio: una contadora no puede tener rol en Fuxia 360 (quita su fila de f360.user_roles primero).';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER finance_preparers_no_f360_role BEFORE INSERT OR UPDATE ON f360_board.finance_preparers
  FOR EACH ROW EXECUTE FUNCTION f360_board.finance_preparers_guard();

CREATE OR REPLACE FUNCTION f360_board.require_finance_capture(p_what text, p_rpc text, p_object_ref text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); why text; prep f360_board.finance_preparers;
BEGIN
  IF p_what NOT IN ('close', 'budget') THEN RAISE EXCEPTION 'f360_board gate misuse'; END IF;
  why := f360_board.member_denial(uid, 'FINANCIAL');
  IF why IS NOT NULL THEN
    -- 0700: a preparer is NEVER also an F360 user (no f360.user_roles row): otherwise she would inherit the role's functions
    SELECT * INTO prep FROM f360_board.finance_preparers WHERE auth_user_id = uid AND active
      AND NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = uid);
    IF prep.auth_user_id IS NOT NULL AND ((p_what = 'close' AND prep.can_close) OR (p_what = 'budget' AND prep.can_budget)) THEN
      -- same second-factor rule as the board (f360_board.settings.require_aal2)
      why := CASE WHEN coalesce((SELECT require_aal2 FROM f360_board.settings WHERE id), false) AND coalesce(auth.jwt()->>'aal', '') <> 'aal2'
                  THEN 'mfa_required' END;
    END IF;
  END IF;
  INSERT INTO f360_board.access_log (auth_user_id, rpc, scope, outcome, reason, object_ref, params_hash, request_id)
    VALUES (uid, p_rpc, 'FINANCIAL', CASE WHEN why IS NULL THEN 'allowed' ELSE 'denied' END, why, left(p_object_ref, 200), NULL, f360_board.request_id());
  RETURN CASE WHEN why IS NULL THEN uid END;
END $$;

CREATE FUNCTION public.f360_finance_access_state() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); p f360_board.finance_preparers; has_role boolean; board boolean; aal_missing boolean;
BEGIN
  IF uid IS NULL THEN
    RETURN jsonb_build_object('preparadora', false, 'consejo', false, 'rol_f360', false, 'mfa_requerido', false);
  END IF;
  SELECT * INTO p FROM f360_board.finance_preparers WHERE auth_user_id = uid AND active;
  has_role := EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = uid);
  board := EXISTS (SELECT 1 FROM f360_board.board_members WHERE auth_user_id = uid AND active) AND has_role;
  aal_missing := coalesce((SELECT require_aal2 FROM f360_board.settings WHERE id), false) AND coalesce(auth.jwt()->>'aal', '') <> 'aal2';
  RETURN jsonb_build_object(
    'preparadora', p.auth_user_id IS NOT NULL AND NOT has_role,
    'nombre', CASE WHEN p.auth_user_id IS NOT NULL AND NOT has_role THEN p.display_name END,
    'can_close', coalesce(p.can_close, false) AND NOT has_role, 'can_budget', coalesce(p.can_budget, false) AND NOT has_role,
    'consejo', board, 'rol_f360', has_role,
    'conflicto', p.auth_user_id IS NOT NULL AND has_role,
    'mfa_requerido', (p.auth_user_id IS NOT NULL OR board) AND aal_missing);
END $$;

REVOKE ALL ON FUNCTION f360_board.finance_preparers_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_finance_access_state() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_finance_access_state() TO authenticated;

INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261024000700', 'f360_finance_access', '{}');
COMMIT;
