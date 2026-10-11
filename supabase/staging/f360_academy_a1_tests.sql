-- Fuxia Academy A1 — access matrix, RLS/isolation, P0-6 gate, approval registry and learning flow. STAGING. ONE transaction, ROLLED BACK.
-- The three A1 migrations are rehearsed inline (@include). Fixtures are synthetic ("ZZ A1 …") and exist only inside this transaction.
-- Uses the real Ballerinas of the pilot (copied nightly from production) for the validated-knowledge snapshot.
-- Run (only with Mario's approval): scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_academy_a1_tests.sql
BEGIN;
-- @include supabase/migrations/20261026000100_f360_approval_registry.sql
-- @include supabase/migrations/20261026000200_f360_academy_a1.sql
-- @include supabase/migrations/20261026000300_f360_academy_pilot_seed.sql

CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, left(p_detail, 300)) $$;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM t_ids WHERE k = p_k $$;
-- run p_sql as an authenticated user (aal1 by default), return its jsonb or {"error": message}
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_aal text DEFAULT 'aal1') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal)::text, true);
    SET LOCAL ROLE authenticated;
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.denied(r jsonb) RETURNS boolean LANGUAGE sql AS $$ SELECT r ? 'error' OR (r->>'ok') = 'false' $$;

-- ── Fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE store uuid := (SELECT id FROM f360.locations WHERE type = 'store' AND status = 'active' ORDER BY sort, name LIMIT 1); u uuid; s uuid; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['CARO', 'MARIO', 'ALU1', 'ALU2', 'CUST', 'OPER'] LOOP
    INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-a1-' || lower(k) || '@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO u;
    INSERT INTO t_ids VALUES (k, u);
  END LOOP;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
    (pg_temp.id('CARO'), 'owner', 'ZZ A1 Carolina', 'test'), (pg_temp.id('MARIO'), 'owner', 'ZZ A1 Mario', 'test'), (pg_temp.id('OPER'), 'operator', 'ZZ A1 Operación', 'test');
  INSERT INTO f360_academy.grants (auth_user_id, role, display_name, granted_by_name, evidence) VALUES
    (pg_temp.id('CARO'), 'editor', 'ZZ A1 Carolina', 'test', 'fixture de prueba'),
    (pg_temp.id('MARIO'), 'admin', 'ZZ A1 Mario', 'test', 'fixture de prueba'), (pg_temp.id('MARIO'), 'editor', 'ZZ A1 Mario', 'test', 'fixture de prueba'),
    (pg_temp.id('ALU1'), 'tester', 'ZZ A1 Alumna 1', 'test', 'fixture de prueba');
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES
    ('academy_content', pg_temp.id('CARO'), 'ZZ A1 Carolina', 'test'), ('academy_content', pg_temp.id('MARIO'), 'ZZ A1 Mario', 'test'),
    ('academy_points', pg_temp.id('CARO'), 'ZZ A1 Carolina', 'test'), ('academy_points', pg_temp.id('MARIO'), 'ZZ A1 Mario', 'test');
  INSERT INTO f360.approval_scope_operations (scope, auth_user_id, operation, added_by_name) VALUES
    ('academy_content', pg_temp.id('CARO'), 'publish_sales', 'test'), ('academy_content', pg_temp.id('CARO'), 'publish_sales_policy', 'test'),
    ('academy_content', pg_temp.id('MARIO'), 'publish_sales_policy', 'test'),
    ('academy_points', pg_temp.id('CARO'), 'manual_adjust', 'test'), ('academy_points', pg_temp.id('MARIO'), 'manual_adjust', 'test');
  FOREACH k IN ARRAY ARRAY['ALU1', 'ALU2'] LOOP
    INSERT INTO f360.sellers (phone, name, location_id, pin_hash, status, created_by_name)
    VALUES ('+1555019' || CASE k WHEN 'ALU1' THEN '8801' ELSE '8802' END, 'ZZ A1 ' || k, store, extensions.crypt('x', extensions.gen_salt('bf', 4)), 'pendiente', 'test')
    RETURNING id INTO s;
    PERFORM f360.activate_seller(s, pg_temp.id(k), 'test', NULL);
  END LOOP;
  INSERT INTO t_ids VALUES ('V1', (SELECT v.id FROM f360_academy.course_versions v JOIN f360_academy.courses c ON c.id = v.course_id WHERE c.key = 'starter-ballerinas-parte-1' AND v.version = 1)),
    ('C1', (SELECT id FROM f360_academy.courses WHERE key = 'starter-ballerinas-parte-1'));
  INSERT INTO t_ids VALUES ('L2P', (SELECT id FROM f360_academy.lessons WHERE course_version_id = pg_temp.id('V1') AND key = '2.p'));
