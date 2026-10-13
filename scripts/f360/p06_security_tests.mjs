// P0-6 security tests against STAGING (real Edge Function + Auth + PostgREST). Run: scripts/s00a/run.sh ../f360/p06_security_tests.mjs
// Uses ONE fictitious phone (+1 555 019 0955, never a real person). OTP codes are planted directly in public.otp_verifications with the
// service key (staging has no SMS provider). Cleans up its own OTP rows and the test account at the end. lib refuses production.
import { loadEnv, client, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const PHONE = '+15550190955';
const EMAIL = '15550190955@fuxia.app';
let fails = 0;
const check = (ok, name, detail = '') => { if (!ok) fails++; console.log(`${ok ? 'PASS' : 'FAIL'} | ${name}${detail ? ` | ${String(detail).slice(0, 160)}` : ''}`); };
const otp = (body) => c.fn('whatsapp-otp', { body });
const plant = async (code, minutesAgo = 0) => c.svcRest('POST', 'otp_verifications',
  { body: { phone: PHONE, code, expires_at: new Date(Date.now() + 10 * 60e3).toISOString(), created_at: new Date(Date.now() - minutesAgo * 60e3).toISOString() } });
const clearOtp = () => c.svcRest('DELETE', `otp_verifications?phone=eq.${encodeURIComponent(PHONE)}`, { prefer: 'return=minimal' });
const pwGrant = (email, password) => fetch(`${env.api}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: env.anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) });

await clearOtp();
// T1 · fixed store-review login is OFF (no REVIEW_BYPASS_ENABLED in staging)
let r = await otp({ action: 'verify', phone: '+525555555555', code: '555555' });
check(r.status === 401 && !r.json?.session, 'T1 código fijo de revisión (+525555555555 / 555555) RECHAZADO', r.status);
r = await otp({ action: 'check_phone', phone: '+525555555555' });
check(r.ok && r.json?.exists === false, 'T1b el número de revisión ya no se "reconoce" como cuenta demo', JSON.stringify(r.json));
// T5 · errors without provider details
r = await otp({ action: 'send', phone: PHONE });
check(!('debug' in (r.json ?? {})), 'T5 los errores ya no devuelven "debug"', `${r.status} ${JSON.stringify(r.json)}`);
await clearOtp();
// T3 · 5 wrong attempts → code invalidated
await plant('246810');
const wrong = [];
for (let i = 0; i < 5; i++) wrong.push((await otp({ action: 'verify', phone: PHONE, code: '111111' })).status);
r = await otp({ action: 'verify', phone: PHONE, code: '246810' });
check(wrong.every((s) => s === 401) && r.status === 429 && !r.json?.session, 'T3 5 intentos fallidos → el código se invalida (aunque luego sea el correcto)', `${wrong.join(',')} → ${r.status}`);
await clearOtp();
// T4 · max 3 codes / 10 min
for (let i = 0; i < 3; i++) await plant(`99999${i}`);
r = await otp({ action: 'send', phone: PHONE });
check(r.status === 429, 'T4 cuarto envío en 10 min → 429', r.status);
await clearOtp();
// T-ok · correct code → session WITHOUT password (new account)
await plant('135790');
r = await otp({ action: 'verify', phone: PHONE, code: '135790' });
const tok = r.json?.session?.access_token;
check(r.ok && !!tok && !!r.json?.session?.refresh_token && 'isNewUser' in r.json && 'customer' in r.json, 'T6 código correcto → sesión con la misma forma de respuesta { success, session, isNewUser, customer }', r.status);
const me = tok ? await fetch(`${env.api}/auth/v1/user`, { headers: { apikey: env.anon, Authorization: `Bearer ${tok}` } }).then((x) => x.json()) : null;
check(me?.email === EMAIL && me?.user_metadata?.phone === PHONE, 'T7 la sesión es de la cuenta {tel}@fuxia.app y conserva el teléfono', me?.email);
r = await otp({ action: 'verify', phone: PHONE, code: '135790' });
check(r.status === 401, 'T8 el mismo código no se usa dos veces', r.status);
// T2 · the derived password no longer opens the account
const g = await pwGrant(EMAIL, `fuxia_${PHONE}_${env.otpSalt}`);
check(g.status === 400, 'T2 la contraseña derivada fuxia_{tel}_{OTP_SALT} NO abre la cuenta nueva', g.status);
// T9 · a session without a Fuxia 360 role is denied everywhere internal
if (tok) {
  for (const fn of ['f360_me', 'f360_board_me', 'f360_admin_sellers']) {
    const x = await c.rest('POST', `rpc/${fn}`, { token: tok, body: {} });
    const denied = !x.ok || x.json?.ok === false;
    check(denied, `T9 cuenta sin rol: ${fn} negado`, `${x.status}`);
  }
}
// T10 · second login of an EXISTING account also works (magic link path, no password)
await clearOtp(); await plant('864200');
r = await otp({ action: 'verify', phone: PHONE, code: '864200' });
check(r.ok && !!r.json?.session?.access_token && r.json?.isNewUser !== undefined, 'T10 segundo ingreso de una cuenta existente → sesión', r.status);
// cleanup
await clearOtp();
const list = await c.admin.list();
const u = (list.json?.users ?? []).find((x) => x.email === EMAIL);
if (u) { const d = await c.admin.del(u.id); check(d.ok, 'Z1 cuenta de prueba borrada', d.status); }
check(psql(`SELECT count(*) FROM public.otp_verifications WHERE phone = '${PHONE}';`, {}, { readOnly: true }) === '0', 'Z2 sin códigos de prueba restantes');
console.log(fails ? `\n${fails} FAIL` : '\nTODO PASS');
process.exit(fails ? 1 : 0);
