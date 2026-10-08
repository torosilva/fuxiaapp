-- Rollback of 20261014000400_f360_sg0_product_cost (confirm first that no SB0 object reads f360.product_cost_versions).
-- The TABLE is dropped only while EMPTY (approved costs are financial history).
DROP FUNCTION IF EXISTS public.f360_product_cost_history(uuid);
DROP FUNCTION IF EXISTS public.f360_product_cost_decide(uuid, boolean, text);
DROP FUNCTION IF EXISTS public.f360_product_cost_propose(uuid, uuid, text, numeric, text, date, text, text);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.product_cost_versions) THEN
    DROP VIEW f360.product_cost_effective;
    DROP TABLE f360.product_cost_versions;
    DROP FUNCTION f360.product_cost_guard();
  ELSE
    RAISE NOTICE 'f360.product_cost_versions tiene filas: se conserva (borrar solo con OK explícito de Mario).';
  END IF;
END $$;
