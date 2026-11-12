-- Fuxia 360 · Fase 2 · Fuxia Skills — access, versions and history. STAGING. ONE transaction, ROLLED BACK.
-- Run: scripts/s00a/run.sh ../f360/sql_test_one.mjs supabase/staging/f360_fuxia_skills_tests.sql
-- To rehearse on a database without the migration, put back:  -- @include supabase/migrations/20261112000200_f360_fuxia_skills.sql
BEGIN;
-- (migración 20261112000200 aplicada en staging el 2026-11-12; 16/16 antes de aplicarla)
-- @include supabase/staging/data_fuxia_skills.sql

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
CREATE FUNCTION pg_temp.err(r jsonb) RETURNS boolean LANGUAGE sql AS $$ SELECT r ? 'error' $$;

DO $$
DECLARE u uuid; k text;
BEGIN
  FOREACH k IN ARRAY ARRAY['OWN', 'OPER', 'MKT', 'VIEW', 'SELL'] LOOP
    INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-sk-' || lower(k) || '@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO u;
    INSERT INTO t_ids VALUES (k, u);
  END LOOP;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES
    (pg_temp.id('OWN'), 'owner', 'ZZ Dueña', 'test'), (pg_temp.id('OPER'), 'operator', 'ZZ Operación', 'test'),
    (pg_temp.id('MKT'), 'viewer', 'ZZ Marketing', 'test'), (pg_temp.id('VIEW'), 'viewer', 'ZZ Lectura', 'test'),
    (pg_temp.id('SELL'), 'seller', 'ZZ Vendedora', 'test');
  INSERT INTO f360.user_module_access (auth_user_id, module, granted_by_name) VALUES (pg_temp.id('MKT'), 'skills', 'test');
END $$;

DO $$
DECLARE r jsonb; v1 text;
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.skills) >= 10 AND (SELECT count(*) FROM f360.skill_versions WHERE version = 1) >= 10, 'C1 las 10 skills cargadas con su versión 1', '');
  PERFORM pg_temp.ok((SELECT status FROM f360.skills WHERE key = 'fuxia-stack-verificado') = 'actualizar', 'C2 stack verificado marcada para actualizar', '');

  r := pg_temp.as(pg_temp.id('OWN'), 'SELECT public.f360_skills()');
  PERFORM pg_temp.ok(NOT pg_temp.err(r) AND (r->>'can_edit')::boolean AND jsonb_array_length(r->'skills') >= 10, 'A1 Dirección ve la biblioteca y puede editar', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('OPER'), 'SELECT public.f360_skills()');
  PERFORM pg_temp.ok(NOT pg_temp.err(r) AND NOT (r->>'can_edit')::boolean, 'A2 Operación la ve sin editar', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('MKT'), $q$SELECT public.f360_skill('copy-pdp-calzado')$q$);
  PERFORM pg_temp.ok(NOT pg_temp.err(r) AND length(r->'shown'->>'body') > 100, 'A3 Marketing (módulo skills) lee una skill completa', coalesce(r->>'error', ''));
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('VIEW'), 'SELECT public.f360_skills()')), 'A4 Solo lectura sin módulo no la ve', '');
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('SELL'), 'SELECT public.f360_skills()')), 'A5 Vendedora no la ve', '');

  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('MKT'),
    $q$SELECT public.f360_skill_save('copy-pdp-calzado', 'x', 'contenido nuevo suficientemente largo', 'Intento de Marketing')$q$)), 'E1 Marketing no edita', '');
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('OWN'),
    $q$SELECT public.f360_skill_save('copy-pdp-calzado', 'x', 'contenido nuevo suficientemente largo', '')$q$)), 'E2 sin nota no se guarda', '');
  v1 := (SELECT body FROM f360.skill_versions WHERE skill_key = 'fuxia-stack-verificado' AND version = 1);
  r := pg_temp.as(pg_temp.id('OWN'), format($q$SELECT public.f360_skill_save('fuxia-stack-verificado', 'Stack actualizado', %L, 'México pasa a Shopify')$q$, v1 || E'\n\nMéxico: Shopify.'));
  PERFORM pg_temp.ok((r->>'version')::int = 2, 'E3 editar crea la versión 2', r::text);
  PERFORM pg_temp.ok((SELECT body FROM f360.skill_versions WHERE skill_key = 'fuxia-stack-verificado' AND version = 1) = v1, 'E4 la versión 1 queda intacta', '');
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('OWN'), format($q$SELECT public.f360_skill_save('fuxia-stack-verificado', 'Stack actualizado', %L, 'Sin cambios')$q$, v1 || E'\n\nMéxico: Shopify.'))),
    'E5 guardar sin cambios se rechaza', '');
  BEGIN
    UPDATE f360.skill_versions SET body = 'x' WHERE skill_key = 'fuxia-stack-verificado' AND version = 1;
    PERFORM pg_temp.ok(false, 'E6 las versiones no se pueden modificar', 'el UPDATE pasó');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'E6 las versiones no se pueden modificar', '');
  END;

  r := pg_temp.as(pg_temp.id('OWN'), $q$SELECT public.f360_skill_set_status('fuxia-stack-verificado', 'revisada', 'Actualizada a Shopify')$q$);
  PERFORM pg_temp.ok((r->>'ok')::boolean AND EXISTS (SELECT 1 FROM f360.skill_status_changes WHERE skill_key = 'fuxia-stack-verificado' AND after = 'revisada'),
    'S1 cambiar estado queda en historial', r::text);
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('OPER'), $q$SELECT public.f360_skill_set_status('copy-pdp-calzado', 'archivada', 'Intento')$q$)), 'S2 Operación no cambia estados', '');
  PERFORM pg_temp.ok(pg_temp.err(pg_temp.as(pg_temp.id('OWN'), 'SELECT count(*)::text::jsonb FROM f360.skill_versions')), 'S3 las tablas están cerradas al navegador', '');
END $$;

SELECT format('%s | %s | %s', status, name, coalesce(detail, '')) FROM t_results ORDER BY n;
ROLLBACK;
