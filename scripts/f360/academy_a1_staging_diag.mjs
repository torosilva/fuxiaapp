// Fuxia Academy A1 — READ-ONLY diagnosis of staging (before/after the rolled-back rehearsal). Writes nothing (BEGIN READ ONLY … ROLLBACK).
// Run: scripts/s00a/run.sh ../f360/academy_a1_staging_diag.mjs
import { loadEnv, psql } from '../s00a/lib.mjs';
loadEnv();
console.log(psql(`SELECT jsonb_pretty(jsonb_build_object(
  'approval_scopes_check', (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'approval_scopes_scope_check'),
  'approval_scopes_rows', (SELECT jsonb_object_agg(scope, n) FROM (SELECT scope, count(*) n FROM f360.approval_scopes GROUP BY scope) x),
  'can_approve_def_md5', (SELECT md5(pg_get_functiondef('f360.can_approve(text,uuid)'::regprocedure))),
  'registry_tables', (SELECT coalesce(jsonb_agg(tablename ORDER BY tablename), '[]') FROM pg_tables WHERE schemaname = 'f360' AND tablename LIKE 'approval\\_%'),
  'f360_academy_schema', to_regnamespace('f360_academy') IS NOT NULL,
  'academy_public_functions', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'f360\\_academy\\_%'),
  'last_migrations', (SELECT jsonb_agg(version ORDER BY version DESC) FROM (SELECT version FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 8) m),
  'has_20261023000200', EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261023000200'),
  'has_20261025000100', EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261025000100'),
  'pending_2026102600', (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version LIKE '20261026%'),
  'pilot_models', (SELECT jsonb_object_agg(c, jsonb_build_object('active', p.status = 'active', 'validated', f360.product_knowledge_public(p.id) IS NOT NULL,
      'knowledge_version', (f360.product_knowledge_public(p.id)->>'version')))
     FROM unnest(ARRAY['PAULA','BALLERINAS-BYL-PUNTUDO','MAFALDA-TACHES','LEATHER-LOAFERS','SUECO-CUCARRON']) c LEFT JOIN f360.products p ON p.code = c),
  'active_stores', (SELECT count(*) FROM f360.locations WHERE type = 'store' AND status = 'active'),
  'active_sellers_with_account', (SELECT count(*) FROM f360.sellers WHERE status = 'activa' AND auth_user_id IS NOT NULL),
  'test_phones_present', (SELECT count(*) FROM f360.sellers WHERE phone LIKE '+1555019880%' OR phone LIKE '+155501909%'),
  'zz_a1_users', (SELECT count(*) FROM auth.users WHERE email LIKE 'zz-a1-%'),
  'extensions_crypt', EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'extensions' AND p.proname = 'crypt')
))`, {}, { readOnly: true }));
