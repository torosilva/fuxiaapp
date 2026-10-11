-- Rollback of 20261024000700_f360_finance_access. Run inside one transaction (no BEGIN/COMMIT here). No data involved.
DROP FUNCTION public.f360_finance_access_state();
DROP TRIGGER finance_preparers_no_f360_role ON f360_board.finance_preparers;
DROP FUNCTION f360_board.finance_preparers_guard();
-- require_finance_capture: exact previous body (20261024000200)
CREATE OR REPLACE FUNCTION f360_board.require_finance_capture(p_what text, p_rpc text, p_object_ref text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := auth.uid(); why text; prep f360_board.finance_preparers;
BEGIN
  IF p_what NOT IN ('close', 'budget') THEN RAISE EXCEPTION 'f360_board gate misuse'; END IF;
  why := f360_board.member_denial(uid, 'FINANCIAL');
  IF why IS NOT NULL THEN
    SELECT * INTO prep FROM f360_board.finance_preparers WHERE auth_user_id = uid AND active;
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
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000700';