END $$;

-- ── 1. Gates (P0-6, no certificates / points / rewards) ──────────────────────────────────────────────────────────────────────
DO $$ DECLARE e text; BEGIN
  BEGIN UPDATE f360_academy.settings SET learner_access_enabled = true; e := NULL; EXCEPTION WHEN check_violation THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'G1 acceso real de vendedoras no se puede encender (CHECK)', coalesce(e, 'se encendió'));
  BEGIN UPDATE f360_academy.settings SET certificates_enabled = true; e := NULL; EXCEPTION WHEN check_violation THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'G2 certificados no se pueden encender', coalesce(e, 'se encendió'));
  BEGIN UPDATE f360_academy.settings SET points_enabled = true; e := NULL; EXCEPTION WHEN check_violation THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'G3 puntos no se pueden encender', coalesce(e, 'se encendió'));
  BEGIN UPDATE f360_academy.settings SET redemptions_enabled = true; e := NULL; EXCEPTION WHEN check_violation THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'G4 canjes no se pueden encender', coalesce(e, 'se encendió'));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'f360_academy' AND tablename ~ '(certif|point|reward|redemp|xp)'),
    'G5 no existen tablas de certificados, puntos, XP ni premios', 'ok');
END $$;

-- ── 2. Shared registry: existing approvals untouched ─────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  PERFORM pg_temp.ok((SELECT array_agg(m[1] ORDER BY m[1]) FROM pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') m
    WHERE c.conname = 'approval_scopes_scope_check') = ARRAY['academy_content', 'academy_points', 'academy_rewards', 'budget', 'close', 'fx_rate', 'store_discount'],
    'R1 CHECK de alcances = los 4 existentes (incl. store_discount) + 3 de Academy', 'ok');
  PERFORM pg_temp.ok(f360.can_approve('academy_content', pg_temp.id('MARIO')) AND NOT f360.can_approve_op('academy_content', 'publish_sales', pg_temp.id('MARIO')),
    'R2 permiso por operación: Mario tiene el alcance pero NO publish_sales', 'ok');
  PERFORM pg_temp.ok(pg_get_functiondef('f360.can_approve(text,uuid)'::regprocedure) LIKE '%approval_scopes WHERE scope = p_scope AND auth_user_id = p_user%',
    'R3 f360.can_approve sin cambios', 'ok');
END $$;
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('CARO'), $q$SELECT to_jsonb(count(*)) FROM f360.approval_requests$q$)), 'R4 un cliente no lee el registro de aprobaciones', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('CARO'), $q$SELECT f360.approval_decide(gen_random_uuid(), true, repeat('0', 64), auth.uid(), 'x', 'x')$q$)), 'R5 un cliente no puede llamar approval_decide', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('CARO'), $q$SELECT to_jsonb(f360.approval_request('academy_content','publish_sales','x.y',gen_random_uuid(),1,repeat('0',64),NULL,'{}','zzz',auth.uid(),'x'))$q$)), 'R6 un cliente no puede crear solicitudes directo', '');

