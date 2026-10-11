-- F4 / F5 / H2 regression checks (staging). Run ONLY wrapped by the rehearsal (migration applied in the same rolled-back transaction).
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  r jsonb; x jsonb; lp jsonb; n int; tot int; pages int; seen int := 0; pg int; q1 jsonb; q2 jsonb; v bigint; b0 numeric; d0 int;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);

  -- R1 F4: the capped list carries its total; paging returns every model exactly once
  r := public.f360_intel_query('inventario_mx', '{"dias":60}');
  lp := f360.intel_low_sell_page(60, 1, 20);
  IF (r->'data'->'baja_salida_total'->>'modelos')::int <> (lp->>'total_modelos')::int
     OR (r->'data'->'baja_salida_total'->>'mostrados')::int <> jsonb_array_length(r->'data'->'baja_salida')
     OR (r->'data'->'baja_salida_total'->>'limitada')::boolean <> ((lp->>'total_modelos')::int > jsonb_array_length(r->'data'->'baja_salida'))
     OR (r->'data'->'baja_salida_total'->>'faltan')::int <> greatest(0, (lp->>'total_modelos')::int - jsonb_array_length(r->'data'->'baja_salida')) THEN
    RAISE EXCEPTION 'R1 totals %', r->'data'->'baja_salida_total';
  END IF;
  tot := (lp->>'total_modelos')::int; pages := ((f360.intel_low_sell_page(60, 1, 7))->>'paginas')::int;
  CREATE TEMP TABLE _names (name text) ON COMMIT DROP;
  FOR pg IN 1..pages LOOP
    INSERT INTO _names SELECT i->>'modelo' FROM jsonb_array_elements((f360.intel_low_sell_page(60, pg, 7))->'items') i;
  END LOOP;
  IF (SELECT count(*) FROM _names) <> tot OR (SELECT count(DISTINCT name) FROM _names) <> tot THEN RAISE EXCEPTION 'R1 paging % vs %', (SELECT count(*) FROM _names), tot; END IF;
  r := public.f360_intel_query('inventario_baja_salida', '{"pagina":2,"por_pagina":5}');
  IF r->>'ok' <> 'true' OR (r->'data'->>'pagina')::int <> 2 OR (r->'data'->>'por_pagina')::int <> 5 THEN RAISE EXCEPTION 'R1 tool %', r; END IF;

  -- R2 F5: online + store = combined; Meta-attributed ⊆ online; ROAS only from attributed revenue; store sales never in ROAS
  r := public.f360_intel_query('marketing', '{"desde":"2026-06-01","hasta":"2026-10-11"}');
  FOR x IN SELECT * FROM jsonb_array_elements(r->'data'->'por_mercado') LOOP
    IF (x->'venta_en_linea'->>'monto')::numeric + (x->'venta_tienda'->>'monto')::numeric <> (x->'venta_neta'->>'monto')::numeric THEN RAISE EXCEPTION 'R2 split %', x->>'mercado'; END IF;
    IF (x->'ingresos_atribuidos_meta'->>'monto')::numeric > (x->'venta_en_linea'->>'monto')::numeric THEN RAISE EXCEPTION 'R2 attributed > online %', x->>'mercado'; END IF;
    IF x->'roas_atribuido'->>'valor' IS NOT NULL AND (x->'roas_atribuido'->>'valor')::numeric
         <> round((x->'ingresos_atribuidos_meta_mxn'->>'mxn')::numeric / (x->'inversion_mxn'->>'mxn')::numeric, 2) THEN RAISE EXCEPTION 'R2 roas formula %', x; END IF;
    IF x->>'mer_definicion' NOT LIKE '%NO es ROAS%' OR x->'venta_tienda'->>'nota' NOT LIKE '%NO atribuida%' THEN RAISE EXCEPTION 'R2 labels %', x->>'mercado'; END IF;
    -- attributed ⊆ online ⊆ combined, same spend → ROAS ≤ online efficiency ≤ combined efficiency (store sales can never inflate the ROAS)
    IF x->'roas_atribuido'->>'valor' IS NOT NULL AND ((x->'roas_atribuido'->>'valor')::numeric > (x->>'eficiencia_en_linea')::numeric
       OR (x->>'eficiencia_en_linea')::numeric > (x->>'eficiencia_combinada')::numeric) THEN RAISE EXCEPTION 'R2 ordering %', x; END IF;
  END LOOP;
  -- CO: spend in MXN, sales in COP, no approved COP rate in staging → ROAS FALTA (never converted with a proposed rate)
  IF NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE currency = 'COP' AND status = 'approved')
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'data'->'por_mercado') e WHERE e->>'mercado' = 'CO' AND (e->'ingresos_atribuidos_meta'->>'monto')::numeric > 0 AND e->'roas_atribuido'->>'valor' IS NOT NULL)
     THEN RAISE EXCEPTION 'R2 CO converted without approved rate'; END IF;

  -- R3 H2: reservations are atomic and count against the limits until the audit row is written (limits restored afterwards)
  SELECT monthly_budget_usd, per_user_daily INTO b0, d0 FROM f360.ai_settings;
  UPDATE f360.ai_settings SET monthly_budget_usd = (SELECT coalesce(sum(cost_usd), 0) FROM f360.ai_queries WHERE at >= date_trunc('month', now() AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'America/Mexico_City') + 0.30;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  q1 := public.f360_ai_reserve(mario, 0.20);
  q2 := public.f360_ai_reserve(mario, 0.20);
  IF NOT (q1->>'allowed')::boolean OR (q2->>'allowed')::boolean OR q2->>'reason' <> 'limite_mes' THEN RAISE EXCEPTION 'R3 % / %', q1, q2; END IF;
  v := public.f360_ai_log(jsonb_build_object('auth_user_id', mario, 'question', 'r3', 'status', 'ok', 'reservation_id', (q1->>'reservation_id')::bigint));
  IF EXISTS (SELECT 1 FROM f360.ai_inflight WHERE id = (q1->>'reservation_id')::bigint) THEN RAISE EXCEPTION 'R3 not released'; END IF;
  IF NOT (public.f360_ai_reserve(mario, 0.20)->>'allowed')::boolean THEN RAISE EXCEPTION 'R3 after release'; END IF;
  INSERT INTO f360.ai_inflight (auth_user_id, started_at, est_cost_usd) VALUES (mario, now() - interval '11 minutes', 50);
  PERFORM public.f360_ai_reserve(mario, 0);
  IF EXISTS (SELECT 1 FROM f360.ai_inflight WHERE est_cost_usd = 50) THEN RAISE EXCEPTION 'R3 stale kept'; END IF;
  UPDATE f360.ai_settings SET monthly_budget_usd = 100000, per_user_daily = (SELECT count(*) FROM f360.ai_queries WHERE auth_user_id = mario AND status = 'ok'
         AND at >= date_trunc('day', now() AT TIME ZONE 'America/Mexico_City') AT TIME ZONE 'America/Mexico_City') + (SELECT count(*) FROM f360.ai_inflight WHERE auth_user_id = mario) + 1;
  IF NOT (public.f360_ai_reserve(mario, 0)->>'allowed')::boolean OR public.f360_ai_reserve(mario, 0)->>'reason' <> 'limite_usuario' THEN RAISE EXCEPTION 'R3 daily cap with in-flight'; END IF;

  UPDATE f360.ai_settings SET monthly_budget_usd = b0, per_user_daily = d0;
  DELETE FROM f360.ai_inflight;

  -- R4 grants of the new objects
  IF has_function_privilege('authenticated', 'public.f360_ai_reserve(uuid,numeric)', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_ai_reserve(uuid,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'f360.intel_low_sell_page(int,int,int)', 'EXECUTE') OR has_table_privilege('authenticated', 'f360.ai_inflight', 'SELECT')
     OR NOT has_function_privilege('authenticated', 'public.f360_intel_query(text,jsonb)', 'EXECUTE') THEN RAISE EXCEPTION 'R4 grants'; END IF;
  RAISE NOTICE 'ENSAYO F4/F5/H2 OK';
END $$;
