-- ROLLBACK for 20261004000400_f360_c3_sales_read_model.sql (read-only objects; no data is lost).
DROP FUNCTION public.f360_list_sales(date, date, uuid, uuid, text, int), public.f360_get_sale(uuid);
DROP FUNCTION f360.mask_phone(text);
DROP VIEW f360.sales_facts;
