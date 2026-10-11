-- I3 · AI analyst audit + consumption controls — rolled-back checks (staging). Run as a whole file (BEGIN … ROLLBACK).
BEGIN;
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  caro uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'carolina.demo@staging.invalid');
  q jsonb; v bigint; i int; r jsonb;
BEGIN
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('budget', mario, 'Mario', 'test') ON CONFLICT DO NOTHING;
  DELETE FROM f360.approval_scopes WHERE scope = 'budget' AND auth_user_id = caro;
  -- A1 defaults: Claude Sonnet 5.5, USD 100 / month, 40 per person per day, 6 tools, 1,500 output tokens
  IF (SELECT row(model, monthly_budget_usd, per_user_daily, max_tool_calls, max_output_tokens)::text FROM f360.ai_settings) <> '(claude-sonnet-5-5,100.00,40,6,1500)' THEN RAISE EXCEPTION 'A1'; END IF;
  -- A2 cost is computed by the database from its own prices (not trusted from the caller) and the question is masked
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  v := public.f360_ai_log(jsonb_build_object('auth_user_id', mario, 'question', 'Escríbele a ana@example.com o al +52 55 1234 5678', 'status', 'ok',
         'tokens_input', 30000, 'tokens_output', 2000, 'tokens_cache_read', 6000, 'cost_usd', 999, 'model', 'claude-sonnet-5-5'));
  IF (SELECT cost_usd FROM f360.ai_queries WHERE id = v) <> round((30000 * 2 + 2000 * 10 + 6000 * 0.1) / 1e6, 5)
     OR (SELECT question_masked FROM f360.ai_queries WHERE id = v) <> 'Escríbele a [correo] o al [número]' THEN RAISE EXCEPTION 'A2 %', (SELECT row(cost_usd, question_masked) FROM f360.ai_queries WHERE id = v); END IF;
  BEGIN UPDATE f360.ai_queries SET cost_usd = 0 WHERE id = v; RAISE EXCEPTION 'A2 update'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'A2%' THEN RAISE; END IF; END;
  -- A3 per-person daily cap
  FOR i IN 1..39 LOOP PERFORM public.f360_ai_log(jsonb_build_object('auth_user_id', mario, 'question', 'p', 'status', 'ok')); END LOOP;
  q := public.f360_ai_quota(mario);
  IF (q->>'allowed')::boolean OR q->>'reason' <> 'limite_usuario' OR NOT (public.f360_ai_quota(caro)->>'allowed')::boolean THEN RAISE EXCEPTION 'A3 %', q; END IF;
  -- A4 monthly budget: hard stop at 100 %, warning from 80 %
  PERFORM public.f360_ai_log(jsonb_build_object('auth_user_id', caro, 'question', 'p', 'status', 'ok', 'tokens_output', 8100000));  -- USD 81
  IF NOT (public.f360_ai_quota(caro)->>'warning')::boolean OR NOT (public.f360_ai_quota(caro)->>'allowed')::boolean THEN RAISE EXCEPTION 'A4 warning'; END IF;
  PERFORM public.f360_ai_log(jsonb_build_object('auth_user_id', caro, 'question', 'p', 'status', 'ok', 'tokens_output', 2000000));   -- USD 20 → 101
  IF (public.f360_ai_quota(caro)->>'allowed')::boolean OR public.f360_ai_quota(caro)->>'reason' <> 'limite_mes' THEN RAISE EXCEPTION 'A4 stop'; END IF;
  -- A5 settings: only the budget approver (Mario), with a reason; history kept; out-of-range refused
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_ai_settings_set('{"monthly_budget_usd":500}', 'subir el tope'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'A5 caro'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_ai_settings_set('{"monthly_budget_usd":150}', 'x'))->>'ok' <> 'false' OR (public.f360_ai_settings_set('{"sql":"x"}', 'campo raro'))->>'ok' <> 'false'
     OR (public.f360_ai_settings_set('{"max_tool_calls":99}', 'demasiadas herramientas'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'A5 validation'; END IF;
  r := public.f360_ai_settings_set('{"monthly_budget_usd":150}', 'Prueba: subir el tope a 150');
  IF r->>'ok' <> 'true' OR (SELECT count(*) FROM f360.ai_settings_changes) < 1 OR (public.f360_ai_quota(caro)->>'allowed')::boolean <> true THEN RAISE EXCEPTION 'A5 %', r; END IF;
  -- A6 history: only my own; usage: per person
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(public.f360_ai_history()->'items') x WHERE x->>'question' = 'p' AND (x->>'cost_usd')::numeric > 50) THEN RAISE EXCEPTION 'A6 own'; END IF;
  IF jsonb_array_length(public.f360_ai_usage()->'month'->'por_persona') < 2 THEN RAISE EXCEPTION 'A6 usage'; END IF;
  -- A7 grants: nobody writes the audit or reads the tables directly
  IF has_function_privilege('authenticated', 'public.f360_ai_log(jsonb)', 'EXECUTE') OR has_function_privilege('authenticated', 'public.f360_ai_quota(uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'f360.ai_queries', 'SELECT') OR has_function_privilege('anon', 'public.f360_ai_history()', 'EXECUTE') THEN RAISE EXCEPTION 'A7'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
