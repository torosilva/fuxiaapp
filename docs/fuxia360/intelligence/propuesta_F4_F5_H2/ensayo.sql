SET statement_timeout = 0; SET lock_timeout = '20s';
BEGIN;
-- evidence 1: privileges of EVERY existing relation and function before the migration
CREATE TEMP TABLE _racl0 ON COMMIT DROP AS
  SELECT 'rel:' || c.oid::regclass::text AS obj, coalesce(c.relacl::text, '') AS acl FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('f360','f360_board','public') AND c.relkind IN ('r','v','m')
  UNION ALL SELECT 'fn:' || p.oid::regprocedure::text, coalesce(p.proacl::text, '') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('f360','f360_board','public');
CREATE TEMP TABLE _rdef0 ON COMMIT DROP AS SELECT p.oid::regprocedure::text AS fn, md5(pg_get_functiondef(p.oid)) AS h FROM pg_proc p
  WHERE p.oid IN ('f360.intel_inventory_core(int)'::regprocedure, 'f360.intel_marketing_core(date,date)'::regprocedure, 'public.f360_intel_query(text,jsonb)'::regprocedure, 'public.f360_ai_log(jsonb)'::regprocedure);
CREATE TEMP TABLE _rw0 ON COMMIT DROP AS SELECT relid, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_xact_user_tables;
\echo '== migración'
\i supabase/migrations/20261024000500_f360_intel_f4_f5_h2.sql
\echo '== evidencia: filas de negocio modificadas por la migración (debe ser 0)'
SELECT count(*) AS tablas_con_filas_cambiadas FROM pg_stat_xact_user_tables s LEFT JOIN _rw0 b USING (relid)
  WHERE s.schemaname NOT LIKE 'pg_temp%' AND (s.n_tup_ins - coalesce(b.n_tup_ins,0) + s.n_tup_upd - coalesce(b.n_tup_upd,0) + s.n_tup_del - coalesce(b.n_tup_del,0)) > 0;
\echo '== evidencia: permisos de objetos EXISTENTES cambiados (debe ser 0)'
SELECT count(*) AS permisos_cambiados FROM _racl0 a JOIN (
  SELECT 'rel:' || c.oid::regclass::text AS obj, coalesce(c.relacl::text, '') AS acl FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('f360','f360_board','public') AND c.relkind IN ('r','v','m')
  UNION ALL SELECT 'fn:' || p.oid::regprocedure::text, coalesce(p.proacl::text, '') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('f360','f360_board','public')) b USING (obj)
  WHERE a.acl <> b.acl;
\echo '== pruebas nuevas F4/F5/H2'
\i supabase/staging/test_intel_f4_f5_h2.sql
\echo '== regresión: métricas M1–M15'
\i $TMPDIR_TESTS/t_intel_metrics.sql
\echo '== regresión: analista A1–A8'
\i $TMPDIR_TESTS/t_ai_analyst.sql
\echo '== regresión: entradas N1–N6'
\i $TMPDIR_TESTS/t_intel_inputs.sql
\echo '== regresión: tipo de cambio X1–X8'
\i $TMPDIR_TESTS/t_fx_daily.sql
\echo '== rollback y verificación de que las 4 funciones vuelven EXACTAS'
\i supabase/rollbacks/20261024000500_f360_intel_f4_f5_h2.down.sql
SELECT count(*) FILTER (WHERE md5(pg_get_functiondef(d.fn::regprocedure)) = d.h) AS funciones_restauradas_exactas, count(*) AS de,
  to_regclass('f360.ai_inflight') IS NULL AS tabla_nueva_eliminada FROM _rdef0 d;
ROLLBACK;
