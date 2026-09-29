-- Rollback of S0.3 legacy store sale (staging). Sales already recorded stay in offline_sales (history is never deleted);
-- their per-line items table and the added columns are dropped only if you accept losing that detail — export first.
BEGIN;
DROP VIEW IF EXISTS f360.store_sale_facts;
DROP FUNCTION IF EXISTS public.f360_claim_store_sale(text);
DROP FUNCTION IF EXISTS public.f360_record_store_sale(text, uuid, jsonb, text, text, text);
ALTER TABLE public.channel_inventory DROP CONSTRAINT IF EXISTS channel_inventory_stock_sane;
DROP TABLE IF EXISTS public.offline_sale_items;
DROP INDEX IF EXISTS public.offline_sales_idempotency_key_key;
ALTER TABLE public.offline_sales DROP COLUMN IF EXISTS created_by_rpc, DROP COLUMN IF EXISTS loyalty_transaction_id, DROP COLUMN IF EXISTS self_sale,
  DROP COLUMN IF EXISTS price_source, DROP COLUMN IF EXISTS payment_reference, DROP COLUMN IF EXISTS payment_method, DROP COLUMN IF EXISTS session_id,
  DROP COLUMN IF EXISTS location_id, DROP COLUMN IF EXISTS seller_auth_user_id, DROP COLUMN IF EXISTS idempotency_key;
COMMIT;
