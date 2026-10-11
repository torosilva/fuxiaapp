-- ENSAYO F4b/H1b — una sola transacción que termina en ROLLBACK (no deja nada aplicado). Lo ejecuta ensayo.sh.
SET statement_timeout = 0; SET lock_timeout = '20s';
BEGIN;
-- foto ANTES: permisos, RLS, políticas, contratos y definiciones de TODAS las funciones/tablas en f360, f360_board y public
CREATE TEMP TABLE _e_acl ON COMMIT DROP AS
  SELECT 'rel:' || c.oid::regclass::text AS obj, coalesce(c.relacl::text, '') AS acl, c.relrowsecurity AS rls, c.relforcerowsecurity AS frls
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname IN ('f360','f360_board','public') AND c.relkind IN ('r','v','m');
CREATE TEMP TABLE _e_pol ON COMMIT DROP AS SELECT md5(string_agg(schemaname||tablename||policyname||coalesce(qual,'')||coalesce(with_check,'')||array_to_string(roles,','), '|' ORDER BY schemaname, tablename, policyname)) AS h FROM pg_policies;
CREATE TEMP TABLE _e_fn ON COMMIT DROP AS
  SELECT p.oid::regprocedure::text AS fn, pg_get_function_result(p.oid) AS res, p.prosecdef, p.provolatile, coalesce(p.proacl::text, '') AS acl, md5(pg_get_functiondef(p.oid)) AS def
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('f360','f360_board','public') AND p.prokind = 'f';
CREATE TEMP TABLE _e_w ON COMMIT DROP AS SELECT relid, n_tup_ins, n_tup_upd, n_tup_del FROM pg_stat_xact_user_tables;
\echo '== migración'
\i docs/fuxia360/intelligence/propuesta_F4b_H1b/20261024000600_f360_intel_f4b_h1b.sql
\echo '== evidencia (todo debe ser 0, salvo funciones_con_cuerpo_nuevo = 2)'
SELECT
  (SELECT count(*) FROM pg_stat_xact_user_tables s LEFT JOIN _e_w b USING (relid) WHERE s.schemaname NOT LIKE 'pg_temp%'
     AND (s.n_tup_ins - coalesce(b.n_tup_ins,0) + s.n_tup_upd - coalesce(b.n_tup_upd,0) + s.n_tup_del - coalesce(b.n_tup_del,0)) > 0) AS tablas_con_filas_cambiadas,
  (SELECT count(*) FROM _e_acl a JOIN pg_class c ON 'rel:' || c.oid::regclass::text = a.obj WHERE coalesce(c.relacl::text,'') <> a.acl OR c.relrowsecurity <> a.rls OR c.relforcerowsecurity <> a.frls) AS permisos_o_rls_de_tablas,
  (SELECT count(*) FROM _e_pol e WHERE e.h IS DISTINCT FROM (SELECT md5(string_agg(schemaname||tablename||policyname||coalesce(qual,'')||coalesce(with_check,'')||array_to_string(roles,','), '|' ORDER BY schemaname, tablename, policyname)) FROM pg_policies)) AS politicas_rls,
  (SELECT count(*) FROM _e_fn f JOIN pg_proc p ON p.oid::regprocedure::text = f.fn WHERE pg_get_function_result(p.oid) <> f.res OR p.prosecdef <> f.prosecdef OR p.provolatile <> f.provolatile OR coalesce(p.proacl::text,'') <> f.acl) AS contratos_o_permisos_de_funciones,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('f360','f360_board','public') AND p.prokind = 'f' AND NOT EXISTS (SELECT 1 FROM _e_fn f WHERE f.fn = p.oid::regprocedure::text)) AS funciones_nuevas,
  (SELECT string_agg(f.fn, ', ') FROM _e_fn f JOIN pg_proc p ON p.oid::regprocedure::text = f.fn WHERE md5(pg_get_functiondef(p.oid)) <> f.def) AS funciones_con_cuerpo_nuevo;
\echo '== pruebas F4b/H1b (T1–T4)'
\i docs/fuxia360/intelligence/propuesta_F4b_H1b/test_intel_f4b_h1b.sql
\echo '== regresión: F4/F5/H2 R1–R4, métricas M1–M15, analista A1–A8'
\i $TMPDIR_TESTS/t_intel_f4_f5_h2.sql
\i $TMPDIR_TESTS/t_intel_metrics.sql
\i $TMPDIR_TESTS/t_ai_analyst.sql
\echo '== rollback y verificación de que las 2 funciones vuelven EXACTAS'
\i docs/fuxia360/intelligence/propuesta_F4b_H1b/20261024000600_f360_intel_f4b_h1b.down.sql
SELECT count(*) AS funciones_restauradas_exactas, 2 AS de FROM _e_fn f JOIN pg_proc p ON p.oid::regprocedure::text = f.fn
  WHERE f.fn IN ('f360.intel_signals_core(date,date)', 'f360.ai_mask(text)') AND md5(pg_get_functiondef(p.oid)) = f.def;
ROLLBACK;
