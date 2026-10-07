-- Rollback of 20261012000800_f360_favorites_intent. The events go with the tables (export them first if they matter).
-- The store keeps working: the ♡ list lives in the visitor's browser; only the anonymous capture stops.
DROP FUNCTION IF EXISTS public.f360_favorites_report(text, integer);
DROP FUNCTION IF EXISTS public.f360_favorite_record(jsonb);
DROP TABLE IF EXISTS f360.favorite_events;
DROP TABLE IF EXISTS f360.anon_visitors;
