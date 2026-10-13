// Fuxia Academy A1 — STAGING test window (Mario 2026-10-11). Isolated: NO `db push`, NO schema_migrations rows, nothing from other sessions.
//   apply    → preflight (read-only) · applies ONLY 20261030000100/0200/0300 in order, one transaction each · records the exact
//              versions + sha256 in f360_academy.staging_window (temporary, dropped by cleanup) · prints them
//   cleanup  → ONE transaction: removes test sellers / roles / assignments of the two test accounts, academy_* approval rows, then
//              the bodies of the two .down.sql files (schema f360_academy, registry, CHECK back to the 4 values) · then deletes the two
//              test auth accounts and their passwords from ~/.fuxia-staging.env
//   rehearse-cleanup → apply + test data + cleanup inside ONE transaction ending in ROLLBACK (proves cleanup before the real window)
// Run: scripts/s00a/run.sh ../f360/academy_a1_window.mjs <apply|cleanup|rehearse-cleanup>     (lib refuses any production target)
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';
import { homedir } from 'node:os';
import { loadEnv, client, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const mode = process.argv[2];
const FILES = ['20261030000100_f360_approval_registry', '20261030000200_f360_academy_a1', '20261030000300_f360_academy_pilot_seed'];
const TEST = ['alumna.prueba1@staging.invalid', 'alumna.prueba2@staging.invalid'];
const strip = (s) => s.replace(/^\s*BEGIN;\s*$/gm, '').replace(/^\s*COMMIT;\s*$/gm, '');
const mig = (f) => readFileSync(`supabase/migrations/${f}.sql`, 'utf8');
const sha = (s) => createHash('sha256').update(s).digest('hex');
const commit = execSync('git rev-parse --short HEAD').toString().trim();

const PREFLIGHT = `DO $$ BEGIN
  IF to_regnamespace('f360_academy') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: f360_academy ya existe en staging'; END IF;
  IF to_regclass('f360.approval_requests') IS NOT NULL THEN RAISE EXCEPTION 'ABORT: el registro de aprobaciones ya existe'; END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version LIKE '20261030%') THEN RAISE EXCEPTION 'ABORT: hay versiones 20261030* registradas'; END IF;
END $$;`;
const WINDOW = () => `CREATE TABLE f360_academy.staging_window (version text PRIMARY KEY, name text NOT NULL, sha256 text NOT NULL, branch_commit text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp(), note text NOT NULL DEFAULT 'TEMPORAL: aplicada fuera del historial oficial (sin fila en schema_migrations). La borra la limpieza manual o la copia nocturna.');
INSERT INTO f360_academy.staging_window (version, name, sha256, branch_commit) VALUES
${FILES.map((f) => `('${f.slice(0, 14)}', '${f.slice(15)}', '${sha(mig(f))}', '${commit}')`).join(',\n')};
REVOKE ALL ON f360_academy.staging_window FROM PUBLIC, anon, authenticated;`;
const CLEANUP = `DO $$ DECLARE u uuid[] := ARRAY(SELECT id FROM auth.users WHERE email IN (${TEST.map((e) => `'${e}'`).join(', ')})); BEGIN
  DELETE FROM f360.sellers WHERE phone IN ('+15550190901', '+15550190902') AND created_by_name = 'Academy A1 (staging)';
  DELETE FROM f360.location_assignments WHERE auth_user_id = ANY (u);
  DELETE FROM f360.seller_credentials WHERE auth_user_id = ANY (u);
  DELETE FROM f360.user_roles WHERE auth_user_id = ANY (u);
  DELETE FROM f360.approval_scopes WHERE scope LIKE 'academy\\_%';
END $$;
${strip(readFileSync('supabase/rollbacks/20261030000200_f360_academy_a1.down.sql', 'utf8'))}
${strip(readFileSync('supabase/rollbacks/20261030000100_f360_approval_registry.down.sql', 'utf8'))}`;

if (mode === 'apply') {
  psql(`BEGIN READ ONLY;\n${PREFLIGHT}\nROLLBACK;`);
  for (const f of FILES) { psql(`BEGIN;\n${mig(f)}\nCOMMIT;\n`); console.log(`APLICADA (temporal) ${f} sha256=${sha(mig(f)).slice(0, 12)}`); }
  psql(`BEGIN;\n${WINDOW()}\nCOMMIT;`);
  console.log(psql(`SELECT string_agg(version || ' ' || name || ' ' || left(sha256, 12) || ' @' || branch_commit, E'\\n' ORDER BY version) FROM f360_academy.staging_window`, {}, { readOnly: true }));
} else if (mode === 'rehearse-cleanup') {
  const seed = readFileSync('supabase/staging/academy_a1_staging.sql', 'utf8').replace(/^\s*(BEGIN|COMMIT);\s*$/gm, '');
  const out = psql(`BEGIN;\n${PREFLIGHT}\n${FILES.map(mig).join('\n')}\n${WINDOW()}
DO $$ DECLARE k text; u uuid; BEGIN
  FOREACH k IN ARRAY ARRAY[${TEST.map((e) => `'${e}'`).join(', ')}] LOOP
    IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = k) THEN INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), k, 'authenticated', 'authenticated'); END IF;
  END LOOP; END $$;
${seed}
SELECT 'ANTES_LIMPIEZA ' || (SELECT count(*) FROM f360_academy.grants) || ' grants, ' || (SELECT count(*) FROM f360.sellers WHERE phone LIKE '+155501909%') || ' vendedoras de prueba';
${CLEANUP}
DELETE FROM auth.users WHERE email IN (${TEST.map((e) => `'${e}'`).join(', ')});
SELECT 'DESPUES_LIMPIEZA schema=' || (to_regnamespace('f360_academy') IS NOT NULL) || ' registro=' || (to_regclass('f360.approval_requests') IS NOT NULL)
  || ' check=' || (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'approval_scopes_scope_check')
  || ' rpc=' || (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE 'f360\\_academy\\_%')
  || ' vendedoras_prueba=' || (SELECT count(*) FROM f360.sellers WHERE phone LIKE '+155501909%')
  || ' roles_prueba=' || (SELECT count(*) FROM f360.user_roles WHERE granted_by = 'Academy A1 (staging)')
  || ' academy_scopes=' || (SELECT count(*) FROM f360.approval_scopes WHERE scope LIKE 'academy\\_%');
ROLLBACK;`);
  console.log(out);
} else if (mode === 'cleanup') {
  psql(`BEGIN;\n${CLEANUP}\nCOMMIT;`);
  const c = client(env);
  const list = await c.admin.list();
  for (const u of (list.json?.users || []).filter((x) => TEST.includes(x.email))) {
    const r = await c.admin.del(u.id); console.log(`cuenta de prueba borrada: ${u.email} (${r.status})`);
  }
  const file = `${homedir()}/.fuxia-staging.env`;
  writeFileSync(file, readFileSync(file, 'utf8').split('\n').filter((l) => !/STAGING_ACADEMY_ALUMNA[12]_PASSWORD=/.test(l)).join('\n'), { mode: 0o600 });
  console.log('LIMPIEZA aplicada');
} else throw new Error('uso: academy_a1_window.mjs <apply|cleanup|rehearse-cleanup>');
