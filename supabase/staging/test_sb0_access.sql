-- Strategy & Board SB0 — ACCESS tests (STAGING). NEVER commits: ends with RAISE 'ENSAYO OK' (success = that message).
-- Run inside a transaction AFTER 20261015000100..0400 + supabase/staging/sb0_board_members_staging.sql (rehearsal: prepend them).
-- Identities are simulated with request.jwt.claims + SET LOCAL ROLE (exactly what PostgREST does with a verified JWT).
-- Since 20261016000100 the Board requires MFA: pg_temp.as() defaults to aal = 'aal2' (aal1 is tested explicitly).
-- Fixtures: Carolina / Mario = board_members by person_key (real staging auth ids); Adrián-like owner NOT on the allowlist
-- (staging owner not in board_members, or a synthetic one); synthetic seller / operator / viewer / no-role users; all rolled back.
-- Covers: 0 privileges & RPC conventions · 1 unauthorized · 2 seller · 3 generic owner · 4 Carolina · 5 Mario · 5b scope/
-- inactive/lost-owner/MFA · 6 denied logged · 7 sensitive writes logged · PII scan · 19 seller vs aggregate intent RPCs.
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated', p_aal text DEFAULT 'aal2') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role, 'aal', p_aal)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
-- every key anywhere in a jsonb document
CREATE FUNCTION pg_temp.keys(j jsonb) RETURNS SETOF text LANGUAGE sql AS $$
  WITH RECURSIVE t(v) AS (SELECT j UNION ALL
    SELECT e.value FROM t, LATERAL (SELECT value FROM jsonb_each(CASE WHEN jsonb_typeof(t.v) = 'object' THEN t.v ELSE '{}' END)
                                    UNION ALL SELECT value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(t.v) = 'array' THEN t.v ELSE '[]' END)) e)
  SELECT k FROM t, LATERAL jsonb_object_keys(CASE WHEN jsonb_typeof(t.v) = 'object' THEN t.v ELSE '{}' END) k
