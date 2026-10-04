// STAGING ONLY — post-deploy guard for the Fuxia 360 Woo functions (READ-ONLY: lists functions, reads cron responses).
// Invariant (incident 2026-10-04 17:47–17:48 UTC): f360-woo-sync, f360-woo-orders and f360-woo-publish run WITHOUT
// gateway JWT verification. Their callers are pg_cron (Bearer F360_SYNC_SECRET, not a JWT) and Woo webhooks (HMAC
// signature); the functions authenticate those themselves. A deploy without --no-verify-jwt flips verify_jwt to true and
// every cron tick answers 401 UNAUTHORIZED_INVALID_JWT_FORMAT.
// Run after EVERY deploy: scripts/s00a/run.sh ../f360/check_woo_functions.mjs   (exit 1 = broken, roll back / redeploy)
// Evidence replay:        scripts/s00a/run.sh ../f360/check_woo_functions.mjs --at=2026-10-04T17:48:30Z
import { spawnSync } from 'node:child_process';
import { loadEnv, psql, STAGING_REF } from '../s00a/lib.mjs';

loadEnv();
const EXPECT = { 'f360-woo-sync': false, 'f360-woo-orders': false, 'f360-woo-publish': false };
const problems = [];

// 1 · configuration: verify_jwt per function, as deployed
const r = spawnSync('supabase', ['functions', 'list', '--project-ref', STAGING_REF, '--output', 'json'], { encoding: 'utf8' });
if (r.status !== 0) problems.push(`no se pudo listar funciones: ${(r.stderr || '').slice(0, 200)}`);
else {
  const fns = JSON.parse(r.stdout);
  for (const [slug, want] of Object.entries(EXPECT)) {
    const f = fns.find((x) => x.slug === slug);
    if (!f) problems.push(`${slug}: no está desplegada`);
    else if (f.verify_jwt !== want) problems.push(`${slug}: verify_jwt=${f.verify_jwt} (debe ser ${want}) → redeploy con --no-verify-jwt`);
    else console.log(`OK  ${slug} v${f.version} verify_jwt=${f.verify_jwt}`);
  }
}

// 2 · smoke: the per-minute stock tick must be answering 200 (look at the last 3 minutes of pg_net responses).
// --at=<ISO UTC> replays the check over a past window (evidence / proving the guard catches a regression).
const at = (process.argv.find((a) => a.startsWith('--at=')) ?? '').slice(5);
if (at && !/^\d{4}-\d\d-\d\dT\d\d:\d\d(:\d\d)?Z$/.test(at)) throw new Error('--at debe ser ISO UTC, p. ej. 2026-10-04T17:48:30Z');
const end = at ? `'${at}'::timestamptz` : 'now()';
const rows = psql(`select status_code, coalesce(content::text, '') like '%UNAUTHORIZED%' from net._http_response
  where created > ${end} - interval '3 minutes' and created <= ${end} and (content::text like '%"push"%' or content::text like '%UNAUTHORIZED%' or content::text like '%run_id%')
  order by id desc;`, {}, { readOnly: true }).split('\n').filter(Boolean).map((l) => l.split('|'));
if (!rows.length) problems.push('sin respuestas del cron en los últimos 3 minutos (¿pg_cron / pg_net detenidos?)');
else if (rows[0][0] !== '200') problems.push(`última respuesta del cron = ${rows[0][0]}${rows[0][1] === 't' ? ' (JWT inválido: verify_jwt quedó activo)' : ''}`);
else console.log(`OK  cron: última respuesta 200 (${rows.filter((x) => x[0] === '200').length}/${rows.length} en 3 min)`);

if (problems.length) { console.log(`\nFALLA\n- ${problems.join('\n- ')}`); process.exit(1); }
console.log('\nTODO OK');
