-- Fuxia 360 · Fase 1 · Usuarios y roles — permission matrix and audit. STAGING. ONE transaction, ROLLED BACK.
-- The migration is rehearsed inline (@include). Fixtures are synthetic ("zz-ua-…@staging.invalid") and exist only inside this
-- transaction. Run (only with Mario's approval):
--   scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_user_admin_tests.sql
BEGIN;
-- Migration 20261112000100 applied to staging on 2026-11-12 (26/26 before applying). To rehearse it on a database that
-- does not have it yet, put back the line:  -- @include supabase/migrations/20261112000100_f360_user_admin.sql

CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, left(p_detail, 300)) $$;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM t_ids WHERE k = p_k $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    SET LOCAL ROLE authenticated;
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.denied(r jsonb) RETURNS boolean LANGUAGE sql AS $$ SELECT r ? 'error' OR (r->>'ok') = 'false' $$;

-- ── Fixtures: two owners, an operator, a seller, a viewer, an account without role ─────────────────────────────────
DO $$
DECLARE u uuid; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['OWN1', 'OWN2', 'OPER', 'SELL', 'VIEW', 'NEW'] LOOP
    INSERT INTO auth.users (id, email, aud, role, last_sign_in_at)
    VALUES (gen_random_uuid(), 'zz-ua-' || lower(k) || '@staging.invalid', 'authenticated', 'authenticated', now()) RETURNING id INTO u;
    INSERT INTO t_ids VALUES (k, u);
  END LOOP;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
    (pg_temp.id('OWN1'), 'owner', 'ZZ Dueña 1', 'test'), (pg_temp.id('OWN2'), 'owner', 'ZZ Dueña 2', 'test'),
    (pg_temp.id('OPER'), 'operator', 'ZZ Operación', 'test'), (pg_temp.id('SELL'), 'seller', 'ZZ Vendedora', 'test'),
    (pg_temp.id('VIEW'), 'viewer', 'ZZ Lectura', 'test');
END $$;

