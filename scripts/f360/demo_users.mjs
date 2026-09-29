// Fuxia 360 Admin — STAGING demo owners + Bodega CDMX.  Run: scripts/s00a/run.sh ../f360/demo_users.mjs
// Creates (or reuses) carolina.demo@staging.invalid and mario.demo@staging.invalid, stores their
// passwords ONLY in ~/.fuxia-staging.env (mode 600), grants f360 'owner', seeds Bodega CDMX.
import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { homedir } from 'node:os';
import { loadEnv, client, psql } from '../s00a/lib.mjs';

const env = loadEnv();                       // aborts on any production ref
const c = client(env);
const ENV_FILE = `${homedir()}/.fuxia-staging.env`;
const DEMO = [
  { key: 'carolina', email: 'carolina.demo@staging.invalid', var: 'STAGING_DEMO_CAROLINA_PASSWORD' },
  { key: 'mario', email: 'mario.demo@staging.invalid', var: 'STAGING_DEMO_MARIO_PASSWORD' },
];

function ensurePassword(varName) {
  if (process.env[varName]) return process.env[varName];
  const pw = `Fx360-${randomBytes(9).toString('base64url')}`;
  const lines = readFileSync(ENV_FILE, 'utf8').split('\n').filter((l) => l && !l.startsWith(`export ${varName}=`));
  lines.push(`export ${varName}='${pw}'`);
  writeFileSync(ENV_FILE, lines.join('\n') + '\n', { mode: 0o600 });
  return pw;
}

const list = await c.admin.list();
const existing = new Map((list.json?.users || []).map((u) => [u.email, u.id]));
const ids = {};
for (const d of DEMO) {
  const password = ensurePassword(d.var);
  if (existing.has(d.email)) {
    const r = await c.admin.update(existing.get(d.email), { password, email_confirm: true });
    if (!r.ok) throw new Error(`update ${d.email}: ${r.status}`);
    ids[d.key] = existing.get(d.email);
  } else {
    const r = await c.admin.create({ email: d.email, password, email_confirm: true, user_metadata: { display_name: d.key } });
    if (!r.ok) throw new Error(`create ${d.email}: ${r.status} ${r.text}`);
    ids[d.key] = r.json.id;
  }
}
psql(readFileSync('supabase/staging/f360_demo_seed.sql', 'utf8'), ids);
console.log(JSON.stringify({ demo_owners: DEMO.map((d) => d.email), locations: psql(`select string_agg(name, ', ') from f360.locations;`, {}, { readOnly: true }) }));
