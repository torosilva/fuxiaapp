-- 0700 · contadora: least privilege, proven by SWEEPING every function and table (staging). Run as a whole file: BEGIN … ROLLBACK.
-- Invariant: the contadora reaches NOTHING more than a signed-in person with no Fuxia 360 role, except the 6 finance-capture RPCs.
-- Every public function executable by `authenticated` is called directly (SET ROLE authenticated + JWT claims, NULL arguments,
-- 3 s limit, each in its own sub-transaction); every table/view readable by `authenticated` is counted under RLS.
BEGIN;
CREATE TEMP TABLE _fa_result (who text, kind text, obj text, outcome text) ON COMMIT DROP;
GRANT ALL ON _fa_result TO authenticated;
DO $$
DECLARE conta uuid; plain uuid; viewer uuid; mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  f record; t record; w record; call text; res text; oc text; n bigint; st jsonb; bad text;
  allowed text[] := ARRAY['f360_finance_access_state', 'f360_close_prep_context', 'f360_close_prep_entry_add', 'f360_close_prep_entry_void',
                          'f360_finance_commitment_add', 'f360_finance_commitment_event'];
BEGIN
  -- fixtures (this transaction only): contadora WITHOUT role + preparer; a signed-in person without role; a viewer
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-fa-conta@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO conta;
  INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, granted_by_name, evidence) VALUES (conta, 'Contadora (prueba)', 'test', 'prueba');
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-fa-plain@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO plain;
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-fa-viewer@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO viewer;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (viewer, 'viewer', 'Lectura (prueba)');

  -- C1 guard: a preparer cannot hold an F360 role; if one is granted later, finance capture stops (defense in depth)
  BEGIN INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, granted_by_name, evidence) VALUES (viewer, 'x', 'test', 'x'); RAISE EXCEPTION 'C1 guard';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'C1%' THEN RAISE; END IF; END;

  -- C2 access state: only the caller's own status
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  st := public.f360_finance_access_state();
  IF NOT (st->>'preparadora')::boolean OR (st->>'consejo')::boolean OR (st->>'rol_f360')::boolean OR NOT (st->>'can_close')::boolean THEN RAISE EXCEPTION 'C2 conta %', st; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  IF NOT (public.f360_finance_access_state()->>'mfa_requerido')::boolean THEN RAISE EXCEPTION 'C2 mfa'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', plain, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_finance_access_state()->>'preparadora')::boolean THEN RAISE EXCEPTION 'C2 plain'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF NOT (public.f360_finance_access_state()->>'consejo')::boolean OR (public.f360_finance_access_state()->>'preparadora')::boolean THEN RAISE EXCEPTION 'C2 board'; END IF;

  -- C3 sweep of every function and every readable table, for the 3 identities
  FOR w IN SELECT * FROM (VALUES ('contadora', conta), ('sin_rol', plain), ('viewer', viewer)) AS w(name, uid) LOOP
    FOR f IN SELECT p.oid, p.proname, p.proretset,
                    (SELECT string_agg(format('NULL::%s', format_type(a, NULL)), ', ' ORDER BY o) FROM unnest(p.proargtypes) WITH ORDINALITY AS x(a, o)) AS args
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public' AND p.prokind = 'f' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
               AND p.proname NOT IN ('f360_ai_log', 'f360_ai_reserve') ORDER BY p.proname LOOP
      call := format('SELECT left((%s)::text, 300)', format('public.%I(%s)', f.proname, coalesce(f.args, '')));
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', w.uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
        SET LOCAL statement_timeout = '3s';
        SET LOCAL ROLE authenticated;
        EXECUTE call INTO res;
        RESET ROLE; SET LOCAL statement_timeout = 0;
        oc := CASE WHEN res LIKE '%"error": "No disponible."%' THEN 'denegado' ELSE 'respondio' END;
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = '__undo__' || oc;   -- undo anything the call did, keep the outcome
      EXCEPTION WHEN others THEN
        RESET ROLE; SET LOCAL statement_timeout = 0;
        oc := CASE WHEN SQLERRM LIKE '__undo__%' THEN substr(SQLERRM, 9)
                        WHEN SQLSTATE = '42501' THEN 'denegado'
                        WHEN SQLERRM ILIKE '%no tiene acceso%' OR SQLERRM ILIKE '%no tiene permiso%' OR SQLERRM ILIKE '%permission denied%' THEN 'denegado'
                        ELSE 'error:' || SQLSTATE END;
      END;
      INSERT INTO _fa_result VALUES (w.name, 'fn', f.proname, oc);
    END LOOP;
    FOR t IN SELECT c.oid::regclass::text AS rel FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname IN ('f360', 'f360_board', 'public') AND c.relkind IN ('r', 'v', 'm') AND has_table_privilege('authenticated', c.oid, 'SELECT') LOOP
      BEGIN
        PERFORM set_config('request.jwt.claims', json_build_object('sub', w.uid, 'role', 'authenticated', 'aal', 'aal2')::text, true);
        SET LOCAL ROLE authenticated;
        EXECUTE format('SELECT count(*) FROM %s', t.rel) INTO n;
        RESET ROLE;
        oc := CASE WHEN n > 0 THEN 've_' || n || '_filas' ELSE '0_filas' END;
      EXCEPTION WHEN others THEN RESET ROLE; oc := 'denegado'; END;
      INSERT INTO _fa_result VALUES (w.name, 'tabla', t.rel, oc);
    END LOOP;
  END LOOP;

  -- the invariant: what the contadora passes beyond a role-less person must be exactly the finance-capture list
  SELECT string_agg(c.obj, ', ' ORDER BY c.obj) INTO bad FROM _fa_result c JOIN _fa_result s ON s.who = 'sin_rol' AND s.kind = c.kind AND s.obj = c.obj
   WHERE c.who = 'contadora' AND c.kind = 'fn' AND c.outcome <> 'denegado' AND s.outcome = 'denegado' AND c.obj <> ALL (allowed);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'C3 la contadora alcanza más que una persona sin rol: %', bad; END IF;
  SELECT string_agg(c.obj, ', ') INTO bad FROM _fa_result c JOIN _fa_result s ON s.who = 'sin_rol' AND s.kind = 'tabla' AND s.obj = c.obj
   WHERE c.who = 'contadora' AND c.kind = 'tabla' AND c.outcome <> s.outcome;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'C3 la contadora lee tablas distinto que una persona sin rol: %', bad; END IF;
  IF (SELECT count(*) FROM _fa_result WHERE who = 'contadora' AND kind = 'fn' AND obj = ANY (allowed) AND outcome <> 'denegado') < 5 THEN
    RAISE EXCEPTION 'C3 la contadora no pasa sus propias funciones: %', (SELECT string_agg(obj || '=' || outcome, ', ') FROM _fa_result WHERE who = 'contadora' AND obj = ANY (allowed));
  END IF;
  RAISE NOTICE 'C3 funciones probadas: % · contadora pasa: % (permitidas: %) · sin rol pasa: % · viewer pasa: %',
    (SELECT count(*) FROM _fa_result WHERE who = 'contadora' AND kind = 'fn'),
    (SELECT count(*) FROM _fa_result WHERE who = 'contadora' AND kind = 'fn' AND outcome <> 'denegado'),
    (SELECT string_agg(obj, ', ' ORDER BY obj) FROM _fa_result WHERE who = 'contadora' AND kind = 'fn' AND outcome <> 'denegado' AND obj = ANY (allowed)),
    (SELECT count(*) FROM _fa_result WHERE who = 'sin_rol' AND kind = 'fn' AND outcome <> 'denegado'),
    (SELECT count(*) FROM _fa_result WHERE who = 'viewer' AND kind = 'fn' AND outcome <> 'denegado');
  RAISE NOTICE 'C3 tablas legibles por authenticated: % · contadora ve filas en: %', (SELECT count(*) FROM _fa_result WHERE who = 'contadora' AND kind = 'tabla'),
    coalesce((SELECT string_agg(obj || ' (' || outcome || ')', ', ') FROM _fa_result WHERE who = 'contadora' AND kind = 'tabla' AND outcome LIKE 've_%'), 'ninguna');

  -- C4 the board / strategy / PII / analyst / budget-approval paths stay closed for her (explicit, by name)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_board_plans())->>'ok' <> 'false' OR (public.f360_intel_query('ventas', '{}'))->>'ok' <> 'false' OR (public.f360_intel_cockpit())->>'ok' <> 'false'
     OR (public.f360_ai_history())->>'ok' <> 'false' OR (public.f360_board_budgets(2026))->>'ok' <> 'false' OR (public.f360_board_close_entries_approve(NULL))->>'ok' <> 'false' THEN
    RAISE EXCEPTION 'C4 strategy/analyst/budget open';
  END IF;
  BEGIN PERFORM public.f360_me(); RAISE EXCEPTION 'C4 f360_me'; EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN IF SQLERRM LIKE 'C4%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.f360_rec_list(); RAISE EXCEPTION 'C4 pii'; EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN IF SQLERRM LIKE 'C4%' THEN RAISE; END IF; END;
  -- a role granted to her later by mistake: finance capture stops at once (she does not keep both)
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (conta, 'viewer', 'error de alta');
  IF (public.f360_close_prep_context())->>'ok' <> 'false' OR NOT (public.f360_finance_access_state()->>'conflicto')::boolean THEN RAISE EXCEPTION 'C4 role later'; END IF;
  RAISE NOTICE 'ENSAYO CONTADORA OK';
END $$;
SELECT who, outcome, count(*) FROM _fa_result WHERE kind = 'fn' GROUP BY 1, 2 ORDER BY 1, 2;
ROLLBACK;