-- ── 3. Access matrix (layer 2) ───────────────────────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.ok(pg_temp.as(pg_temp.id('CUST'), 'SELECT public.f360_academy_me()')->>'sales' = 'none', 'A1 cuenta sin rol: acceso none', '');
SELECT pg_temp.ok(pg_temp.as(pg_temp.id('OPER'), 'SELECT public.f360_academy_me()')->>'sales' = 'none', 'A2 operación (no vendedora, sin tester): none', '');
SELECT pg_temp.ok(pg_temp.as(pg_temp.id('ALU2'), 'SELECT public.f360_academy_me()')->>'sales' = 'bloqueado', 'A3 vendedora activa sin tester: BLOQUEADO (P0-6)', '');
SELECT pg_temp.ok(pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_me()')->>'sales' = 'ok', 'A4 alumna de prueba autorizada: ok', '');
SELECT pg_temp.ok((SELECT count(*) FROM f360.sellers s WHERE s.status = 'activa' AND s.auth_user_id IS NOT NULL AND s.phone NOT LIKE '+1555019880%'
                     AND f360_academy.sales_access(s.auth_user_id) <> 'bloqueado' AND NOT f360_academy.has_grant(s.auth_user_id, 'tester')) = 0,
  'A5 TODAS las vendedoras reales activas de staging quedan bloqueadas',
  (SELECT count(*)::text || ' vendedoras activas revisadas' FROM f360.sellers WHERE status = 'activa' AND auth_user_id IS NOT NULL));
DO $$ DECLARE k text; f text; BEGIN
  FOREACH k IN ARRAY ARRAY['CUST', 'ALU2', 'OPER'] LOOP
    FOREACH f IN ARRAY ARRAY['f360_academy_home()', 'f360_academy_fichas()', format('f360_academy_lesson(%L)', pg_temp.id('L2P')),
                             format('f360_academy_progress_save(%L, 1, false)', pg_temp.id('L2P'))] LOOP
      PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id(k), 'SELECT public.' || f)), 'A6 ' || k || ' no estudia: ' || split_part(f, '(', 1), '');
    END LOOP;
  END LOOP;
  FOREACH k IN ARRAY ARRAY['CUST', 'ALU1', 'ALU2', 'OPER'] LOOP
    FOREACH f IN ARRAY ARRAY['f360_academy_admin_overview()', format('f360_academy_admin_version(%L)', pg_temp.id('V1')), 'f360_academy_team()',
        format('f360_academy_submit(%L, %L)', pg_temp.id('V1'), 'x x x'), format('f360_academy_decide(%L, true, %L)', pg_temp.id('V1'), 'x x x'),
        format('f360_academy_new_draft(%L)', pg_temp.id('C1')), format('f360_academy_lesson_save(%L, %L, 3, %L, ARRAY[]::text[])', pg_temp.id('L2P'), 'xxx', '[{"type":"texto","text":"hola","source":"[X]"}]')] LOOP
      PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id(k), 'SELECT public.' || f)), 'A7 ' || k || ' sin administración: ' || split_part(f, '(', 1), '');
    END LOOP;
  END LOOP;
END $$;
-- RLS / isolation: no direct table access for any client
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU1'), $q$SELECT to_jsonb(count(*)) FROM f360_academy.items$q$)), 'I1 alumna no lee tablas (ni respuestas) directo', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('MARIO'), $q$SELECT to_jsonb(count(*)) FROM f360_academy.lesson_progress$q$)), 'I2 ni el admin lee tablas directo (solo RPC)', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU1'), $q$WITH x AS (INSERT INTO f360_academy.grants VALUES (auth.uid(),'editor','yo',true,'yo','yo yo yo',now(),NULL) RETURNING 1) SELECT to_jsonb(count(*)) FROM x$q$)),
  'I3 alumna no se autoasigna roles', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(NULL, 'SELECT public.f360_academy_me()')) OR (pg_temp.as(NULL, 'SELECT public.f360_academy_me()')->>'sales') = 'none', 'I4 sin sesión: nada', '');

