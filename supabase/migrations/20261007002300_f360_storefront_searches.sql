-- Fuxia 360 — what customers search for in the shop (STAGING). Decision: Mario 2026-10-03 ("faltan los más buscados").
-- The shop page sends the term a customer searched or picked (no personal data, no IP, no session id). "Más buscados" =
-- the most frequent terms of the last 30 days (at least 3 searches each); until there are enough, the page shows
-- "Populares" (best sellers) instead. Written only by the Edge Function (service role).
-- Rollback: supabase/rollbacks/20261007002300_f360_storefront_searches.down.sql
CREATE TABLE f360.storefront_searches (
  id       bigserial PRIMARY KEY,
  term     text NOT NULL CHECK (length(term) BETWEEN 3 AND 60),
  country  text CHECK (length(country) <= 8),
  at       timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX storefront_searches_at_idx ON f360.storefront_searches (at DESC);

CREATE FUNCTION public.f360_log_search(p_term text, p_country text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE v text := btrim(regexp_replace(coalesce(p_term, ''), '[<>]', '', 'g'));
BEGIN
  IF length(v) < 3 THEN RETURN; END IF;
  INSERT INTO f360.storefront_searches (term, country) VALUES (left(v, 60), nullif(left(p_country, 8), ''));
END $$;

CREATE FUNCTION public.f360_top_searches(p_days int DEFAULT 30, p_limit int DEFAULT 6) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce(jsonb_agg(x.term ORDER BY x.n DESC, x.term), '[]') FROM (
    SELECT min(term) AS term, count(*) AS n FROM f360.storefront_searches
    WHERE at > now() - make_interval(days => greatest(1, least(p_days, 365)))
    GROUP BY lower(term) HAVING count(*) >= 3 ORDER BY count(*) DESC LIMIT greatest(1, least(p_limit, 20))) x
$$;

REVOKE ALL ON f360.storefront_searches FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.storefront_searches TO service_role;
GRANT USAGE ON SEQUENCE f360.storefront_searches_id_seq TO service_role;
REVOKE ALL ON FUNCTION public.f360_log_search(text, text), public.f360_top_searches(int, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_log_search(text, text), public.f360_top_searches(int, int) TO service_role;
