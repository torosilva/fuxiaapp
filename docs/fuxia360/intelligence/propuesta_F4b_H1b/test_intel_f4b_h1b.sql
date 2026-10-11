-- F4b / H1b regression checks (staging). Runs ONLY inside ensayo.sql (migration applied in the same rolled-back transaction), or
-- after the approved application wrapped in BEGIN … ROLLBACK. Writes nothing that survives.
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  truth jsonb := f360.intel_low_sell_page(60, 1, 20); ev jsonb; r jsonb; t text; c record; v bigint; today date := f360.intel_today();
BEGIN
  -- T1 F4b: the signal reports the WHOLE list (same totals as the paged tool), not the 20-row sample
  ev := (SELECT s->'evidencia' FROM jsonb_array_elements(f360.intel_signals_core(today - 6, today)->'data'->'senales') s WHERE s->>'codigo' = 'INVENTARIO_BAJA_SALIDA');
  IF ev IS NULL THEN RAISE EXCEPTION 'T1 no signal (truth %)', truth->'total_modelos'; END IF;
  IF (ev->>'modelos')::int <> (truth->>'total_modelos')::int OR (ev->>'pares')::int <> (truth->>'total_pares')::int THEN
    RAISE EXCEPTION 'T1 signal % modelos / % pares vs truth % / %', ev->'modelos', ev->'pares', truth->'total_modelos', truth->'total_pares';
  END IF;
  IF jsonb_array_length(ev->'ejemplos') > 5 OR ev->>'ejemplos_nota' NOT LIKE '5 ejemplos de%' THEN RAISE EXCEPTION 'T1 sample labelling %', ev; END IF;
  RAISE NOTICE 'T1 F4b: señal = % modelos y % pares (lista completa: % / %)', ev->'modelos', ev->'pares', truth->'total_modelos', truth->'total_pares';

  -- T2 H1b: valid dates kept; emails, phones, card / account numbers still masked
  FOR c IN SELECT * FROM (VALUES
      ('¿Cuánto vendimos del 2026-08-01 al 2026-08-31?',            '¿Cuánto vendimos del 2026-08-01 al 2026-08-31?'),
      ('entre el 01/08/2026 y el 31/8/26',                           'entre el 01/08/2026 y el 31/8/26'),
      ('llámale al +52 55 1234 5678 o al (55) 1234-5678',            'llámale al [número] o al ([número]'),
      ('mi correo es ana.perez@example.com',                         'mi correo es [correo]'),
      ('tarjeta 4111 1111 1111 1111 y cuenta 012180001234567891',    'tarjeta [número] y cuenta [número]'),
      ('el 2026-08-01 llamó al 5512345678 (ana@x.mx)',               'el 2026-08-01 llamó al [número] ([correo])'),
      ('folio 2026-13-45 no es fecha',                               'folio [número] no es fecha'),       -- month 13: not a date → masked as before
      ('número 2026-08-01-5512345678',                               'número 2026-08-01-[número]'),      -- the date is kept, the phone part masked
      (NULL,                                                         '')) AS x(inp, expected) LOOP
    t := f360.ai_mask(c.inp);
    IF t IS DISTINCT FROM c.expected THEN RAISE EXCEPTION 'T2 mask(%) = % (esperado %)', c.inp, t, c.expected; END IF;
  END LOOP;
  IF length(f360.ai_mask(repeat('a', 3000))) <> 2000 THEN RAISE EXCEPTION 'T2 length cap'; END IF;
  -- the audit stores the masked question through the same function
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  v := public.f360_ai_log(jsonb_build_object('auth_user_id', mario, 'question', 'del 2026-08-01 al 2026-08-31, tel +52 55 1234 5678', 'status', 'ok'));
  IF (SELECT question_masked FROM f360.ai_queries WHERE id = v) <> 'del 2026-08-01 al 2026-08-31, tel [número]' THEN RAISE EXCEPTION 'T2 audit %', (SELECT question_masked FROM f360.ai_queries WHERE id = v); END IF;

  -- T3 weekly priorities read the complete set through the analyst's tool (board gate, as Mario)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_intel_query('senales_semana', jsonb_build_object('desde', today - 6, 'hasta', today));
  ev := (SELECT s->'evidencia' FROM jsonb_array_elements(r->'data'->'senales') s WHERE s->>'codigo' = 'INVENTARIO_BAJA_SALIDA');
  IF r->>'ok' <> 'true' OR (ev->>'modelos')::int <> (truth->>'total_modelos')::int THEN RAISE EXCEPTION 'T3 %', r; END IF;

  -- T4 every other analyst tool still answers with data + meta
  FOREACH t IN ARRAY ARRAY['ventas','presupuesto_vs_real','avance_meta','marketing','pagos','inventario_mx','inventario_baja_salida','margen','caja','proyeccion_cierre','embudo','senales_semana','fuentes'] LOOP
    r := public.f360_intel_query(t, '{"desde":"2026-06-01","hasta":"2026-10-11","mes":"2026-09-01","dias":60}');
    IF r->>'ok' <> 'true' OR NOT (r ? 'meta') OR r->'meta'->>'disponibilidad' IS NULL THEN RAISE EXCEPTION 'T4 tool % → %', t, left(r::text, 200); END IF;
  END LOOP;
  RAISE NOTICE 'ENSAYO F4b/H1b OK';
END $$;
