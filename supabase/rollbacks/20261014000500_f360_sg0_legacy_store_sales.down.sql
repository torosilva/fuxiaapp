-- Rollback of 20261014000500_f360_sg0_legacy_store_sales. Run AFTER rolling back 20261014000600 (f360.measurement_sales reads
-- the registry). public.offline_sales is never touched by this migration or its rollback. The registry is dropped only while
-- EMPTY (it is an audit of who decided what); otherwise kept.
DROP FUNCTION IF EXISTS public.f360_legacy_store_sales_import(boolean);
DROP FUNCTION IF EXISTS f360.legacy_sale_check(uuid);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.legacy_store_sale_imports) THEN
    DROP TABLE f360.legacy_store_sale_imports;
  ELSE
    RAISE NOTICE 'f360.legacy_store_sale_imports tiene filas: se conserva (borrar solo con OK explícito de Mario).';
  END IF;
END $$;
