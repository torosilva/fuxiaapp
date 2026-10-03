-- Rollback of 20261007002300.
DROP FUNCTION IF EXISTS public.f360_top_searches(int, int);
DROP FUNCTION IF EXISTS public.f360_log_search(text, text);
DROP TABLE IF EXISTS f360.storefront_searches;
