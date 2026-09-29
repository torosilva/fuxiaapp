// STAGING ONLY — S0.0A-A2 full rehearsal: BEFORE → apply → AFTER → regressions → rollback → exact-restore check →
// re-apply (only if everything was clean). Write probes run inside BEGIN…ROLLBACK (no sale/stock is created).
// Run: scripts/s00a/run.sh ../f360/a2_rehearsal.mjs      Output: docs/fuxia360/audit/s00a_results/a2_rehearsal.json
import { readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const A2 = 'supabase/pending/s00a/20260925000200_s00a_a2_remove_anon_operational_access.sql';
const DOWN = 'supabase/rollbacks/20260925000200_s00a_a2_remove_anon_operational_access.down.sql';
const TABLES = ['staff', 'channel_inventory', 'offline_sales', 'channels', 'inventory_change_requests', 'support_tickets'];
const INV_ROW = '00000000-0000-4000-a000-000000000503';          // lab "STAGING Ballerina Test"
const CH_X = '00000000-0000-4000-a000-000000000301';
const log = [];
const say = (m) => { console.log(m); log.push(m); };

function snapshot() {
  const t = TABLES.map((x) => `'${x}'`).join(',');
  return JSON.parse(psql(`select json_build_object(
    'policies', (select json_agg(json_build_object('t', tablename, 'name', policyname, 'permissive', permissive, 'roles', roles, 'cmd', cmd, 'qual', qual, 'check', with_check) order by tablename, policyname)
                 from pg_policies where schemaname = 'public' and tablename in (${t})),
    'anon_grants', (select coalesce(json_agg(table_name || ':' || privilege_type order by table_name, privilege_type), '[]') from information_schema.role_table_grants
                    where grantee = 'anon' and table_schema = 'public' and table_name in (${t})))::text;`, {}, { readOnly: true }));
}

// run SQL as a given role/claims inside a transaction that is ALWAYS rolled back; returns {ok, out|error}
function asRole(role, sub, sql) {
  const claims = JSON.stringify(sub ? { sub, role } : { role });
  try {
    const out = psql(`BEGIN;\nselect set_config('request.jwt.claims', '${claims}', true);\nSET LOCAL ROLE ${role};\n${sql}\nROLLBACK;`);
    return { ok: true, out: out.split('\n').filter(Boolean).pop() };
  } catch (e) { return { ok: false, error: (e.message.match(/ERROR:\s+([^\n]+)/) ?? [])[1] ?? e.message.slice(0, 120) }; }
}

async function probe(label) {
  const s1 = await c.signIn(`${PHONES.S1.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.S1));
  const c2 = await c.signIn(`${PHONES.C2.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.C2));
  const rows = async (path, token) => { const r = await c.rest('GET', path, { token }); return r.ok ? (r.json?.length ?? 0) : `HTTP ${r.status}`; };
  const res = {
    anon_read_staff: await rows('staff?select=id&limit=5'),
    anon_read_inventory: await rows('channel_inventory?select=id&limit=5'),
    anon_read_sales: await rows('offline_sales?select=id&limit=5'),
    anon_read_channels: await rows('channels?select=id&limit=5'),
    anon_update_inventory: asRole('anon', null, `with u as (update public.channel_inventory set price = price where id = '${INV_ROW}' returning 1) select count(*) from u;`),
    anon_insert_sale: asRole('anon', null, `insert into public.offline_sales (code, channel_id, items, total) values ('ZZREH1', '${CH_X}', '[]', 1); select 'inserted';`),
    customer_read_icr: await rows('inventory_change_requests?select=id&limit=5', c2.token),
    customer_insert_icr_with_staff_id: asRole('authenticated', c2.uid, `insert into public.inventory_change_requests (channel_id, action, payload, requested_by_staff_id, requested_by_name, status)
       select '${CH_X}', 'adjust_stock', '{}'::jsonb, id, 'ensayo A2', 'pending' from public.staff where active limit 1; select 'inserted';`),
    staff_read_inventory: await rows('channel_inventory?select=id&limit=5', s1.token),
    staff_update_sold: asRole('authenticated', s1.uid, `with u as (update public.channel_inventory set sold = sold where id = '${INV_ROW}' returning 1) select count(*) from u;`),
    staff_insert_sale: asRole('authenticated', s1.uid, `insert into public.offline_sales (code, channel_id, items, total) values ('ZZREH2', '${CH_X}', '[]', 1); select 'inserted';`),
    staff_read_icr: await rows('inventory_change_requests?select=id&limit=5', s1.token),
    staff_insert_icr: asRole('authenticated', s1.uid, `insert into public.inventory_change_requests (channel_id, action, payload, requested_by_name, status) values ('${CH_X}', 'adjust_stock', '{}'::jsonb, 'ensayo A2', 'pending'); select 'inserted';`),
  };
  say(`\n── ${label}`);
  for (const [k, v] of Object.entries(res)) say(`  ${k.padEnd(36)} ${typeof v === 'object' ? (v.ok ? `OK → ${v.out}` : `DENIED (${v.error})`) : v}`);
  return res;
}

const run = (cmd, args) => { try { return { ok: true, out: execFileSync(cmd, args, { encoding: 'utf8', env: process.env, stdio: ['ignore', 'pipe', 'pipe'] }) }; } catch (e) { return { ok: false, out: (e.stdout ?? '') + (e.stderr ?? '') }; } };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const report = { at: new Date().toISOString() };
report.before = snapshot();
say(`BEFORE: ${report.before.policies.length} policies on the 6 tables; anon policies = ${report.before.policies.filter((p) => p.roles.includes('anon')).length}; anon grants = ${report.before.anon_grants.length}`);
report.before_probe = await probe('BEFORE A2');

say('\n>>> applying A2 (staging)');
psql(readFileSync(A2, 'utf8'));
report.after = snapshot();
const anonAfter = report.after.policies.filter((p) => p.roles.includes('anon')).length;
say(`AFTER: anon policies = ${anonAfter}; anon grants = ${report.after.anon_grants.length}; ICR policies = ${report.after.policies.filter((p) => p.t === 'inventory_change_requests').map((p) => p.name).join(', ')}`);
report.after_probe = await probe('AFTER A2');

const ap = report.after_probe;
const closed = [ap.anon_read_staff, ap.anon_read_inventory, ap.anon_read_sales, ap.anon_read_channels].every((v) => v === 0 || String(v).startsWith('HTTP'))
  && !ap.anon_update_inventory.ok && !ap.anon_insert_sale.ok && (ap.customer_read_icr === 0 || String(ap.customer_read_icr).startsWith('HTTP')) && !ap.customer_insert_icr_with_staff_id.ok;
const staffOk = typeof ap.staff_read_inventory === 'number' && ap.staff_read_inventory > 0 && ap.staff_update_sold.ok && ap.staff_update_sold.out === '1'
  && ap.staff_insert_sale.ok && ap.staff_insert_icr.ok && typeof ap.staff_read_icr === 'number';
say(`\nanonymous fully closed: ${closed ? 'YES' : 'NO'} · logged-in legacy staff path still works: ${staffOk ? 'YES' : 'NO'}`);

say('\n>>> regressions (AFTER A2): S0.2 seller flow + all DB suites');
const flow = run('node', ['scripts/f360/s02_seller_flow.mjs']);
const dbs = run('node', ['scripts/f360/db_tests.mjs']);
report.regressions = { s02_flow: flow.ok, db_tests: dbs.ok, flow_tail: flow.out.split('\n').slice(-3).join(' | '), db_tail: dbs.out.split('\n').filter((l) => /^==|FAIL|ALL PASS/.test(l)).join(' | ') };
say(`  S0.2 seller flow: ${flow.ok ? 'PASS' : 'FAIL'} · DB suites: ${dbs.ok ? 'ALL PASS' : 'FAIL'}\n  ${report.regressions.db_tail}`);

say('\n>>> rollback A2 (staging)');
psql(readFileSync(DOWN, 'utf8'));
report.after_rollback = snapshot();
const restored = same(report.after_rollback, report.before);
say(`rollback restores the exact BEFORE policies + grants: ${restored ? 'YES (identical)' : 'NO — DIFFERENCE'}`);
if (!restored) say(JSON.stringify({ before: report.before, after_rollback: report.after_rollback }).slice(0, 2000));
report.rollback_probe = await probe('AFTER ROLLBACK');

const clean = closed && staffOk && flow.ok && dbs.ok && restored;
report.clean = clean;
if (clean) {
  say('\n>>> rehearsal clean → re-applying A2 on staging');
  psql(readFileSync(A2, 'utf8'));
  report.final = snapshot();
  report.final_equals_after = same(report.final, report.after);
  say(`final state = first AFTER state: ${report.final_equals_after ? 'YES' : 'NO'}`);
  report.final_probe = await probe('FINAL (A2 re-applied)');
} else {
  say('\n>>> rehearsal NOT clean → A2 left rolled back on staging');
}
writeFileSync('docs/fuxia360/audit/s00a_results/a2_rehearsal.json', JSON.stringify({ ...report, log }, null, 2));
say('\nsaved docs/fuxia360/audit/s00a_results/a2_rehearsal.json');
process.exit(clean ? 0 : 1);
