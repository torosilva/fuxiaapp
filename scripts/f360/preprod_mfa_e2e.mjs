// Pre-production gate S-G0/SB0 · Board MFA end-to-end against STAGING Auth + PostgREST (real JWTs, real TOTP).
// Run: scripts/s00a/run.sh ../f360/preprod_mfa_e2e.mjs        (lib refuses any production target)
// For each staging demo owner (Carolina, Mario): sign in (aal1) → Board denied, access_state mfa_required, rest of F360 works →
// enroll a TOTP factor → wrong code refused → right code (RFC 6238, computed here) → aal2 → Board allowed → unenroll the
// factor (cleanup: the staging accounts end exactly as they started) → sign out. Aborts if an account already has a verified
// factor (never touches a real enrollment). Prints no secrets.
import { createHmac } from 'node:crypto';
import { loadEnv } from '../s00a/lib.mjs';
import { createClient } from '../../admin-web/node_modules/@supabase/supabase-js/dist/index.mjs';

const env = loadEnv();
const b32 = (s) => { const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = ''; for (const c of s.replace(/=+$/, '').toUpperCase()) bits += a.indexOf(c).toString(2).padStart(5, '0');
  const out = []; for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2)); return Buffer.from(out); };
const totp = (secret, offset = 0) => { const ctr = Buffer.alloc(8); ctr.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000) + offset));
  const h = createHmac('sha1', b32(secret)).update(ctr).digest(); const o = h[h.length - 1] & 15;
  return String(((h.readUInt32BE(o) & 0x7fffffff) % 1e6)).padStart(6, '0'); };
let fails = 0;
const check = (ok, name, detail = '') => { if (!ok) fails++; console.log(`${ok ? 'PASS' : 'FAIL'} | ${name}${detail ? ` | ${detail}` : ''}`); };

for (const who of [{ name: 'Carolina', email: 'carolina.demo@staging.invalid', pw: process.env.STAGING_DEMO_CAROLINA_PASSWORD },
                   { name: 'Mario', email: 'mario.demo@staging.invalid', pw: process.env.STAGING_DEMO_MARIO_PASSWORD }]) {
  if (!who.pw) { check(false, `${who.name}: demo password missing in ~/.fuxia-staging.env`); continue; }
  const sb = createClient(env.api, env.anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: e0 } = await sb.auth.signInWithPassword({ email: who.email, password: who.pw });
  if (e0) { check(false, `${who.name}: sign in`, e0.message); continue; }
  const pre = await sb.auth.mfa.listFactors();
  if ((pre.data?.totp?.length ?? 0) > 0) { check(false, `${who.name}: already has a verified factor — not touching it`); await sb.auth.signOut(); continue; }
  for (const f of pre.data?.all ?? []) if (f.status !== 'verified') await sb.auth.mfa.unenroll({ factorId: f.id });
  let r = await sb.rpc('f360_board_me');
  check(r.data?.ok === false && r.data?.error === 'No disponible.', `${who.name} aal1: f360_board_me denied (MFA required)`);
  r = await sb.rpc('f360_board_access_state');
  check(r.data === 'mfa_required', `${who.name} aal1: access_state = mfa_required`, String(r.data));
  r = await sb.rpc('f360_board_nav_visible');
  check(r.data === true, `${who.name} aal1: menu entry still visible (to reach the MFA screen)`);
  r = await sb.rpc('f360_measurement_health');
  check(!r.error && Array.isArray(r.data?.sources), `${who.name} aal1: rest of Fuxia 360 works (f360_measurement_health)`, r.error?.message ?? '');
  const en = await sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: `preprod e2e ${Date.now()}`, issuer: 'Fuxia 360 staging' });
  check(!en.error && !!en.data?.totp?.secret && en.data.totp.qr_code.startsWith('data:image/svg'), `${who.name}: TOTP enroll returns QR + secret`, en.error?.message ?? '');
  if (en.error) { await sb.auth.signOut(); continue; }
  const factorId = en.data.id;
  const bad = await sb.auth.mfa.challengeAndVerify({ factorId, code: totp(en.data.totp.secret, 20) });
  check(!!bad.error, `${who.name}: wrong code refused`);
  const ok = await sb.auth.mfa.challengeAndVerify({ factorId, code: totp(en.data.totp.secret) });
  check(!ok.error, `${who.name}: correct TOTP verifies`, ok.error?.message ?? '');
  const aal = await sb.auth.mfa.getAuthenticatorAssuranceLevel();
  check(aal.data?.currentLevel === 'aal2', `${who.name}: session is now aal2`, aal.data?.currentLevel ?? '');
  r = await sb.rpc('f360_board_me');
  check(r.data?.ok === true && r.data?.settings?.require_aal2 === true, `${who.name} aal2: f360_board_me allowed`);
  r = await sb.rpc('f360_board_access_state');
  check(r.data === 'ok', `${who.name} aal2: access_state = ok`);
  r = await sb.rpc('f360_board_periods', { p_year: 2026 });
  check(r.data?.ok === true, `${who.name} aal2: f360_board_periods allowed`);
  const un = await sb.auth.mfa.unenroll({ factorId });
  const post = await sb.auth.mfa.listFactors();
  check(!un.error && (post.data?.all?.length ?? 0) === (pre.data?.all ?? []).filter((f) => f.status === 'verified').length, `${who.name}: cleanup — test factor removed`, un.error?.message ?? '');
  await sb.auth.signOut();
}
console.log(fails ? `\n${fails} FAILED` : '\nALL MFA E2E CHECKS PASS (staging accounts left without factors, as found)');
process.exit(fails ? 1 : 0);
