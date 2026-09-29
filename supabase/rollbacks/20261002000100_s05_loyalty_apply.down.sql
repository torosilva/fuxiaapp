-- Rollback of S0.5 (staging). Drops loyalty_apply and its audit; removes the added transactions columns.
-- WARNING: transactions created through loyalty_apply stay (they are real loyalty history) but lose ref/idempotency columns.
BEGIN;
DROP FUNCTION IF EXISTS public.loyalty_apply(uuid, jsonb, numeric, text, text, text, text, jsonb, text);
DROP FUNCTION IF EXISTS public.loyalty_points_per_pair();
DROP FUNCTION IF EXISTS public.loyalty_pairs_for_lines(jsonb);
DROP TABLE IF EXISTS public.loyalty_apply_audit;
DROP INDEX IF EXISTS public.transactions_idempotency_key_key;
ALTER TABLE public.transactions DROP COLUMN IF EXISTS actor, DROP COLUMN IF EXISTS idempotency_key, DROP COLUMN IF EXISTS ref_id, DROP COLUMN IF EXISTS ref_type;
COMMIT;
