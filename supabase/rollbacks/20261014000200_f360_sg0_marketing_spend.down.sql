-- Rollback of 20261014000200_f360_sg0_marketing_spend. Run AFTER rolling back 20261014000600 (its health / summary read
-- f360.marketing_spend_daily). Removes the upload surface; the TABLES are dropped only while EMPTY (imported spend is
-- financial history: dropping it needs Mario's explicit OK).
DROP FUNCTION IF EXISTS public.f360_marketing_spend_imports(integer);
DROP FUNCTION IF EXISTS public.f360_marketing_spend_void(uuid, text);
DROP FUNCTION IF EXISTS public.f360_marketing_spend_upload(text, text, text, jsonb);
DROP FUNCTION IF EXISTS f360.marketing_spend_row_error(jsonb, date);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.marketing_spend_imports) THEN
    DROP VIEW f360.marketing_spend_daily;
    DROP TABLE f360.marketing_spend_rows;
    DROP TABLE f360.marketing_spend_imports;
    DROP FUNCTION f360.marketing_spend_import_guard();
  ELSE
    RAISE NOTICE 'marketing_spend_* tiene importaciones: se conservan las tablas (borrar solo con OK explícito de Mario).';
  END IF;
END $$;
