-- Fuxia 360 · PRODUCCIÓN · Fuxia Kids, tablero semanal de "Atrapa las estrellas" (Mario 2026-10-24). Migración 20261103000100, igual a
-- staging (aplicada y probada ahí: supabase/staging/test_kids_leaderboard.sql 7/7). Solo AGREGA una tabla nueva (f360.kids_scores) y
-- 4 funciones; no toca pedidos, clientas, inventario ni otras tablas. Sin premios ni cupones; nombres de una lista fija; sin IP.
-- Reversión: supabase/rollbacks/20261103000100_f360_kids_leaderboard.down.sql (vía prod_sql.sh; pierde solo los puntajes del juego).
BEGIN;
DO $$ BEGIN
  IF to_regclass('f360.kids_scores') IS NOT NULL OR EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261103000100') THEN
    RAISE EXCEPTION 'KIDS PRE: ya está instalada'; END IF;
END $$;
CREATE TABLE f360.kids_scores (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  week_start  date NOT NULL,
  market      text NOT NULL CHECK (market IN ('mx', 'co')),
  dancer_name text NOT NULL CHECK (length(dancer_name) <= 40),
  dancer_num  smallint CHECK (dancer_num BETWEEN 1 AND 99),
  score       integer NOT NULL CHECK (score BETWEEN 0 AND 480),
  device_hash text NOT NULL CHECK (device_hash ~ '^[0-9a-f]{64}$'),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX kids_scores_week ON f360.kids_scores (market, week_start, score DESC);
CREATE INDEX kids_scores_device ON f360.kids_scores (device_hash, created_at DESC);
ALTER TABLE f360.kids_scores ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.kids_scores FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.kids_dancer_names() RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT ARRAY['Estrellita Dorada','Luna de Plata','Perla Rosa','Brillo de Oro','Bailarina de Cristal','Rosa de Seda','Lucero Rosa',
               'Nube de Tul','Princesa Pointe','Mariposa Dorada','Gota de Rocío','Lirio Blanco','Flor de Tutú','Cometa Rosa','Hada de Satén',
               'Estrella Fugaz','Coral de Mar','Azucena','Violeta Brillante','Aurora Rosa','Copito de Nieve','Lunita','Chispita Dorada','Arabesque']
$$;
CREATE FUNCTION f360.kids_week_start(p_at timestamptz DEFAULT now()) RETURNS date LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT date_trunc('week', p_at AT TIME ZONE 'America/Mexico_City')::date
$$;

CREATE FUNCTION public.f360_kids_top(p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE m text := lower(coalesce(p_market, '')); w date := f360.kids_week_start();
BEGIN
  IF m NOT IN ('mx', 'co') THEN RETURN jsonb_build_object('ok', false, 'error', 'mercado'); END IF;
  RETURN jsonb_build_object('ok', true, 'week_start', w, 'top', coalesce((
    SELECT jsonb_agg(jsonb_build_object('name', b.dancer_name || coalesce(' ' || b.dancer_num, ''), 'score', b.score) ORDER BY b.score DESC, b.created_at)
    FROM (SELECT * FROM (SELECT DISTINCT ON (device_hash) dancer_name, dancer_num, score, created_at FROM f360.kids_scores
                         WHERE market = m AND week_start = w ORDER BY device_hash, score DESC, created_at DESC) d
          ORDER BY score DESC, created_at LIMIT 10) b), '[]'::jsonb));
END $$;

CREATE FUNCTION public.f360_kids_score_submit(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE m text := lower(coalesce(p->>'market', '')); nm text := p->>'name'; anon text := coalesce(p->>'anon_id', '');
  num_t text := p->>'num'; sc_t text := p->>'score'; num smallint; sc integer; dev text; w date := f360.kids_week_start();
BEGIN
  IF m NOT IN ('mx', 'co') THEN RETURN jsonb_build_object('ok', false, 'error', 'mercado'); END IF;
  IF nm IS NULL OR NOT (nm = ANY (f360.kids_dancer_names())) THEN RETURN jsonb_build_object('ok', false, 'error', 'nombre'); END IF;
  IF anon !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'dispositivo'); END IF;
  IF sc_t IS NULL OR sc_t !~ '^[0-9]{1,3}$' THEN RETURN jsonb_build_object('ok', false, 'error', 'puntaje'); END IF;
  sc := sc_t::integer;
  IF sc > 480 THEN RETURN jsonb_build_object('ok', false, 'error', 'puntaje'); END IF;   -- 50 s: ≤ 95 stars, ≤ 5 each
  IF num_t IS NOT NULL AND num_t <> '' THEN
    IF num_t !~ '^[0-9]{1,2}$' OR num_t::integer NOT BETWEEN 1 AND 99 THEN RETURN jsonb_build_object('ok', false, 'error', 'numero'); END IF;
    num := num_t::smallint;
  END IF;
  dev := encode(sha256(convert_to('f360-kids-v1:' || lower(anon), 'UTF8')), 'hex');
  IF (SELECT count(*) FROM f360.kids_scores WHERE device_hash = dev AND created_at > now() - interval '1 hour') >= 8
     OR (SELECT count(*) FROM f360.kids_scores WHERE device_hash = dev AND created_at > now() - interval '1 day') >= 40 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'limite');
  END IF;
  IF (SELECT count(*) FROM f360.kids_scores WHERE market = m AND created_at > now() - interval '1 day') >= 5000 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'limite');
  END IF;
  INSERT INTO f360.kids_scores (week_start, market, dancer_name, dancer_num, score, device_hash) VALUES (w, m, nm, num, sc, dev);
  RETURN public.f360_kids_top(m) || jsonb_build_object('mine', (SELECT max(score) FROM f360.kids_scores WHERE device_hash = dev AND market = m AND week_start = w));
END $$;

REVOKE ALL ON FUNCTION public.f360_kids_top(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_kids_score_submit(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_kids_top(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.f360_kids_score_submit(jsonb) TO service_role;
REVOKE ALL ON FUNCTION f360.kids_dancer_names() FROM PUBLIC;
REVOKE ALL ON FUNCTION f360.kids_week_start(timestamptz) FROM PUBLIC;

INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('20261103000100', 'f360_kids_leaderboard');
DO $$ BEGIN
  IF has_function_privilege('anon', 'public.f360_kids_score_submit(jsonb)', 'EXECUTE') OR has_table_privilege('anon', 'f360.kids_scores', 'SELECT')
     OR NOT has_function_privilege('service_role', 'public.f360_kids_top(text)', 'EXECUTE') THEN RAISE EXCEPTION 'KIDS POST: permisos'; END IF;
END $$;
COMMIT;
