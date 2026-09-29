// S0.0A staging security lab — shared helpers.
// Credentials come ONLY from environment variables exported by ~/.fuxia-staging.env
// (run scripts via scripts/s00a/run.sh). Nothing here ever prints a credential.
import { spawnSync } from 'node:child_process';
import { createHmac } from 'node:crypto';

export const PROD_REF = 'tgzgiwfzddsghnxgkcqd';
export const STAGING_REF = 'faltxpkaicwpnlqaxrdu';
const PG_IMAGE = 'public.ecr.aws/supabase/postgres:17.6.1.104';

function jwtRef(jwt) {
  try { return JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString()).ref; } catch { return null; }
}

// ── Production guard: refuse to run unless every credential targets staging. ──
export function loadEnv() {
  const e = process.env;
  const need = ['STAGING_API_URL', 'STAGING_DB_URL', 'STAGING_ANON_JWT', 'STAGING_SERVICE_JWT', 'STAGING_OTP_SALT', 'STAGING_WC_WEBHOOK_SECRET'];
  for (const k of need) if (!e[k]) throw new Error(`missing env ${k} (run via scripts/s00a/run.sh)`);
  const all = need.map((k) => e[k]).join(' ');
  if (all.includes(PROD_REF)) throw new Error('ABORT: production project ref detected in staging environment');
  if (!e.STAGING_API_URL.includes(STAGING_REF) || !e.STAGING_DB_URL.includes(STAGING_REF)) {
    throw new Error('ABORT: target is not the approved staging project');
  }
  for (const k of ['STAGING_ANON_JWT', 'STAGING_SERVICE_JWT']) {
    const ref = jwtRef(e[k]);
    if (ref !== STAGING_REF) throw new Error(`ABORT: ${k} is not a staging key`);
  }
  return {
    api: e.STAGING_API_URL.replace(/\/+$/, ''),
    anon: e.STAGING_ANON_JWT,
    service: e.STAGING_SERVICE_JWT,
    otpSalt: e.STAGING_OTP_SALT,
    webhookSecret: e.STAGING_WC_WEBHOOK_SECRET,
  };
}

// ── Synthetic identities (NANP fictional 555-01xx; .invalid domain) ──
export const ID = (n) => `00000000-0000-4000-a000-${String(n).padStart(12, '0')}`;
export const PHONES = {
  M1: '+15550100001', C1: '+15550100011', C2: '+15550100012', C3: '+15550100013',
  S1: '+15550100021', R1: '+15550100031', DEMO: '+15550100090', E1SQUAT: '+15550100098', U1: '+15550100099',
};
export const phoneEmail = (p) => `${p.replace('+', '')}@fuxia.app`;
export const E1_EMAIL = 'e1.attacker@staging.invalid';
export const phonePassword = (env, p) => `fuxia_${p}_${env.otpSalt}`;      // same derivation as whatsapp-otp
export const e1Password = (env) => `e1_${env.otpSalt.slice(0, 24)}`;
export const isLabPhone = (p) => typeof p === 'string' && /^\+1555010\d{4}$/.test(p);
export const isLabEmail = (m) => typeof m === 'string' && (/^1555010\d{4}@fuxia\.app$/.test(m) || m.endsWith('@staging.invalid'));

// ── HTTP ──
async function http(url, { method = 'GET', headers = {}, body, raw = false } = {}) {
  const res = await fetch(url, { method, headers, body: body === undefined ? undefined : (raw ? body : JSON.stringify(body)) });
  const text = await res.text();
  let json = null; try { json = text ? JSON.parse(text) : null; } catch { /* keep text */ }
  return { status: res.status, ok: res.ok, json, text: text.slice(0, 500) };
}

export function client(env) {
  const base = (token) => ({ apikey: env.anon, Authorization: `Bearer ${token || env.anon}`, 'Content-Type': 'application/json' });
  const svc = { apikey: env.service, Authorization: `Bearer ${env.service}`, 'Content-Type': 'application/json' };
  return {
    // PostgREST as anon (token omitted) or as a user (token = access_token)
    rest: (method, path, { token, body, prefer = 'return=representation' } = {}) =>
      http(`${env.api}/rest/v1/${path}`, { method, headers: { ...base(token), Prefer: prefer }, body }),
    svcRest: (method, path, { body, prefer = 'return=representation' } = {}) =>
      http(`${env.api}/rest/v1/${path}`, { method, headers: { ...svc, Prefer: prefer }, body }),
    fn: (name, { token, body, headers = {}, raw } = {}) =>
      http(`${env.api}/functions/v1/${name}`, { method: 'POST', headers: { ...base(token), ...headers }, body, raw }),
    signIn: async (email, password) => {
      const r = await http(`${env.api}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: env.anon, 'Content-Type': 'application/json' }, body: { email, password } });
      if (!r.ok) throw new Error(`signIn failed for ${email}: ${r.status}`);
      return { token: r.json.access_token, uid: r.json.user.id, user: r.json.user };
    },
    updateUserMetadata: (token, data) =>
      http(`${env.api}/auth/v1/user`, { method: 'PUT', headers: { apikey: env.anon, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: { data } }),
    admin: {
      create: (body) => http(`${env.api}/auth/v1/admin/users`, { method: 'POST', headers: svc, body }),
      list: () => http(`${env.api}/auth/v1/admin/users?per_page=1000`, { headers: svc }),
      update: (id, body) => http(`${env.api}/auth/v1/admin/users/${id}`, { method: 'PUT', headers: svc, body }),
      del: (id) => http(`${env.api}/auth/v1/admin/users/${id}`, { method: 'DELETE', headers: svc }),
    },
    storageUpload: (token, path, bytes) =>
      http(`${env.api}/storage/v1/object/${path}`, { method: 'POST', headers: { apikey: env.anon, Authorization: `Bearer ${token}`, 'Content-Type': 'image/jpeg', 'x-upsert': 'true' }, body: bytes, raw: true }),
  };
}

export const jwtClaims = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString());
export const wcSignature = (env, body) => createHmac('sha256', env.webhookSecret).update(body).digest('base64');

// ── SQL via psql in the local Supabase Postgres image; the URL is passed as an env var, never on argv. ──
export function psql(sqlText, vars = {}, { readOnly = false } = {}) {
  const e = process.env;
  if (!e.STAGING_DB_URL.includes(STAGING_REF) || e.STAGING_DB_URL.includes(PROD_REF)) throw new Error('ABORT: psql target is not staging');
  const body = readOnly ? `BEGIN READ ONLY;\n${sqlText}\nROLLBACK;\n` : sqlText;
  const args = ['run', '--rm', '-i', '-e', 'STAGING_DB_URL', PG_IMAGE, 'sh', '-c',
    `psql "$STAGING_DB_URL" -X -q -At -v ON_ERROR_STOP=1 ${Object.entries(vars).map(([k, v]) => `-v ${k}='${String(v).replace(/'/g, '')}'`).join(' ')} -f -`];
  const r = spawnSync('docker', args, { input: body, encoding: 'utf8', env: { ...process.env } });
  const redact = (s) => (s || '').replace(/postgres(ql)?:\/\/\S+/g, '<REDACTED_DB_URL>');
  if (r.status !== 0) throw new Error(`psql failed: ${redact(r.stderr).slice(0, 800)}`);
  return redact(r.stdout).trim();
}
