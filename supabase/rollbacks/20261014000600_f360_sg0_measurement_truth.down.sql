-- Rollback of 20261014000600_f360_sg0_measurement_truth. Deploy the admin-web without the /growth?vista=medicion tab FIRST
-- (it calls these RPCs). Nothing here holds business data except the source registry (configuration) and the API run log
-- (empty until connectors exist); both are dropped.
DROP FUNCTION IF EXISTS public.f360_measurement_source_set(text, text, boolean, boolean, text);
DROP FUNCTION IF EXISTS public.f360_measurement_sales_list(integer, date, date);
DROP FUNCTION IF EXISTS public.f360_measurement_truth(date, date);
DROP FUNCTION IF EXISTS public.f360_measurement_health();
DROP FUNCTION IF EXISTS f360.sg0_efficiency_kpis(date, date);
DROP FUNCTION IF EXISTS f360.sg0_source_health();
DROP FUNCTION IF EXISTS f360.sg0_include_tests();
DROP VIEW IF EXISTS f360.measurement_sales;
DROP TABLE IF EXISTS f360.measurement_runs;
DROP TABLE IF EXISTS f360.measurement_sources;
