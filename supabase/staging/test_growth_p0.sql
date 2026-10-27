-- Growth P0 (Instagram, Clarity, experimentos) — rolled-back checks (staging).
-- Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/test_growth_p0.sql   (migrations 20261104000100/0200 applied)
-- To rehearse on a database without them, add after BEGIN:  -- @include supabase/migrations/<file>.sql  (one line per migration).
BEGIN;
CREATE TEMP TABLE t_out (n serial, line text) ON COMMIT DROP;
GRANT ALL ON t_out, t_out_n_seq TO PUBLIC;
CREATE FUNCTION pg_temp.ok(p_name text, p_cond boolean, p_detail text DEFAULT '') RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_out (line) VALUES (CASE WHEN p_cond THEN 'PASS | ' ELSE 'FAIL | ' END || p_name || CASE WHEN p_cond THEN '' ELSE ' · ' || coalesce(p_detail, '') END)
$$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(text, boolean, text) TO PUBLIC;

DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360_board.board_members WHERE person_key = 'MARIO');
  seller uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' ORDER BY created_at LIMIT 1);
  d jsonb; x jsonb; e1 uuid; e2 uuid; n int; failed boolean; msg text;
BEGIN
  -- G1 permissions: anon and seller refused on every read / write
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  failed := false; BEGIN PERFORM public.f360_growth_instagram(NULL, NULL); EXCEPTION WHEN insufficient_privilege THEN failed := true; END;
  PERFORM pg_temp.ok('G1a anon no lee Instagram', failed);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
  failed := false; BEGIN PERFORM public.f360_experiments_list(); EXCEPTION WHEN insufficient_privilege THEN failed := true; END;
  PERFORM pg_temp.ok('G1b vendedora no ve experimentos', failed);
  failed := false; BEGIN PERFORM public.f360_experiment_save(NULL, '{}'); EXCEPTION WHEN insufficient_privilege THEN failed := true; END;
  PERFORM pg_temp.ok('G1c vendedora no crea experimentos', failed);
  PERFORM pg_temp.ok('G1d authenticated no puede importar Instagram ni Clarity',
    NOT has_function_privilege('authenticated', 'public.f360_instagram_import(text, date, date, jsonb, jsonb)', 'execute')
    AND NOT has_function_privilege('authenticated', 'public.f360_clarity_import(date, int, text, jsonb)', 'execute')
    AND NOT has_table_privilege('authenticated', 'f360.growth_experiments', 'select'));

  -- G2 sources registered, not configured until a successful read
  PERFORM pg_temp.ok('G2 fuentes instagram y clarity registradas sin configurar',
    (SELECT count(*) FROM f360.measurement_sources WHERE key IN ('instagram', 'clarity') AND config_status = 'NOT_CONFIGURED' AND kind = 'api') = 2);
  d := f360.sg0_source_health();
  PERFORM pg_temp.ok('G2b Medición las muestra (tramo genérico de API)', d::text LIKE '%instagram%' AND d::text LIKE '%clarity%', left(d::text, 200));
END $$;

