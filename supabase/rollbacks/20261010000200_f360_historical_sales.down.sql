-- Rollback of 20261010000200_f360_historical_sales.sql. Loaded summaries are LOST: export
-- `SELECT * FROM f360.historical_sales` first if Carolina already loaded data.
DROP FUNCTION public.f360_hist_sales_list(integer);
DROP FUNCTION public.f360_hist_sales_void(uuid, text);
DROP FUNCTION public.f360_hist_sales_save(text, uuid, text, date, date, numeric, integer, boolean, text);
DROP FUNCTION f360.hist_refusal(text);
DROP VIEW f360.historical_sales_active;
DROP TABLE f360.historical_sales_log;
DROP TABLE f360.historical_sales;