$$;
CREATE FUNCTION pg_temp.new_user(p_role text, p_name text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE u uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sb0-' || u || '@test.invalid', '', now(), now(), now());
  IF p_role IS NOT NULL THEN INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (u, p_role, p_name, 'test_sb0'); END IF;
  RETURN u;
END $$;

DO $$
DECLARE car uuid; mar uuid; adr uuid; seller uuid; oper uuid; viewer uuid; norole uuid; partial uuid; st uuid; per uuid;
  r jsonb; q text; calls text[]; reads text[]; n int; t0 timestamptz := clock_timestamp(); k text; uid uuid; who text;
BEGIN
  SELECT auth_user_id INTO car FROM f360_board.board_members WHERE person_key = 'CAROLINA';
  SELECT auth_user_id INTO mar FROM f360_board.board_members WHERE person_key = 'MARIO';
  IF car IS NULL OR mar IS NULL THEN RAISE EXCEPTION 'fixture: Carolina/Mario board members missing (run sb0_board_members_staging.sql)'; END IF;
  SELECT r.auth_user_id INTO adr FROM f360.user_roles r WHERE r.role = 'owner'
    AND NOT EXISTS (SELECT 1 FROM f360_board.board_members b WHERE b.auth_user_id = r.auth_user_id) LIMIT 1;
  IF adr IS NULL THEN adr := pg_temp.new_user('owner', 'Owner técnico (test)'); END IF;
  seller := pg_temp.new_user('seller', 'Vendedora SB0'); oper := pg_temp.new_user('operator', 'Operación SB0');
  viewer := pg_temp.new_user('viewer', 'Consulta SB0');   norole := pg_temp.new_user(NULL, NULL);
  SELECT id INTO st FROM f360.locations WHERE status = 'active' AND sellable ORDER BY name LIMIT 1;
  IF st IS NOT NULL THEN INSERT INTO f360.location_assignments (auth_user_id, location_id, active, granted_by_name) VALUES (seller, st, true, 'test_sb0') ON CONFLICT DO NOTHING; END IF;
  SELECT id INTO per FROM f360_board.fiscal_periods WHERE entity_key = 'fuxia' AND kind = 'MONTH' AND fiscal_year = 2026 AND period_no = 9;

  reads := ARRAY['SELECT public.f360_board_me()', 'SELECT public.f360_board_access_log(7)', 'SELECT public.f360_board_periods(2026)',
                 format('SELECT public.f360_board_close_get(%L)', per), 'SELECT public.f360_board_metric_catalog()',
                 'SELECT public.f360_board_decisions(10)', 'SELECT public.f360_board_plans()'];
  calls := reads || ARRAY[
    format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_rent'', 100, ''MXN'', ''prueba de acceso'')', per),
    format('SELECT public.f360_board_close_entry_void(gen_random_uuid(), ''motivo de prueba'')'),
    format('SELECT public.f360_board_close_entries_approve(%L)', per),
    format('SELECT public.f360_board_period_transition(%L, ''UNDER_REVIEW'')', per),
    'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Decisión intrusa'', ''no debe existir'')',
    'SELECT public.f360_board_decision_revise(gen_random_uuid(), ''x'', ''y'')',
    'SELECT public.f360_board_decision_act(gen_random_uuid(), ''APPROVE'')'];

  -- ── 0 · privileges and conventions ─────────────────────────────────────────
  IF has_schema_privilege('authenticated', 'f360_board', 'USAGE') OR has_schema_privilege('anon', 'f360_board', 'USAGE')
     OR has_schema_privilege('service_role', 'f360_board', 'USAGE') THEN RAISE EXCEPTION 'FAIL T0 schema usage granted'; END IF;
  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace, unnest(ARRAY['anon', 'authenticated', 'service_role']) ro,
    unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']) pr
    WHERE s.nspname = 'f360_board' AND c.relkind = 'r' AND has_table_privilege(ro, c.oid, pr);
  IF n > 0 THEN RAISE EXCEPTION 'FAIL T0 % table privileges granted', n; END IF;
  SELECT count(*) INTO n FROM pg_class c JOIN pg_namespace s ON s.oid = c.relnamespace WHERE s.nspname = 'f360_board' AND c.relkind = 'r' AND NOT c.relrowsecurity;
  IF n > 0 THEN RAISE EXCEPTION 'FAIL T0 % tables without RLS', n; END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'f360_board';
  IF n > 0 THEN RAISE EXCEPTION 'FAIL T0 RLS policies exist (must be deny-all)'; END IF;
  FOR k, r IN SELECT p.oid::regprocedure::text, jsonb_build_object('definer', p.prosecdef, 'cfg', p.proconfig,
        'anon', has_function_privilege('anon', p.oid, 'EXECUTE'), 'auth', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
        'gate_first', p.proname IN ('f360_board_nav_visible', 'f360_board_access_state') OR   -- caller-only hints (20261016000100), no data
                      (position('f360_board.require_board_member(' IN p.prosrc) > 0
                      AND position('f360_board.require_board_member(' IN p.prosrc) < position('BEGIN' IN p.prosrc)))
      FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace WHERE s.nspname = 'public' AND p.proname LIKE 'f360\_board\_%' LOOP
    IF NOT (r->>'definer')::boolean OR NOT (r->'cfg') @> '["search_path=pg_catalog, pg_temp"]' OR (r->>'anon')::boolean OR NOT (r->>'auth')::boolean
       OR NOT (r->>'gate_first')::boolean THEN RAISE EXCEPTION 'FAIL T0 RPC convention % %', k, r; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace WHERE s.nspname = 'public' AND p.proname LIKE 'f360\_board\_%';
  RAISE NOTICE 'PASS T0 privileges: no schema/table grants, RLS on with no policies, % public RPCs definer+search_path+gate-first, anon cannot execute', n;

  -- ── 1 · unauthorized (anon, signed-in without role) ────────────────────────
  r := pg_temp.as(NULL, 'SELECT public.f360_board_me()', 'anon');
  IF r->>'sqlstate' <> '42501' THEN RAISE EXCEPTION 'FAIL T1 anon executed f360_board_me: %', r; END IF;
  r := pg_temp.as(NULL, 'SELECT to_jsonb(count(*)) FROM f360_board.board_members', 'anon');
  IF r->>'sqlstate' <> '42501' THEN RAISE EXCEPTION 'FAIL T1 anon read table: %', r; END IF;
  FOREACH q IN ARRAY calls LOOP
    r := pg_temp.as(norole, q);
    IF r IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T1 no-role user: % → %', q, r; END IF;
  END LOOP;
  r := pg_temp.as(norole, 'SELECT to_jsonb(count(*)) FROM f360_board.access_log');
  IF r->>'error' NOT LIKE 'permission denied for schema%' THEN RAISE EXCEPTION 'FAIL T1 direct read: %', r; END IF;
  IF (pg_temp.as(norole, 'SELECT to_jsonb(public.f360_board_nav_visible())'))::text <> 'false' THEN RAISE EXCEPTION 'FAIL T1 nav visible'; END IF;
  RAISE NOTICE 'PASS T1 unauthorized: anon cannot execute (42501); signed-in user without role gets {ok:false,"No disponible."} on all % RPCs; direct table read → permission denied for schema', cardinality(calls);

  -- ── 2 · seller (and operator, viewer) ──────────────────────────────────────
  FOREACH uid IN ARRAY ARRAY[seller, oper, viewer] LOOP
    FOREACH q IN ARRAY calls LOOP
      r := pg_temp.as(uid, q);
      IF r IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T2 % % → %', uid, q, r; END IF;
    END LOOP;
    r := pg_temp.as(uid, 'SELECT to_jsonb(count(*)) FROM f360_board.decisions');
    IF r->>'error' NOT LIKE 'permission denied for schema%' THEN RAISE EXCEPTION 'FAIL T2 direct read %', r; END IF;
  END LOOP;
  RAISE NOTICE 'PASS T2 seller cannot access Board (all % RPCs denied, direct SELECT denied); operator and viewer too', cardinality(calls);

  -- ── 3 · generic owner not on the allowlist ─────────────────────────────────
  FOREACH q IN ARRAY calls LOOP
    r := pg_temp.as(adr, q);
    IF r IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T3 owner non-member: % → %', q, r; END IF;
  END LOOP;
  IF (pg_temp.as(adr, 'SELECT to_jsonb(public.f360_board_nav_visible())'))::text <> 'false' THEN RAISE EXCEPTION 'FAIL T3 nav visible to owner'; END IF;
  IF (SELECT role FROM f360.user_roles WHERE auth_user_id = adr) <> 'owner' THEN RAISE EXCEPTION 'FAIL T3 fixture is not owner'; END IF;
  RAISE NOTICE 'PASS T3 generic owner (role owner, not on allowlist) is denied on every RPC and sees no nav';

  -- ── 4 / 5 · Carolina and Mario ─────────────────────────────────────────────
  FOREACH uid IN ARRAY ARRAY[car, mar] LOOP
    who := CASE uid WHEN car THEN 'T4 Carolina' ELSE 'T5 Mario' END;
    FOREACH q IN ARRAY reads LOOP
      r := pg_temp.as(uid, q);
      IF NOT coalesce((r->>'ok')::boolean, false) THEN RAISE EXCEPTION 'FAIL % % → %', who, q, r; END IF;
      -- PII scan: no customer personal-data keys, no e-mail/phone-like values in any Board response
      IF EXISTS (SELECT 1 FROM pg_temp.keys(r) x WHERE x IN ('phone', 'email', 'address', 'birthday', 'first_name', 'last_name', 'full_name', 'whatsapp', 'customer_name'))
         OR r::text ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}' OR r::text ~ '\+52[0-9]{10}' THEN
        RAISE EXCEPTION 'FAIL PII in % response: %', q, left(r::text, 300);
      END IF;
    END LOOP;
    IF (pg_temp.as(uid, 'SELECT to_jsonb(public.f360_board_nav_visible())'))::text <> 'true' THEN RAISE EXCEPTION 'FAIL % nav', who; END IF;
    r := pg_temp.as(uid, 'SELECT to_jsonb(count(*)) FROM f360_board.board_members');
    IF r->>'error' NOT LIKE 'permission denied for schema%' THEN RAISE EXCEPTION 'FAIL % direct table read must still be denied: %', who, r; END IF;
    RAISE NOTICE 'PASS % authorized: % read RPCs ok, nav visible, still no direct table access, no PII in responses', who, cardinality(reads);
  END LOOP;
  r := pg_temp.as(car, 'SELECT public.f360_board_me()');
  IF r->'me'->>'person_key' <> 'CAROLINA' OR jsonb_array_length(r->'members') <> 2 THEN RAISE EXCEPTION 'FAIL T4 me %', r; END IF;

  -- ── 5b · missing scope, inactive member, member who lost owner, MFA flag ───
  partial := pg_temp.new_user('owner', 'Socio parcial (test)');
  INSERT INTO f360_board.board_members (auth_user_id, display_name, scopes, granted_by_name, evidence) VALUES (partial, 'Socio parcial (test)', ARRAY['BOARD'], 'test', 'test');
  r := pg_temp.as(partial, 'SELECT public.f360_board_periods(2026)');
  IF r IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T5b missing scope %', r; END IF;
  IF NOT (pg_temp.as(partial, 'SELECT public.f360_board_decisions(5)')->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL T5b granted scope'; END IF;
  UPDATE f360.user_roles SET role = 'operator' WHERE auth_user_id = partial;
  IF pg_temp.as(partial, 'SELECT public.f360_board_decisions(5)') IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T5b lost owner still in'; END IF;
  UPDATE f360.user_roles SET role = 'owner' WHERE auth_user_id = partial;
  UPDATE f360_board.board_members SET active = false WHERE auth_user_id = partial;
  IF pg_temp.as(partial, 'SELECT public.f360_board_decisions(5)') IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T5b inactive still in'; END IF;
  UPDATE f360_board.settings SET require_aal2 = true;
  IF pg_temp.as(car, 'SELECT public.f360_board_me()', 'authenticated', 'aal1') IS DISTINCT FROM f360_board.denied() THEN RAISE EXCEPTION 'FAIL T5b aal1 passed with MFA required'; END IF;
  IF NOT (pg_temp.as(car, 'SELECT public.f360_board_me()', 'authenticated', 'aal2')->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL T5b aal2 refused'; END IF;
  -- 20261016000100: MFA stays required for the Board (Mario 2026-10-08); members are simulated at aal2 by default.
  IF (SELECT count(*) FROM f360_board.settings_changes WHERE at >= t0) <> 1 THEN RAISE EXCEPTION 'FAIL T5b settings changes not audited'; END IF;
  IF (SELECT count(*) FROM f360_board.board_member_changes WHERE auth_user_id = partial) <> 2 THEN RAISE EXCEPTION 'FAIL T5b member changes not audited'; END IF;
  RAISE NOTICE 'PASS T5b member without scope denied; member who loses owner role denied; inactive member denied; MFA flag enforces aal2; settings + membership changes audited';

  -- ── 6 · denied access logged (and kept) ────────────────────────────────────
  FOREACH uid IN ARRAY ARRAY[norole, seller, oper, viewer, adr] LOOP
    SELECT count(*) INTO n FROM f360_board.access_log WHERE auth_user_id = uid AND outcome = 'denied' AND reason = 'not_member' AND at >= t0;
    IF n < cardinality(calls) THEN RAISE EXCEPTION 'FAIL T6 % denied rows for % (expected ≥ %)', n, uid, cardinality(calls); END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = partial AND reason = 'missing_scope')
     OR NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = partial AND reason = 'not_owner')
     OR NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = partial AND reason = 'inactive')
     OR NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = car AND reason = 'mfa_required') THEN RAISE EXCEPTION 'FAIL T6 reasons'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = car AND outcome = 'allowed' AND rpc = 'f360_board_me' AND at >= t0)
     OR NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = mar AND outcome = 'allowed' AND at >= t0) THEN RAISE EXCEPTION 'FAIL T6 allowed not logged'; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.access_log WHERE at >= t0 AND rpc = 'f360_board_nav_visible') THEN RAISE EXCEPTION 'FAIL T6 nav probe logged'; END IF;
  r := pg_temp.as(car, 'SELECT public.f360_board_access_log(1)');
  IF (r->'summary'->>'denied_non_members')::int < 5 * cardinality(calls) THEN RAISE EXCEPTION 'FAIL T6 access log RPC summary %', r->'summary'; END IF;
  BEGIN UPDATE f360_board.access_log SET outcome = 'allowed' WHERE outcome = 'denied'; RAISE EXCEPTION 'FAIL T6 log editable';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360_board.access_log; RAISE EXCEPTION 'FAIL T6 log deletable';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  RAISE NOTICE 'PASS T6 every denied call logged with reason (not_member/missing_scope/not_owner/inactive/mfa_required) and kept; allowed logged; log append-only; members see the denials summary';

  -- ── 7 · sensitive writes logged ────────────────────────────────────────────
  r := pg_temp.as(car, format('SELECT public.f360_board_close_entry_add(gen_random_uuid(), %L, ''opex_tech'', 1234.50, ''MXN'', ''factura de prueba SB0'')', per));
  IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL T7 capture %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = car AND outcome = 'write' AND rpc = 'f360_board_close_entry_add' AND object_ref = r->>'id') THEN
    RAISE EXCEPTION 'FAIL T7 capture write not logged'; END IF;
  r := pg_temp.as(mar, 'SELECT public.f360_board_decision_propose(gen_random_uuid(), ''Prueba de registro'', ''Registrar la escritura'')');
  IF NOT EXISTS (SELECT 1 FROM f360_board.access_log WHERE auth_user_id = mar AND outcome = 'write' AND rpc = 'f360_board_decision_propose' AND object_ref = r->'decision'->>'id') THEN
    RAISE EXCEPTION 'FAIL T7 decision write not logged %', r; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.access_log WHERE at >= t0 AND outcome = 'write' AND auth_user_id NOT IN (car, mar)) THEN RAISE EXCEPTION 'FAIL T7 non-member write'; END IF;
  IF EXISTS (SELECT 1 FROM f360_board.monthly_close_entries WHERE source = 'prueba de acceso') OR EXISTS (SELECT 1 FROM f360_board.decisions WHERE title = 'Decisión intrusa') THEN
    RAISE EXCEPTION 'FAIL T7 a denied write landed'; END IF;
  RAISE NOTICE 'PASS T7 sensitive writes (close capture, decision) logged as write with object id; params stored only as hash; no denied write landed';

  -- ── 19 · seller cannot reach aggregate demand / product-intent RPCs (direct RPC, seller JWT) ──
  FOREACH q IN ARRAY ARRAY['SELECT public.f360_stock_demand(NULL)', 'SELECT public.f360_favorites_report(''woo_staging4'', 30)',
                           format('SELECT public.f360_review_summary(%L)', (SELECT id FROM f360.products LIMIT 1)), 'SELECT public.f360_store_order(''woo_staging4'')'] LOOP
    r := pg_temp.as(seller, q);
    IF r->>'sqlstate' IS DISTINCT FROM '42501' THEN RAISE EXCEPTION 'FAIL T19 seller reached %: %', q, left(r::text, 200); END IF;
    r := pg_temp.as(viewer, q);
    IF r->>'sqlstate' IS DISTINCT FROM '42501' THEN RAISE EXCEPTION 'FAIL T19 viewer reached %', q; END IF;
    r := pg_temp.as(oper, q);
    IF r ? 'sqlstate' AND r->>'sqlstate' = '42501' THEN RAISE EXCEPTION 'FAIL T19 operator lost access to %: %', q, r; END IF;
    r := pg_temp.as(car, q);
    IF r ? 'sqlstate' AND r->>'sqlstate' = '42501' THEN RAISE EXCEPTION 'FAIL T19 owner lost access to %', q; END IF;
  END LOOP;
  -- the seller's own daily RPCs keep working
  IF (pg_temp.as(seller, 'SELECT public.f360_me()')->>'role') <> 'seller' THEN RAISE EXCEPTION 'FAIL T19 seller f360_me'; END IF;
  IF pg_temp.as(seller, 'SELECT public.f360_list_products(NULL)') ? 'sqlstate' THEN RAISE EXCEPTION 'FAIL T19 seller catalog'; END IF;
  IF pg_temp.as(seller, 'SELECT public.f360_my_locations()') ? 'sqlstate' THEN RAISE EXCEPTION 'FAIL T19 seller locations'; END IF;
  RAISE NOTICE 'PASS T19 seller and viewer get 42501 on f360_stock_demand / f360_favorites_report / f360_review_summary / f360_store_order; operator and owner keep access; seller f360_me / products / my_locations still work';

  RAISE NOTICE 'SB0 access: all checks passed';
  RAISE EXCEPTION 'ENSAYO OK';
END $$;