-- ── 4. Content workflow + approval registry ─────────────────────────────────────────────────────────────────────────────────
SELECT pg_temp.ok((pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_home()')->'courses') = '[]'::jsonb, 'W1 un borrador no lo ve la alumna', '');
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_lesson(%L)', pg_temp.id('L2P')))), 'W2 la alumna no abre lecciones de un borrador', '');
SELECT pg_temp.ok((pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_lesson_save(%L, 'Cinco modelos para empezar', 8, '[{"type":"texto","text":"Intro","source":"[PEDAGOGÍA]"},{"type":"ficha","code":"PAULA"},{"type":"ficha","code":"BALLERINAS-BYL-PUNTUDO"},{"type":"ficha","code":"MAFALDA-TACHES"},{"type":"ficha","code":"LEATHER-LOAFERS"},{"type":"ficha","code":"SUECO-CUCARRON"}]'::jsonb, ARRAY['PAULA','BALLERINAS-BYL-PUNTUDO','MAFALDA-TACHES','LEATHER-LOAFERS','SUECO-CUCARRON'])$q$, pg_temp.id('L2P')))->>'ok')::boolean,
  'W4 el editor edita un borrador', '');
SELECT pg_temp.ok((pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_lesson_save(%L, 'x', 8, '[{"type":"texto","text":"sin fuente"}]'::jsonb, ARRAY[]::text[])$q$, pg_temp.id('L2P')))->>'ok') = 'false',
  'W5 una tarjeta sin fuente se rechaza', '');
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_submit(%L, 'Piloto A1 para revisión de Carolina')$q$, pg_temp.id('V1')));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'operation' = 'publish_sales', 'W6 enviar a revisión crea la solicitud publish_sales', r::text);
  INSERT INTO t_ids VALUES ('REQ1', (r->>'request_id')::uuid);
  PERFORM pg_temp.ok((SELECT status = 'en_revision' AND content_hash = f360_academy.version_hash(id) FROM f360_academy.course_versions WHERE id = pg_temp.id('V1')),
    'W7 versión en revisión con su huella', '');
  PERFORM pg_temp.ok((SELECT jsonb_typeof(product_snapshot->'PAULA'->'knowledge') = 'object' FROM f360_academy.lessons WHERE id = pg_temp.id('L2P')),
    'W8 la ficha validada de Paula quedó congelada en la lección', '');
END $$;
SELECT pg_temp.ok((pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_lesson_save(%L, 'x x', 8, '[{"type":"texto","text":"cambio","source":"[X]"}]'::jsonb, ARRAY[]::text[])$q$, pg_temp.id('L2P')))->>'ok') = 'false',
  'W9 no se edita una versión enviada (RPC)', '');
DO $$ DECLARE e text; BEGIN
  BEGIN UPDATE f360_academy.lessons SET title = 'hack' WHERE id = pg_temp.id('L2P'); e := NULL; EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'W10 ni siquiera directo en la base (trigger)', coalesce(e, 'se editó'));
END $$;
SELECT pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_decide(%L, true, 'ok')$q$, pg_temp.id('V1')), 'aal2')),
  'W11 Mario no puede aprobar contenido ordinario (no tiene publish_sales)', '');
SELECT pg_temp.ok(pg_temp.as(pg_temp.id('CARO'), format($q$SELECT public.f360_academy_decide(%L, true, 'ok')$q$, pg_temp.id('V1')), 'aal1')->>'error' = 'mfa_required',
  'W12 Carolina sin segundo factor: no aprueba', '');
-- tamper after submission (superuser, test only) → approval must invalidate
DO $$ DECLARE r jsonb; BEGIN
  ALTER TABLE f360_academy.lessons DISABLE TRIGGER lessons_draft_only;
  UPDATE f360_academy.lessons SET minutes = 9 WHERE id = pg_temp.id('L2P');
  ALTER TABLE f360_academy.lessons ENABLE TRIGGER lessons_draft_only;
  r := pg_temp.as(pg_temp.id('CARO'), format($q$SELECT public.f360_academy_decide(%L, true, 'ok')$q$, pg_temp.id('V1')), 'aal2');
  PERFORM pg_temp.ok((r->>'ok') = 'false' AND (SELECT status FROM f360.approval_requests WHERE id = pg_temp.id('REQ1')) = 'invalidated'
    AND (SELECT status FROM f360_academy.course_versions WHERE id = pg_temp.id('V1')) = 'borrador',
    'W13 contenido cambiado después de enviar → aprobación INVALIDADA, vuelve a borrador', r::text);
