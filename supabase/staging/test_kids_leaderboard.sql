-- 20261103000100 Fuxia Kids weekly board — rolled-back checks (staging).
-- Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/test_kids_leaderboard.sql
-- Before the migration is applied to staging, uncomment the include line to rehearse it inside this transaction.
BEGIN;
-- @include supabase/migrations/20261103000100_f360_kids_leaderboard.sql
CREATE TEMP TABLE _r (n serial, line text);
DO $$
DECLARE a text := '11111111-2222-4333-8444-555555555555'; b text := 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'; r jsonb; i int;
BEGIN
  -- K1 a valid round is stored and comes back in the week's top
  r := public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'num', 7, 'score', 120, 'anon_id', a));
  IF NOT (r->>'ok')::boolean OR (r->>'mine')::int <> 120 OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'top') x WHERE x->>'name' = 'Perla Rosa 7' AND (x->>'score')::int = 120)
    THEN RAISE EXCEPTION 'K1 %', r; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K1 puntaje válido guardado y en el top de la semana');
  -- K2 free text, out-of-range score, bad market / number / device are refused
  IF (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'María López', 'score', 10, 'anon_id', a))->>'error') <> 'nombre'
     OR (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'score', 481, 'anon_id', a))->>'error') <> 'puntaje'
     OR (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'score', -3, 'anon_id', a))->>'error') <> 'puntaje'
     OR (public.f360_kids_score_submit(jsonb_build_object('market', 'us', 'name', 'Perla Rosa', 'score', 3, 'anon_id', a))->>'error') <> 'mercado'
     OR (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'num', 100, 'score', 3, 'anon_id', a))->>'error') <> 'numero'
     OR (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'score', 3, 'anon_id', 'x'))->>'error') <> 'dispositivo'
    THEN RAISE EXCEPTION 'K2 validation'; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K2 rechaza texto libre, puntaje fuera de rango, mercado, número y dispositivo inválidos');
  -- K3 one device cannot fill the board: only its best counts
  PERFORM public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Perla Rosa', 'num', 7, 'score', 90, 'anon_id', a));
  r := public.f360_kids_top('mx');
  IF (SELECT count(*) FROM jsonb_array_elements(r->'top') x WHERE x->>'name' = 'Perla Rosa 7') <> 1 THEN RAISE EXCEPTION 'K3 %', r; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K3 un dispositivo sale una sola vez (su mejor puntaje)');
  -- K4 rate limit: 8 per hour per device (2 already sent)
  FOR i IN 1..6 LOOP PERFORM public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Lunita', 'score', i, 'anon_id', a)); END LOOP;
  IF (public.f360_kids_score_submit(jsonb_build_object('market', 'mx', 'name', 'Lunita', 'score', 1, 'anon_id', a))->>'error') <> 'limite' THEN RAISE EXCEPTION 'K4'; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K4 límite de 8 envíos por hora por dispositivo');
  -- K5 markets are separate; no device id or hash leaves the database
  r := public.f360_kids_score_submit(jsonb_build_object('market', 'co', 'name', 'Luna de Plata', 'score', 55, 'anon_id', b));
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'top') x WHERE x->>'name' LIKE 'Perla Rosa%') OR r::text ~ '[0-9a-f]{64}' OR r::text ILIKE '%' || b || '%'
    THEN RAISE EXCEPTION 'K5 %', r; END IF;
  IF EXISTS (SELECT 1 FROM f360.kids_scores WHERE device_hash = b OR device_hash = a) THEN RAISE EXCEPTION 'K5 raw id stored'; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K5 MX y CO separados; el id del dispositivo no se guarda ni se devuelve');
  -- K6 week starts Monday 00:00 CDMX
  IF f360.kids_week_start('2026-10-26 05:59:00+00') <> '2026-10-19' OR f360.kids_week_start('2026-10-26 06:00:00+00') <> '2026-10-26'
    THEN RAISE EXCEPTION 'K6'; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K6 la semana empieza el lunes 00:00 hora CDMX');
  -- K7 grants: only the service role (the edge function) can call; nobody reads the table directly
  IF has_function_privilege('anon', 'public.f360_kids_score_submit(jsonb)', 'EXECUTE') OR has_function_privilege('authenticated', 'public.f360_kids_top(text)', 'EXECUTE')
     OR has_table_privilege('anon', 'f360.kids_scores', 'SELECT') OR has_table_privilege('authenticated', 'f360.kids_scores', 'SELECT')
     OR NOT has_function_privilege('service_role', 'public.f360_kids_score_submit(jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'K7 grants'; END IF;
  INSERT INTO _r (line) VALUES ('PASS | K7 solo la función de la tienda puede llamar; la tabla no se lee directo');
END $$;
SELECT line FROM _r ORDER BY n;
ROLLBACK;
