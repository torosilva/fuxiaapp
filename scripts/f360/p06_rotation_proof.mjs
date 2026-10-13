// P0-6.2 proof on STAGING for an EXISTING (legacy) account: create a fictitious account the old way (derived password), show the
// derived password works, rotate ONLY that account, show it no longer works, and show the WhatsApp-code login still works.
// Run: scripts/s00a/run.sh ../f360/p06_rotation_proof.mjs        (fictitious +1 555 019 0966; deleted at the end)
import { execFileSync } from 'node:child_process';
import { loadEnv, client } from '../s00a/lib.mjs';
const env = loadEnv(); const c = client(env);
const PHONE = '+15550190966', EMAIL = '15550190966@fuxia.app', LEGACY = `fuxia_${PHONE}_${env.otpSalt}`;
let fails = 0; const check = (ok, n, d = '') => { if (!ok) fails++; console.log(`${ok ? 'PASS' : 'FAIL'} | ${n}${d ? ` | ${d}` : ''}`); };
const grant = (pw) => fetch(`${env.api}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: env.anon, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: EMAIL, password: pw }) }).then((r) => r.status);
const cr = await c.admin.create({ email: EMAIL, password: LEGACY, email_confirm: true, user_metadata: { phone: PHONE } });
check(cr.ok, 'R0 cuenta "antigua" de prueba creada con la contraseña derivada', cr.status);
check(await grant(LEGACY) === 200, 'R1 ANTES: la contraseña derivada abre la cuenta antigua');
const out = execFileSync('node', ['scripts/f360/p06_rotate_passwords.mjs', '--apply', `--only=${EMAIL}`], { encoding: 'utf8' }).trim();
check(JSON.parse(out).rotated === 1, 'R2 rotación de esa única cuenta', out);
check(await grant(LEGACY) === 400, 'R3 DESPUÉS: la contraseña derivada ya NO abre la cuenta');
await c.svcRest('POST', 'otp_verifications', { body: { phone: PHONE, code: '424242', expires_at: new Date(Date.now() + 6e5).toISOString() } });
const v = await c.fn('whatsapp-otp', { body: { action: 'verify', phone: PHONE, code: '424242' } });
check(v.ok && !!v.json?.session?.access_token, 'R4 la clienta sigue entrando con su código de WhatsApp', v.status);
await c.svcRest('DELETE', `otp_verifications?phone=eq.${encodeURIComponent(PHONE)}`, { prefer: 'return=minimal' });
const u = ((await c.admin.list()).json?.users ?? []).find((x) => x.email === EMAIL);
if (u) check((await c.admin.del(u.id)).ok, 'Z cuenta de prueba borrada');
console.log(fails ? `${fails} FAIL` : 'TODO PASS'); process.exit(fails ? 1 : 0);