END $$;
DO $$ DECLARE r jsonb; BEGIN
  r := pg_temp.as(pg_temp.id('CARO'), format($q$SELECT public.f360_academy_submit(%L, 'Reenvío tras cambio')$q$, pg_temp.id('V1')));
  INSERT INTO t_ids VALUES ('REQ2', (r->>'request_id')::uuid);
  r := pg_temp.as(pg_temp.id('CARO'), format($q$SELECT public.f360_academy_decide(%L, true, 'Revisado')$q$, pg_temp.id('V1')), 'aal2');
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'status' = 'publicado' AND (r->>'self_approval')::boolean,
    'W14 Carolina publica su propio contenido ordinario (autoaprobación registrada)', r::text);
  PERFORM pg_temp.ok((SELECT status FROM f360.approval_requests WHERE id = pg_temp.id('REQ2')) = 'consumed'
    AND (SELECT array_agg(action ORDER BY id) FROM f360.approval_events WHERE request_id = pg_temp.id('REQ2')) = ARRAY['requested', 'approved', 'consumed']
    AND (SELECT self_approval AND aal = 'aal2' FROM f360.approval_events WHERE request_id = pg_temp.id('REQ2') AND action = 'approved'),
    'W15 historial: solicitada → aprobada (autoaprobación, aal2) → usada', '');
  PERFORM pg_temp.ok(NOT f360.approval_consume(pg_temp.id('REQ2'), 'academy_content', 'publish_sales', 'academy.course_version', pg_temp.id('V1'), 1,
    (SELECT content_hash FROM f360_academy.course_versions WHERE id = pg_temp.id('V1')), pg_temp.id('CARO'), 'x'), 'W16 una aprobación no se reutiliza', '');
END $$;
DO $$ DECLARE e text; BEGIN
  BEGIN DELETE FROM f360.approval_events WHERE request_id = pg_temp.id('REQ2'); e := NULL; EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'W17 el historial de aprobaciones no se borra', coalesce(e, 'se borró'));
  BEGIN UPDATE f360.approval_requests SET object_hash = repeat('1', 64) WHERE id = pg_temp.id('REQ2'); e := NULL; EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'W18 una solicitud no se edita', coalesce(e, 'se editó'));
  BEGIN UPDATE f360_academy.lessons SET title = 'hack' WHERE id = pg_temp.id('L2P'); e := NULL; EXCEPTION WHEN OTHERS THEN e := SQLERRM; END;
  PERFORM pg_temp.ok(e IS NOT NULL, 'W19 una versión publicada no se edita', coalesce(e, 'se editó'));
