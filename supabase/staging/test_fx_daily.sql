-- I0 · daily FX history + monthly proposal + approval by Mario — rolled-back checks (staging).
-- Run: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/staging/test_fx_daily.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  caro uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'carolina.demo@staging.invalid');
  seller uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' LIMIT 1);
  r jsonb; rows jsonb := '[]'; d date; i int; n int; v_usd uuid; v_cop uuid; open_month date := date_trunc('month', (now() AT TIME ZONE 'America/Mexico_City'))::date;
  as_svc text := json_build_object('role', 'service_role')::text;
  ref text := 'https://sidof.segob.gob.mx/dof/sidof/indicadores/158/01-03-2024/31-03-2024 ; https://www.datos.gov.co/resource/32sa-8pi3.json';
BEGIN
  IF seller IS NULL THEN   -- staging may have no seller: a throw-away one inside this rolled-back transaction
    INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-fx-seller@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO seller;
    INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (seller, 'seller', 'Vendedora de prueba');
  END IF;
  IF mario IS NULL OR caro IS NULL THEN RAISE EXCEPTION 'X0 fixtures: Mario / otra dueña'; END IF;
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('fx_rate', mario, 'Mario', 'test') ON CONFLICT DO NOTHING;
  DELETE FROM f360.approval_scopes WHERE scope = 'fx_rate' AND auth_user_id = caro;

  -- X1 record (service): 11 business days of March 2024, USD direct + COP cross, plus one reference 5 % off
  FOR i IN 0..16 LOOP
    d := '2024-03-01'::date + i;
    CONTINUE WHEN extract(isodow FROM d) > 5;
    rows := rows || jsonb_build_object('obs_date', d, 'currency', 'USD', 'rate', (17 + i * 0.01)::text, 'role', 'primary', 'method', 'DIRECT',
              'source', 'FIX de Banxico publicado en el DOF', 'source_reference', ref, 'inputs', jsonb_build_object('usd_mxn', 17 + i * 0.01))
            || jsonb_build_object('obs_date', d, 'currency', 'COP', 'rate', round((17 + i * 0.01) / 3900.0, 10)::text, 'role', 'primary', 'method', 'CROSS_USD',
              'source', 'FIX de Banxico (DOF) ÷ TRM del Banco de la República', 'source_reference', ref, 'inputs', jsonb_build_object('trm_cop_por_usd', 3900));
  END LOOP;
  rows := rows || jsonb_build_object('obs_date', '2024-03-15', 'currency', 'USD', 'rate', '17.85', 'role', 'reference', 'method', 'DIRECT',
            'source', 'ExchangeRate-API (acceso abierto, referencia)', 'source_reference', 'https://open.er-api.com/v6/latest/MXN');
  PERFORM set_config('request.jwt.claims', as_svc, true);
  r := public.f360_fx_observations_record('2024-03-01', '2024-03-17', rows);
  IF (r->>'new')::int <> jsonb_array_length(rows) OR jsonb_array_length(r->'inconsistencias') <> 1 THEN RAISE EXCEPTION 'X1 %', r; END IF;
  r := public.f360_fx_observations_record('2024-03-01', '2024-03-17', rows);
  IF (r->>'new')::int <> 0 OR (r->>'duplicates')::int <> jsonb_array_length(rows) THEN RAISE EXCEPTION 'X1 dedupe %', r; END IF;
  IF (SELECT count(*) FROM f360.measurement_runs WHERE source_key = 'fx_rates' AND window_from = '2024-03-01') < 2 THEN RAISE EXCEPTION 'X1 runs'; END IF;
  -- a revised figure for the same day is a NEW row and wins in fx_daily
  r := public.f360_fx_observations_record('2024-03-01', '2024-03-17', jsonb_build_array(jsonb_build_object('obs_date', '2024-03-01', 'currency', 'USD',
         'rate', '17.0050', 'role', 'primary', 'method', 'DIRECT', 'source', 'FIX de Banxico publicado en el DOF', 'source_reference', ref)));
  IF (SELECT rate FROM f360.fx_daily WHERE currency = 'USD' AND obs_date = '2024-03-01') <> 17.005
     OR (SELECT count(*) FROM f360.fx_observations WHERE currency = 'USD' AND obs_date = '2024-03-01' AND role = 'primary') <> 2 THEN RAISE EXCEPTION 'X1 revision'; END IF;

  -- X2 append-only
  BEGIN UPDATE f360.fx_observations SET rate = 1 WHERE obs_date = '2024-03-01'; RAISE EXCEPTION 'X2 update'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X2%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360.fx_observations WHERE obs_date = '2024-03-01'; RAISE EXCEPTION 'X2 delete'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X2%' THEN RAISE; END IF; END;

  -- X3 invalid rows refused (other currency, manual role through the daily path, bad rate)
  BEGIN PERFORM public.f360_fx_observations_record('2024-03-01', '2024-03-17', '[{"obs_date":"2024-03-04","currency":"EUR","rate":"20","role":"primary","method":"DIRECT","source":"x1","source_reference":"xxxx"}]');
    RAISE EXCEPTION 'X3 eur'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X3%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.f360_fx_observations_record('2024-03-01', '2024-03-17', '[{"obs_date":"2024-03-04","currency":"USD","rate":"20","role":"manual","method":"MANUAL","source":"x1","source_reference":"xxxx"}]');
    RAISE EXCEPTION 'X3 manual'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X3%' THEN RAISE; END IF; END;

  -- X4 monthly proposal: closed month with ≥ 10 days → proposed (average, documented, by the system); again → already exists;
  --    open month → skipped; a month with too few days → not proposed
  r := public.f360_fx_month_propose('2024-03-01');
  IF (SELECT count(*) FROM jsonb_array_elements(r->'monedas') m WHERE m->>'resultado' = 'propuesta') <> 2 THEN RAISE EXCEPTION 'X4 %', r; END IF;
  SELECT id INTO v_usd FROM f360.fx_rates WHERE currency = 'USD' AND period = '2024-03-01' AND status = 'proposed';
  SELECT id INTO v_cop FROM f360.fx_rates WHERE currency = 'COP' AND period = '2024-03-01' AND status = 'proposed';
  IF (SELECT rate FROM f360.fx_rates WHERE id = v_usd) <> (SELECT round(avg(rate), 8) FROM f360.fx_daily WHERE currency = 'USD' AND obs_date BETWEEN '2024-03-01' AND '2024-03-31')
     OR (SELECT rate_method FROM f360.fx_rates WHERE id = v_cop) <> 'MONTHLY_AVERAGE' OR (SELECT proposed_by FROM f360.fx_rates WHERE id = v_cop) <> f360.fx_system_proposer()
     OR (SELECT notes FROM f360.fx_rates WHERE id = v_cop) NOT LIKE '11 observaciones%' THEN RAISE EXCEPTION 'X4 content'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(public.f360_fx_month_propose('2024-03-01')->'monedas') m WHERE m->>'resultado' = 'ya existe') <> 2 THEN RAISE EXCEPTION 'X4 twice'; END IF;
  IF public.f360_fx_month_propose(open_month)->>'skipped' IS NULL THEN RAISE EXCEPTION 'X4 open month'; END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(public.f360_fx_month_propose('2024-04-01')->'monedas') m WHERE m->>'resultado' = 'pocas observaciones') <> 2 THEN RAISE EXCEPTION 'X4 few'; END IF;
  IF f360.fx_rate_for_report('COP', '2024-03-10')->>'status' <> 'missing' THEN RAISE EXCEPTION 'X4 proposed must not be used'; END IF;

  -- X5 approval: seller no, another owner not listed no (42501), Mario yes
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
  BEGIN PERFORM public.f360_fx_rate_approve(v_usd); RAISE EXCEPTION 'X5 seller'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X5%' THEN RAISE; END IF; WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated')::text, true);
  BEGIN PERFORM public.f360_fx_rate_approve(v_usd); RAISE EXCEPTION 'X5 other owner'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.f360_fx_month_propose('2024-03-01'); EXCEPTION WHEN others THEN RAISE EXCEPTION 'X5 owner may (re)propose: %', SQLERRM; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  PERFORM public.f360_fx_rate_approve(v_usd); PERFORM public.f360_fx_rate_approve(v_cop);
  IF (SELECT approved_by FROM f360.fx_rates WHERE id = v_cop) <> mario THEN RAISE EXCEPTION 'X5 approved_by'; END IF;

  -- X6 the rate a report applies: approved month / provisional for the open month / missing before
  IF f360.fx_rate_for_report('COP', '2024-03-10')->>'status' <> 'approved' OR (f360.fx_rate_for_report('COP', '2024-03-10')->>'id')::uuid <> v_cop THEN RAISE EXCEPTION 'X6 approved'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE currency = 'COP' AND period = open_month AND status = 'approved')
     AND f360.fx_rate_for_report('COP', open_month)->>'status' <> 'provisional' THEN RAISE EXCEPTION 'X6 provisional %', f360.fx_rate_for_report('COP', open_month); END IF;
  IF f360.fx_rate_for_report('COP', '2024-02-10')->>'status' <> 'missing' OR f360.fx_rate_for_report('MXN', '2024-02-10')->>'status' <> 'base' THEN RAISE EXCEPTION 'X6 missing/base'; END IF;

  -- X7 manual observation: owner yes (kept, never averaged), seller no
  r := public.f360_fx_observation_manual('2024-03-20', 'COP', 0.0057, 'Mario (Google)', 'Captura manual en el chat, prueba');
  IF NOT EXISTS (SELECT 1 FROM f360.fx_observations WHERE id = (r->>'id')::bigint AND role = 'manual' AND recorded_by = mario)
     OR EXISTS (SELECT 1 FROM f360.fx_daily WHERE currency = 'COP' AND obs_date = '2024-03-20' AND rate = 0.0057) THEN RAISE EXCEPTION 'X7 manual'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
  BEGIN PERFORM public.f360_fx_observation_manual('2024-03-20', 'COP', 0.0057, 'x1', 'xxxx'); RAISE EXCEPTION 'X7 seller'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X7%' THEN RAISE; END IF; WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.f360_fx_status(); RAISE EXCEPTION 'X7 seller status'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'X7%' THEN RAISE; END IF; WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  r := public.f360_fx_status();
  IF NOT (r->>'can_approve')::boolean OR jsonb_array_length(r->'months') < 2 THEN RAISE EXCEPTION 'X7 status %', r; END IF;

  -- X8 grants
  IF has_function_privilege('authenticated', 'public.f360_fx_observations_record(date,date,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.f360_fx_status()', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_fx_month_propose(date)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'f360.fx_observations', 'SELECT') OR has_table_privilege('authenticated', 'f360.approval_scopes', 'INSERT')
     OR has_table_privilege('authenticated', 'f360.fx_daily', 'SELECT') THEN RAISE EXCEPTION 'X8 grants'; END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobname = 'f360-fx-rates' AND schedule = '0 14 * * *') <> 1 THEN RAISE EXCEPTION 'X8 cron'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
