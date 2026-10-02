-- Rollback of 20261007000600_f360_inventory_adjustment.sql. ADJUSTMENT events already recorded stay in the ledger
-- (append-only history); only the ability to create new ones is removed.
DROP FUNCTION IF EXISTS public.f360_adjust_inventory(uuid, uuid, jsonb, text);