END $$;
-- sensitive operation: two people, reason required, expiry, beneficiary
DO $$ DECLARE rid uuid; r jsonb; BEGIN
  rid := f360.approval_request('academy_content', 'publish_sales_policy', 'zz.test', gen_random_uuid(), 1, repeat('a', 64), NULL, '{}', 'Prueba de política', pg_temp.id('CARO'), 'ZZ Carolina');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('CARO'), 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := f360.approval_decide(rid, true, repeat('a', 64), pg_temp.id('CARO'), 'ZZ Carolina', 'ok ok');
  PERFORM pg_temp.ok(r->>'error' = 'Esta operación la debe decidir otra persona.', 'S1 política: quien pide no aprueba', r::text);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('MARIO'), 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := f360.approval_decide(rid, true, repeat('a', 64), pg_temp.id('MARIO'), 'ZZ Mario', '');
  PERFORM pg_temp.ok(r->>'error' = 'Escribe el motivo.', 'S2 operación sensible exige motivo', r::text);
  r := f360.approval_decide(rid, true, repeat('a', 64), pg_temp.id('MARIO'), 'ZZ Mario', 'Revisado por segunda persona');
  PERFORM pg_temp.ok((r->>'ok')::boolean, 'S3 otra persona sí aprueba', r::text);
  -- expiry, evaluated with the database clock
  rid := f360.approval_request('academy_points', 'manual_adjust', 'zz.test', gen_random_uuid(), 1, repeat('b', 64), NULL, '{}', 'Prueba vencida', pg_temp.id('CARO'), 'ZZ Carolina');
  ALTER TABLE f360.approval_requests DISABLE TRIGGER approval_requests_guard;
  UPDATE f360.approval_requests SET requested_at = now() - interval '30 days', expires_at = now() - interval '1 day' WHERE id = rid;
  ALTER TABLE f360.approval_requests ENABLE TRIGGER approval_requests_guard;
  r := f360.approval_decide(rid, true, repeat('b', 64), pg_temp.id('MARIO'), 'ZZ Mario', 'tarde');
  PERFORM pg_temp.ok(r->>'ok' = 'false' AND (SELECT status FROM f360.approval_requests WHERE id = rid) = 'expired', 'S4 solicitud vencida no se aprueba (queda expired)', r::text);
  -- beneficiary
  rid := f360.approval_request('academy_points', 'manual_adjust', 'zz.test', gen_random_uuid(), 1, repeat('c', 64), pg_temp.id('MARIO'), '{}', 'Ajuste a favor de Mario', pg_temp.id('CARO'), 'ZZ Carolina');
  r := f360.approval_decide(rid, true, repeat('c', 64), pg_temp.id('MARIO'), 'ZZ Mario', 'me lo apruebo');
  PERFORM pg_temp.ok(r->>'error' = 'Nadie puede pedir ni aprobar algo a su favor.', 'S5 nadie aprueba algo a su favor', r::text);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- ── 5. Learning flow (authorized test learner) ──────────────────────────────────────────────────────────────────────────────
DO $$ DECLARE r jsonb; it jsonb; BEGIN
  r := pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_home()');
  PERFORM pg_temp.ok(jsonb_array_length(r->'courses') = 1 AND jsonb_array_length(r->'courses'->0->'lessons') = 7, 'F1 la alumna ve el curso publicado con 7 lecciones', r::text);
  r := pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_lesson(%L)', pg_temp.id('L2P')));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND jsonb_typeof(r->'lesson'->'products'->'PAULA'->'knowledge') = 'object', 'F2 abre la lección con la ficha congelada', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'practice') p WHERE p ? 'answer') AND jsonb_array_length(r->'practice') = 5,
    'F3 las preguntas llegan SIN respuesta', (r->'practice')::text);
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_progress_save(%L, 3, false)', pg_temp.id('L2P')))->>'ok' = 'true'
    AND (pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_lesson(%L)', pg_temp.id('L2P')))->'progress'->>'card_index')::int = 3,
    'F4 guarda y retoma en la tarjeta 3', '');
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_progress_save(%L, 99, false)', pg_temp.id('L2P')))->>'ok' = 'false', 'F5 tarjeta inexistente rechazada', '');
  SELECT p INTO it FROM jsonb_array_elements(r->'practice') p WHERE p->>'key' = 'B-PAULA-HP';
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('ALU1'), format($q$SELECT public.f360_academy_answer(%L, '{"choice":"a"}')$q$, it->>'id'))->>'correct')::boolean
    AND NOT (pg_temp.as(pg_temp.id('ALU1'), format($q$SELECT public.f360_academy_answer(%L, '{"choice":"c"}')$q$, it->>'id'))->>'correct')::boolean,
    'F6 calificación en el servidor (correcta / incorrecta)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360_academy.attempts WHERE auth_user_id = pg_temp.id('ALU1')) = 2, 'F7 intentos registrados (append-only)', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU1'), format($q$SELECT public.f360_academy_answer(%L, '{"choice":"a"}')$q$,
    (SELECT id FROM f360_academy.items WHERE course_version_id = pg_temp.id('V1') AND key = 'A06')))), 'F8 una pregunta solo de examen no se puede contestar en A1', '');
  r := pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_fichas()');
  PERFORM pg_temp.ok(jsonb_array_length(r->'fichas') = 5, 'F9 fichas: los 5 modelos del piloto', (SELECT string_agg(f->>'code', ', ') FROM jsonb_array_elements(r->'fichas') f));
  r := pg_temp.as(pg_temp.id('CARO'), 'SELECT public.f360_academy_team()');
  PERFORM pg_temp.ok(jsonb_array_length(r->'learners') = 1 AND (r->'learners'->0->>'store') IS NOT NULL, 'F10 Carolina ve el avance individual y la tienda', r::text);
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU2'), format('SELECT public.f360_academy_lesson(%L)', pg_temp.id('L2P')))),
    'F11 con el curso publicado, la vendedora sin tester sigue BLOQUEADA (P0-6)', '');