DO $$
DECLARE r jsonb; n_before int; n_after int;
BEGIN
  -- Who can open the screen
  r := pg_temp.as(pg_temp.id('OWN1'), 'SELECT public.f360_admin_users()');
  PERFORM pg_temp.ok(r ? 'users' AND NOT r ? 'error', 'U1 Dirección abre Usuarios', coalesce(r->>'error', ''));
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OPER'), 'SELECT public.f360_admin_users()')), 'U2 Operación no abre Usuarios', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('SELL'), 'SELECT public.f360_admin_users()')), 'U3 Vendedora no abre Usuarios', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('NEW'), 'SELECT public.f360_admin_users()')), 'U4 cuenta sin rol no abre Usuarios', '');
  r := pg_temp.as(pg_temp.id('OWN1'), 'SELECT public.f360_admin_users()');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'without_role') x WHERE (x->>'auth_user_id')::uuid = pg_temp.id('NEW')),
    'U5 la cuenta sin rol aparece para agregarla', '');

  -- Reason is required
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'),
    format($q$SELECT public.f360_admin_set_profile(%L, 'agencia', 'ZZ Agencia', '')$q$, pg_temp.id('NEW')))), 'P1 sin motivo no se cambia', '');

  -- Add the new account as Agencia → viewer + growth, tareas; logged with reason
  n_before := (SELECT count(*) FROM f360.access_changes);
  r := pg_temp.as(pg_temp.id('OWN1'), format($q$SELECT public.f360_admin_set_profile(%L, 'agencia', 'ZZ Agencia', 'Alta de la agencia')$q$, pg_temp.id('NEW')));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (SELECT role FROM f360.user_roles WHERE auth_user_id = pg_temp.id('NEW')) = 'viewer',
    'P2 alta como Agencia = viewer', r::text);
  PERFORM pg_temp.ok(f360.user_modules(pg_temp.id('NEW')) = ARRAY['growth', 'tareas'], 'P3 Agencia recibe Growth y Tareas', f360.user_modules(pg_temp.id('NEW'))::text);
  n_after := (SELECT count(*) FROM f360.access_changes);
  PERFORM pg_temp.ok(n_after = n_before + 2, 'P4 queda en bitácora (rol + perfil)', format('%s → %s', n_before, n_after));
  PERFORM pg_temp.ok((SELECT after->>'reason' FROM f360.access_changes WHERE what = 'profile' AND subject = pg_temp.id('NEW')::text ORDER BY id DESC LIMIT 1) = 'Alta de la agencia',
    'P5 el motivo queda guardado', '');

  -- Marketing preset, then a single module toggle
  r := pg_temp.as(pg_temp.id('OWN1'), format($q$SELECT public.f360_admin_set_profile(%L, 'marketing', 'ZZ Agencia', 'Pasa a Marketing')$q$, pg_temp.id('NEW')));
  PERFORM pg_temp.ok(f360.user_modules(pg_temp.id('NEW')) = ARRAY['growth', 'marketing', 'skills', 'tareas'], 'P6 Marketing recibe sus 4 módulos', '');
  r := pg_temp.as(pg_temp.id('OWN1'), format($q$SELECT public.f360_admin_set_module(%L, 'skills', false, 'Sin skills por ahora')$q$, pg_temp.id('NEW')));
  PERFORM pg_temp.ok(NOT ('skills' = ANY(f360.user_modules(pg_temp.id('NEW')))), 'M1 se quita un módulo', r::text);
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'),
    format($q$SELECT public.f360_admin_set_module(%L, 'growth', true, 'No aplica')$q$, pg_temp.id('OPER')))), 'M2 módulos solo para perfiles viewer', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OPER'),
    format($q$SELECT public.f360_admin_set_module(%L, 'skills', true, 'Intento')$q$, pg_temp.id('NEW')))), 'M3 Operación no da módulos', '');

  -- Module gate in the database
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('NEW'), 'SELECT public.f360_my_access()')->>'profile') = 'marketing', 'G1 la persona ve su propio perfil', '');
  PERFORM pg_temp.ok((pg_temp.as(pg_temp.id('VIEW'), 'SELECT public.f360_my_access()')->>'profile') = 'lectura', 'G2 viewer sin módulos = Solo lectura', '');

  -- Safety rules
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'),
    format($q$SELECT public.f360_admin_set_profile(%L, 'lectura', 'ZZ Dueña 1', 'Me bajo yo misma')$q$, pg_temp.id('OWN1')))), 'S1 nadie se quita a sí misma Dirección', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'),
    format($q$SELECT public.f360_admin_remove_user(%L, 'Me doy de baja')$q$, pg_temp.id('OWN1')))), 'S2 nadie se da de baja a sí misma', '');
  r := pg_temp.as(pg_temp.id('OWN1'), format($q$SELECT public.f360_admin_remove_user(%L, 'Ya no colabora')$q$, pg_temp.id('NEW')));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = pg_temp.id('NEW'))
    AND cardinality(f360.user_modules(pg_temp.id('NEW'))) = 0, 'S3 dar de baja quita rol y módulos', r::text);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.access_changes WHERE what = 'removed' AND subject = pg_temp.id('NEW')::text),
    'S4 la baja queda en bitácora', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('NEW'), 'SELECT public.f360_my_access()')), 'S5 dada de baja ya no entra', '');

  -- Sensitive permissions are untouchable from here
  INSERT INTO f360.customer_pii_viewers (auth_user_id, granted_by, note) VALUES (pg_temp.id('OWN2'), 'test', 'fixture');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'),
    format($q$SELECT public.f360_admin_remove_user(%L, 'Prueba de candado')$q$, pg_temp.id('OWN2')))), 'K1 quien ve datos de clientas no se da de baja desde la pantalla', '');
  r := pg_temp.as(pg_temp.id('OWN1'), 'SELECT public.f360_admin_users()');
  PERFORM pg_temp.ok((SELECT (x->'sensitive'->>'pii')::boolean FROM jsonb_array_elements(r->'users') x WHERE (x->>'auth_user_id')::uuid = pg_temp.id('OWN2')),
    'K2 la pantalla muestra quién ve datos de clientas', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'), 'SELECT count(*)::text::jsonb FROM f360.customer_pii_viewers')),
    'K3 la tabla de datos de clientas sigue cerrada al navegador', '');
  PERFORM pg_temp.ok(pg_temp.denied(pg_temp.as(pg_temp.id('OWN1'), 'SELECT count(*)::text::jsonb FROM f360.user_module_access')),
    'K4 la tabla de módulos está cerrada al navegador', '');

  -- Last owner
  DELETE FROM f360.customer_pii_viewers WHERE auth_user_id = pg_temp.id('OWN2');
  PERFORM pg_temp.as(pg_temp.id('OWN1'), format($q$SELECT public.f360_admin_remove_user(%L, 'Prueba última dueña')$q$, pg_temp.id('OWN2')));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.user_roles WHERE role = 'owner' AND auth_user_id IN (pg_temp.id('OWN1'), pg_temp.id('OWN2'))) >= 1,
    'S6 siempre queda al menos una dueña', '');
END $$;

SELECT format('%s | %s | %s', status, name, coalesce(detail, '')) FROM t_results ORDER BY n;
ROLLBACK;
