-- Rollback of 20261014000300_f360_sg0_fx_rates. Run AFTER rolling back 20261014000600 (it reads f360.fx_rate_for) and after
-- confirming no SB0 object references f360.fx_rates. The TABLE is dropped only while EMPTY (approved rates are Board history).
DROP FUNCTION IF EXISTS public.f360_fx_rates_list();
DROP FUNCTION IF EXISTS public.f360_fx_rate_void(uuid, text);
DROP FUNCTION IF EXISTS public.f360_fx_rate_approve(uuid);
DROP FUNCTION IF EXISTS public.f360_fx_rate_propose(text, date, numeric, text, text);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.fx_rates) THEN
    DROP FUNCTION f360.fx_rate_for(text, date);
    DROP TABLE f360.fx_rates;
    DROP FUNCTION f360.fx_rates_guard();
  ELSE
    RAISE NOTICE 'f360.fx_rates tiene filas: se conserva (borrar solo con OK explícito de Mario).';
  END IF;
END $$;
