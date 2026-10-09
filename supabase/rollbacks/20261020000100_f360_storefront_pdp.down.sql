-- Rollback of 20261020000100_f360_storefront_pdp.sql (the product page then simply shows no promise / materials).
DROP FUNCTION IF EXISTS public.f360_storefront_pdp(text, bigint, text);