-- G3 Instagram import (service role)
SET LOCAL ROLE service_role;
DO $$
DECLARE d jsonb; failed boolean;
BEGIN
  d := public.f360_instagram_import('17841400765862195', '2026-07-23', '2026-07-24',
    '[{"date":"2026-07-23","reach":1200,"views":5000,"profile_views":80,"website_clicks":12},{"date":"2026-07-24","reach":900}]',
    '[{"media_id":"18000000000000001","kind":"reel","media_type":"VIDEO","media_product_type":"REELS","posted_at":"2026-07-23T18:00:00Z","permalink":"https://www.instagram.com/reel/ABCDE12345/","shortcode":"ABCDE12345","caption":"Ballerinas","metrics":{"reach":3000,"views":8000,"saves":40,"shares":12}},
      {"media_id":"18000000000000002","kind":"story","media_type":"IMAGE","media_product_type":"STORY","posted_at":"2026-07-24T15:00:00Z","metrics":{"reach":400,"replies":3}}]');
  PERFORM pg_temp.ok('G3a importa 2 días y 2 piezas', d->>'days' = '2' AND d->>'media' = '2', d::text);
  -- a newer read without a metric keeps the old value (NULL is "not returned", never 0)
  d := public.f360_instagram_import('17841400765862195', '2026-07-23', '2026-07-23', '[{"date":"2026-07-23","reach":1300}]', '[]');
  PERFORM pg_temp.ok('G3b relectura: gana el dato nuevo y no borra lo que no vino',
    (SELECT reach = 1300 AND views = 5000 AND website_clicks = 12 FROM f360.ig_account_daily WHERE date = '2026-07-23'));
  failed := false; BEGIN PERFORM public.f360_instagram_import('17841400765862195', '2026-07-23', '2026-07-23', '[{"date":"2026-07-23","reach":-5}]', '[]'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G3c rechaza un número negativo', failed);
  failed := false; BEGIN PERFORM public.f360_instagram_import('17841400765862195', '2026-07-23', '2026-07-23', '[{"date":"2026-08-01","reach":5}]', '[]'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G3d rechaza un día fuera de la ventana', failed);
  failed := false; BEGIN PERFORM public.f360_instagram_import('17841400765862195', '2026-07-23', '2026-07-23', '[]', '[{"media_id":"18000000000000003","kind":"tiktok","posted_at":"2026-07-23T00:00:00Z"}]'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G3e rechaza un tipo de contenido desconocido', failed);
  PERFORM pg_temp.ok('G3f corrida registrada y fuente configurada tras la primera lectura buena',
    EXISTS (SELECT 1 FROM f360.measurement_runs WHERE source_key = 'instagram' AND ok)
    AND (SELECT config_status FROM f360.measurement_sources WHERE key = 'instagram') = 'CONFIGURED');

  -- G5 Clarity
  d := public.f360_clarity_import('2026-10-27', 1, 'Source', '[{"metricName":"Traffic","information":[{"totalSessionCount":29,"Source":""}]}]');
  d := public.f360_clarity_import('2026-10-27', 1, 'Source', '[{"metricName":"Traffic","information":[{"totalSessionCount":30,"Source":""}]}]');
  PERFORM pg_temp.ok('G5a Clarity: una foto por día × desglose × métrica (la relectura reemplaza)',
    (SELECT count(*) FROM f360.clarity_snapshots WHERE window_end = '2026-10-27') = 1
    AND (SELECT information->0->>'totalSessionCount' FROM f360.clarity_snapshots WHERE window_end = '2026-10-27') = '30');
  failed := false; BEGIN PERFORM public.f360_clarity_import('2026-10-27', 4, '', '[]'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G5b Clarity rechaza más de 3 días', failed);
END $$;
RESET ROLE;

DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360_board.board_members WHERE person_key = 'MARIO');
  op uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' ORDER BY created_at LIMIT 1);
  d jsonb; m jsonb; e1 uuid; e2 uuid; failed boolean; msg text;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  -- G4 Instagram view: the July reconciliation (9 Instagram-only paid orders 23 jul – 2 ago; Facebook not mixed in)
  d := public.f360_growth_instagram('2026-07-23', '2026-08-02');
  PERFORM pg_temp.ok('G4a un renglón por día', jsonb_array_length(d->'daily') = 11, jsonb_array_length(d->'daily')::text);
  PERFORM pg_temp.ok('G4b ventas pagadas con último clic de Instagram sin anuncio = 9 (julio)', d->'sales'->>'paid_orders' = '9', (d->'sales')::text);
  PERFORM pg_temp.ok('G4c ninguna venta ligada a una publicación sin evidencia', d->'sales'->>'with_post_evidence' = '0' AND d->'sales'->>'without_post' = '9');
  PERFORM pg_temp.ok('G4d la suma diaria cuadra con el total',
    (SELECT sum((x->>'ig_paid_orders')::int) FROM jsonb_array_elements(d->'daily') x) = 9);
  PERFORM pg_temp.ok('G4e métricas de la cuenta y piezas por tipo',
    (d->'daily'->0->>'reach') = '1300' AND (d->'daily'->0->'published'->>'reel') = '1' AND (d->'daily'->1->'published'->>'story') = '1', (d->'daily'->0)::text);
  PERFORM pg_temp.ok('G4f limitaciones declaradas', jsonb_array_length(d->'limitations') >= 4);

  -- G6 experiments: draft → approve (owner) → running → verdict from paid orders → archived
  d := public.f360_experiment_save(NULL, '{"name":"Summer Sale MX (relectura)","hypothesis":"Si ofrecemos 15% y envío gratis en México por 11 días, las ventas pagadas suben a 15 o más.","market":"MX","primary_variable":"oferta","proposed_by":"mario","responsible":"agencia","primary_kpi":"paid_orders"}');
  e1 := (d->>'id')::uuid;
  PERFORM pg_temp.ok('G6a borrador creado con código EXP-AAAA-nnn', d->>'code' ~ '^EXP-\d{4}-\d{3}$', d::text);
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e1, 'APPROVED'); EXCEPTION WHEN OTHERS THEN failed := true; msg := SQLERRM; END;
  PERFORM pg_temp.ok('G6b no se aprueba sin fechas, presupuesto y umbrales', failed, msg);
  failed := false; BEGIN PERFORM public.f360_experiment_save(e1, '{"success_threshold":{"op":"=>","value":15,"min_sample":10}}'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G6c umbral mal escrito rechazado', failed);
  failed := false; BEGIN PERFORM public.f360_experiment_save(e1, '{"created_by":"00000000-0000-0000-0000-000000000000"}'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G6d la identidad no viene del formulario', failed);
  PERFORM public.f360_experiment_save(e1, '{"start_date":"2026-07-23","end_date":"2026-08-02","budget":0,"budget_currency":"MXN","success_threshold":{"op":">=","value":15,"min_sample":10},"kill_threshold":{"op":"<=","value":5,"min_sample":1}}');
  -- an operator (not owner) cannot approve
  UPDATE f360.user_roles SET role = 'operator' WHERE auth_user_id = op;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', op, 'role', 'authenticated')::text, true);
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e1, 'APPROVED'); EXCEPTION WHEN insufficient_privilege THEN failed := true; END;
  PERFORM pg_temp.ok('G6e operador no aprueba', failed);
  d := public.f360_experiments_list();
  PERFORM pg_temp.ok('G6f operador sí ve la lista y no puede aprobar', (d->>'can_approve')::boolean = false AND jsonb_array_length(d->'experiments') >= 1);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  PERFORM public.f360_experiment_transition(e1, 'APPROVED');
  failed := false; BEGIN PERFORM public.f360_experiment_save(e1, '{"success_threshold":{"op":">=","value":5,"min_sample":1}}'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G6g después de aprobado no se mueve la meta', failed);
  PERFORM public.f360_experiment_transition(e1, 'RUNNING');
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e1, 'LOSER', 'no vendió nada'); EXCEPTION WHEN OTHERS THEN failed := true; msg := SQLERRM; END;
  PERFORM pg_temp.ok('G6h no se puede declarar perdedor si no llegó al criterio de cancelar', failed, msg);
  PERFORM public.f360_experiment_transition(e1, 'WINNER', 'El Summer Sale vendió 20 pares pagados en 11 días.');
  SELECT result INTO m FROM f360.growth_experiments WHERE id = e1;
  PERFORM pg_temp.ok('G6i resultado calculado en el servidor desde pedidos pagados (20 en MX)', m->>'kpi_value' = '20' AND m->>'market_paid_orders' = '20' AND (m->>'success_met')::boolean, m::text);
  PERFORM pg_temp.ok('G6j evidencia etiquetada: antes/después, no causal', m->>'evidence' = 'antes_despues_mercado' AND m->>'evidence_note' LIKE '%no demuestra causalidad%');
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e1, 'ARCHIVED'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G6k no se archiva sin decisión', failed);
  PERFORM public.f360_experiment_transition(e1, 'ARCHIVED', NULL, 'ITERATE');

  -- G7 a campaign experiment with spend and no attributed sales is not a winner
  failed := false;
  BEGIN PERFORM public.f360_experiment_save(NULL, '{"name":"x","hypothesis":"Si pagamos visitas al perfil de Instagram, llegan clientas que compran.","market":"MX","primary_variable":"objetivo","proposed_by":"mario","responsible":"goyo","primary_kpi":"paid_orders","kill_threshold":{"op":"<=","value":0,"min_sample":0}}');
  EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G7a muestra mínima 0 rechazada', failed);
  d := public.f360_experiment_save(NULL, '{"name":"Seguidores IG octubre","hypothesis":"Si pagamos visitas al perfil de Instagram, llegan clientas que compran en la tienda.","market":"MX","primary_variable":"objetivo de campaña","proposed_by":"mario","responsible":"goyo","primary_kpi":"paid_orders","campaign_ids":["120250000000000001"],"start_date":"2026-10-01","end_date":"2026-10-26","success_threshold":{"op":">=","value":3,"min_sample":1},"kill_threshold":{"op":"<=","value":0,"min_sample":1}}');
  e2 := (d->>'id')::uuid;
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e2, 'APPROVED'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G7b sin presupuesto no se aprueba', failed);
  PERFORM public.f360_experiment_save(e2, '{"budget":1278,"budget_currency":"MXN"}');
  PERFORM public.f360_experiment_transition(e2, 'APPROVED'); PERFORM public.f360_experiment_transition(e2, 'RUNNING');
  failed := false; BEGIN PERFORM public.f360_experiment_transition(e2, 'WINNER', 'parecía ir bien'); EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G7c sin ventas atribuidas no puede ser ganador', failed);
  PERFORM public.f360_experiment_transition(e2, 'INCONCLUSIVE', 'Cero ventas atribuidas con la muestra disponible.');
  SELECT result INTO m FROM f360.growth_experiments WHERE id = e2;
  PERFORM pg_temp.ok('G7d atribución observada separada de causalidad', m->>'evidence' = 'atribucion_observada' AND m->>'attributed_paid_orders' = '0', m::text);

  -- G8 history and track record
  d := public.f360_experiments_list();
  PERFORM pg_temp.ok('G8a resultados cerrados primero', d->'experiments'->0->>'status' IN ('WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED'));
  PERFORM pg_temp.ok('G8b historial completo del primero (creado, cambios, aprobado, corriendo, ganador, archivado)',
    (SELECT count(*) FROM f360.growth_experiment_changes WHERE experiment_id = e1) >= 6);
  PERFORM pg_temp.ok('G8c récord por persona: Mario 1 ganador + 1 inconcluso; agencia y Goyo como responsables',
    EXISTS (SELECT 1 FROM jsonb_array_elements(d->'track_record') x WHERE x->>'party' = 'mario' AND x->>'winner' = '1' AND x->>'inconclusive' = '1')
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(d->'track_record') x WHERE x->>'party' = 'goyo' AND x->>'responsible' = '1'), (d->'track_record')::text);
  failed := false; BEGIN UPDATE f360.growth_experiment_changes SET reason = 'x' WHERE experiment_id = e1; EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G8d la bitácora no se edita', failed);
  failed := false; BEGIN DELETE FROM f360.growth_experiments WHERE id = e2; EXCEPTION WHEN OTHERS THEN failed := true; END;
  PERFORM pg_temp.ok('G8e un experimento no se borra', failed);
END $$;

SELECT line FROM t_out ORDER BY n;
ROLLBACK;
