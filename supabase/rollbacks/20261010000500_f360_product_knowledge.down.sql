-- Rollback of 20261010000500_f360_product_knowledge.sql. Carolina's captured knowledge is LOST:
-- export `SELECT * FROM f360.product_knowledge` (and _history) first.
DROP FUNCTION public.f360_product_knowledge_overview();
DROP FUNCTION public.f360_product_knowledge_save(uuid, jsonb, boolean);
DROP FUNCTION public.f360_product_knowledge_get(uuid);
DROP FUNCTION f360.knowledge_row(uuid);
DROP FUNCTION f360.product_knowledge_public(uuid);
DROP FUNCTION f360.knowledge_labels();
DROP TABLE f360.product_knowledge_history;
DROP TABLE f360.product_knowledge;