END $$;

-- ── 6. Separation Sales / Executive + stale product knowledge + new drafts ──────────────────────────────────────────────────
DO $$ DECLARE c uuid; v uuid; l uuid; r jsonb; BEGIN
  INSERT INTO f360_academy.courses (school, key, title, kind, created_by_name) VALUES ('executive', 'zz-ejecutiva', 'ZZ Ejecutiva', 'programa', 'test') RETURNING id INTO c;
  INSERT INTO f360_academy.course_versions (course_id, version, title, created_by_name) VALUES (c, 1, 'ZZ Ejecutiva', 'test') RETURNING id INTO v;
  INSERT INTO f360_academy.lessons (course_version_id, key, position, title, minutes, blocks) VALUES (v, '1.1', 1, 'ZZ Clase', 5, '[{"type":"texto","text":"P&L","source":"[X]"}]') RETURNING id INTO l;
  ALTER TABLE f360_academy.course_versions DISABLE TRIGGER course_versions_guard;
  UPDATE f360_academy.course_versions SET status = 'publicado' WHERE id = v;
  ALTER TABLE f360_academy.course_versions ENABLE TRIGGER course_versions_guard;
  UPDATE f360_academy.courses SET published_version_id = v WHERE id = c;
  r := pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_home()');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'courses') x WHERE x->>'key' = 'zz-ejecutiva'), 'X1 la alumna de Sales no ve cursos ejecutivos', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('ALU1'), format('SELECT public.f360_academy_lesson(%L)', l))), 'X2 ni abre una lección ejecutiva por id', '');
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('MARIO'), format($q$SELECT public.f360_academy_submit(%L, 'x x x')$q$, v))->>'ok') = 'false', 'X3 la Ejecutiva no se publica en A1', '');
  -- §9.4: Carolina re-validates Paula → the published course flags it
  UPDATE f360.product_knowledge SET version = version + 1 WHERE product_id = (SELECT id FROM f360.products WHERE code = 'PAULA');
  r := pg_temp.as(pg_temp.id('CARO'), 'SELECT public.f360_academy_admin_overview()');
  PERFORM pg_temp.ok((SELECT x->'versions'->0->'stale_products' ? 'PAULA' FROM jsonb_array_elements(r->'courses') x WHERE x->>'key' = 'starter-ballerinas-parte-1'),
    'X4 ficha re-validada → el curso publicado queda marcado para revisión', '');
  r := pg_temp.as(pg_temp.id('MARIO'), format('SELECT public.f360_academy_new_draft(%L)', pg_temp.id('C1')));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (SELECT count(*) FROM f360_academy.lessons WHERE course_version_id = (r->>'id')::uuid) = 7, 'X5 nueva versión = copia en borrador', r::text);
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('MARIO'), format('SELECT public.f360_academy_new_draft(%L)', pg_temp.id('C1')))->>'ok') = 'false', 'X6 solo un borrador a la vez', '');
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('ALU1'), 'SELECT public.f360_academy_home()')->'courses'->0->>'version')::int = 1, 'X7 la alumna sigue en su versión (no ve borradores)', '');
END $$;

SELECT format('%s | %s | %s', status, name, coalesce(detail, '')) FROM t_results ORDER BY n;
ROLLBACK;
