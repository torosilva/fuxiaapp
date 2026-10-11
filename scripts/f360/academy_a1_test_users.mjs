// Fuxia Academy A1 — STAGING test learners. Run (only with Mario's approval of this exact command):
//   scripts/s00a/run.sh ../f360/academy_a1_test_users.mjs
// Creates (or reuses) two auth accounts that are NOT real people: alumna.prueba1@staging.invalid and alumna.prueba2@staging.invalid.
// Passwords live ONLY in ~/.fuxia-staging.env (mode 600). Then loads supabase/staging/academy_a1_staging.sql (grants + approver
// operations + the two test sellers). lib.mjs aborts on any production ref. Touches nothing else.
import { readFileSync, writeFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { homedir } from 'node:os';
import { loadEnv, client, psql } from '../s00a/lib.mjs';

const env = loadEnv();                       // aborts on any production ref
const c = client(env);
const ENV_FILE = `${homedir()}/.fuxia-staging.env`;
const TEST = [
  { email: 'alumna.prueba1@staging.invalid', var: 'STAGING_ACADEMY_ALUMNA1_PASSWORD', name: 'Alumna Prueba 1' },
  { email: 'alumna.prueba2@staging.invalid', var: 'STAGING_ACADEMY_ALUMNA2_PASSWORD', name: 'Alumna Prueba 2' },
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
for (const t of TEST) {
  const password = ensurePassword(t.var);
  const r = existing.has(t.email)
    ? await c.admin.update(existing.get(t.email), { password, email_confirm: true })
    : await c.admin.create({ email: t.email, password, email_confirm: true, user_metadata: { display_name: t.name } });
  if (!r.ok) throw new Error(`${t.email}: ${r.status}`);
}
psql(readFileSync('supabase/staging/academy_a1_staging.sql', 'utf8'));
console.log(JSON.stringify({ test_learners: TEST.map((t) => t.email) }));
