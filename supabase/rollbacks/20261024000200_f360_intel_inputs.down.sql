-- Rollback of 20261024000200_f360_intel_inputs (I1a). Run inside one transaction with psql (no BEGIN/COMMIT here).
-- Refuses if real data was captured in the new tables (goals, commitments, preparers) unless f360.intel_drop_data = 'yes'.
DO $$ BEGIN
  IF (EXISTS (SELECT 1 FROM f360_board.goals) OR EXISTS (SELECT 1 FROM f360_board.financial_commitments) OR EXISTS (SELECT 1 FROM f360_board.finance_preparers))
     AND coalesce(current_setting('f360.intel_drop_data', true), '') <> 'yes' THEN
    RAISE EXCEPTION 'ABORT: hay metas, compromisos o contadoras registradas. Respáldalos y corre con SET f360.intel_drop_data = ''yes''.';
  END IF;
END $$;
DROP FUNCTION public.f360_finance_commitment_event(uuid, text, text);
DROP FUNCTION public.f360_finance_commitment_add(text, text, text, date, numeric, text, text, text, text, uuid, text);
DROP FUNCTION public.f360_close_prep_context();
DROP FUNCTION f360_board.commitments_current_json();
DROP VIEW f360_board.commitments_current;
DROP TABLE f360_board.financial_commitment_events;
DROP TABLE f360_board.financial_commitments;
DROP FUNCTION public.f360_close_prep_entry_void(uuid, text);
DROP FUNCTION public.f360_close_prep_entry_add(uuid, uuid, text, numeric, text, text, text, text, text);
DROP VIEW f360.product_cost_effective; -- recreated without cost_basis below (a view cannot drop a column in place)
CREATE VIEW f360.product_cost_effective AS
  SELECT c.id, c.product_id, c.variant_id, c.market, c.cost_amount, c.currency, c.effective_from, c.effective_to, c.source,
         c.created_by_name, c.approved_by_name, c.approved_at
  FROM f360.product_cost_versions c WHERE c.status = 'approved';
ALTER TABLE f360.product_cost_versions DROP COLUMN cost_basis;
DROP FUNCTION public.f360_board_goals();
DROP FUNCTION public.f360_board_goal_set(text, text, text, text, numeric, date, text);
DROP FUNCTION f360_board.goal_for(text, date);
DROP TABLE f360_board.goals;
DROP FUNCTION public.f360_board_budgets(int);
DROP FUNCTION public.f360_board_budget_approve(uuid);
DROP FUNCTION public.f360_board_budget_validate(uuid, text);
DROP FUNCTION public.f360_board_budget_lines_set(uuid, jsonb);
DROP FUNCTION public.f360_board_budget_draft(int, text, text, uuid);
DROP FUNCTION f360_board.capture_name(uuid);
DROP FUNCTION f360_board.require_finance_capture(text, text, text);
DROP TABLE f360_board.finance_preparers;
-- budget versions captured with these RPCs keep their rows; only the new columns go
ALTER TABLE f360_board.budget_versions DROP COLUMN change_reason, DROP COLUMN commercial_validated_by, DROP COLUMN commercial_validated_by_name,
  DROP COLUMN commercial_validated_at, DROP COLUMN commercial_validation_note;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261024000200';
