-- Rollback of 20261025000100_f360_store_discounts.sql. Restores the store-sale RPCs exactly as 20261007001100 / 20261013000200
-- (re-run their CREATE blocks after this file), drops the discount entry points and the requests table.
-- Sales already recorded WITH a discount keep their columns' data only if the columns stay: this file KEEPS the offline_sales
-- columns (history: who gave which discount) and only drops what can be dropped without losing records. Approvals (scope
-- 'store_discount') are removed. Run only with Mario's OK once applied (teardown).
DROP FUNCTION IF EXISTS public.f360_record_store_sale_for(text, uuid, jsonb, text, text, uuid, numeric, jsonb);
DROP FUNCTION IF EXISTS public.f360_record_store_sale(text, uuid, jsonb, text, text, text, numeric, jsonb);
-- → now re-create public.f360_record_store_sale from 20261007001100 (+ its grants from 20261002000300:188-189) and
--   public.f360_record_store_sale_for from 20261013000200 (+ grants :128-129).
DROP FUNCTION IF EXISTS public.f360_store_discount_decide(uuid, boolean, text), public.f360_store_discount_inbox(),
  public.f360_store_discount_status(text, uuid), public.f360_store_discount_request(text, jsonb, numeric, text),
  public.f360_store_discount_pin(text, jsonb, numeric, text, text), public.f360_shift_discount_policy(text),
  f360.store_discount_prepare(f360.seller_sessions, jsonb, numeric, text), f360.store_discount_authorize(f360.seller_sessions, numeric, jsonb, numeric, jsonb),
  f360.store_discount_push(uuid[], text, text, jsonb), f360.store_discount_check_pct(numeric), f360.store_lines_gross(f360.locations, jsonb),
  f360.store_lines_req(jsonb, boolean), f360.store_discount_approver_names(), f360.store_discount_approvers(), f360.store_discount_params();
DROP TABLE IF EXISTS f360.store_discount_requests;
DELETE FROM f360.approval_scopes WHERE scope = 'store_discount';
ALTER TABLE f360.approval_scopes DROP CONSTRAINT approval_scopes_scope_check;
ALTER TABLE f360.approval_scopes ADD CONSTRAINT approval_scopes_scope_check CHECK (scope IN ('fx_rate', 'budget', 'close'));
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261025000100';
