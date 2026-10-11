// Fuxia Academy A1 — functional walkthrough against STAGING with real sessions (Mario 2026-10-11). Run during the test window:
//   scripts/s00a/run.sh ../f360/academy_a1_walkthrough.mjs
// Accounts: alumna.prueba1/2 (fictitious), carolina.demo / mario.demo (staging demo owners). Carolina gets a TEMPORARY TOTP factor for the
// aal2 approval and it is removed at the end (aborts if she already has a verified factor). Prints PASS/FAIL, no secrets.
import { createHmac } from 'node:crypto';
import { loadEnv } from '../s00a/lib.mjs';
import { createClient } from '../../admin-web/node_modules/@supabase/supabase-js/dist/index.mjs';

const env = loadEnv();
const b32 = (s) => { const a = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'; let bits = ''; for (const c of s.replace(/=+$/, '').toUpperCase()) bits += a.indexOf(c).toString(2).padStart(5, '0');
  const out = []; for (let i = 0; i + 8 <= bits.length; i += 8) out.push(parseInt(bits.slice(i, i + 8), 2)); return Buffer.from(out); };
const totp = (secret) => { const ctr = Buffer.alloc(8); ctr.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const h = createHmac('sha1', b32(secret)).update(ctr).digest(); const o = h[h.length - 1] & 15; return String(((h.readUInt32BE(o) & 0x7fffffff) % 1e6)).padStart(6, '0'); };
let fails = 0;
const check = (ok, name, detail = '') => { if (!ok) fails++; console.log(`${ok ? 'PASS' : 'FAIL'} | ${name}${detail ? ` | ${String(detail).slice(0, 200)}` : ''}`); };
const login = async (email, pw) => { const sb = createClient(env.api, env.anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error } = await sb.auth.signInWithPassword({ email, password: pw }); if (error) throw new Error(`login ${email}: ${error.message}`); return sb; };
const rpc = async (sb, fn, args = {}) => { const { data, error } = await sb.rpc(fn, args); return error ? { ok: false, error: error.message } : data; };

const a1 = await login('alumna.prueba1@staging.invalid', process.env.STAGING_ACADEMY_ALUMNA1_PASSWORD);
const a2 = await login('alumna.prueba2@staging.invalid', process.env.STAGING_ACADEMY_ALUMNA2_PASSWORD);
const caro = await login('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const mario = await login('mario.demo@staging.invalid', process.env.STAGING_DEMO_MARIO_PASSWORD);

// 1 · access allowed / denied
check((await rpc(a2, 'f360_academy_me')).sales === 'bloqueado', 'R1 Alumna 2 (vendedora activa sin permiso de prueba) = BLOQUEADA');
check((await rpc(a2, 'f360_academy_home')).ok === false, 'R2 Alumna 2 no ve cursos');
check((await rpc(a1, 'f360_academy_me')).sales === 'ok', 'R3 Alumna 1 (permiso de prueba) = acceso');
check(JSON.stringify((await rpc(a1, 'f360_academy_home')).courses) === '[]', 'R4 Alumna 1 no ve el borrador antes de publicarse');
check((await rpc(a1, 'f360_academy_admin_overview')).ok === false, 'R5 Alumna 1 sin panel de contenido');

// 2 · content review and publication (Mario sends, Carolina approves with aal2)
const ov = await rpc(mario, 'f360_academy_admin_overview');
const course = ov.courses?.find((c) => c.key === 'starter-ballerinas-parte-1');
const v1 = course?.versions?.[0];
check(v1?.status === 'borrador' && v1?.lessons === 7 && v1?.items === 24, 'P1 curso piloto en borrador: 7 lecciones, 24 preguntas', JSON.stringify(v1));
const ver = await rpc(mario, 'f360_academy_admin_version', { p_version: v1.id });
check(ver.can_edit && Object.values(ver.lessons.find((l) => l.key === '2.p').products).every((p) => p?.knowledge?.version), 'P2 vista previa con fichas validadas en vivo (5 modelos)');
check((await rpc(mario, 'f360_academy_comment', { p_version: v1.id, p_lesson_key: '2.0', p_item_key: null, p_block: 1, p_body: 'Recorrido A1: comentario de prueba' })).ok, 'P3 comentario de revisión');
const sub = await rpc(mario, 'f360_academy_submit', { p_version: v1.id, p_reason: 'Recorrido funcional A1 (staging)' });
check(sub.ok && sub.operation === 'publish_sales', 'P4 enviar a revisión → solicitud publish_sales', JSON.stringify(sub));
check((await rpc(mario, 'f360_academy_lesson_save', { p_lesson: ver.lessons[0].id, p_title: 'x x x', p_minutes: 3, p_blocks: [{ type: 'texto', text: 'cambio', source: '[X]' }], p_product_codes: [] })).ok === false,
  'P5 lo enviado ya no se edita');
check((await rpc(mario, 'f360_academy_decide', { p_version: v1.id, p_approve: true, p_reason: 'yo' })).ok === false, 'P6 Mario no aprueba contenido ordinario');
check((await rpc(caro, 'f360_academy_decide', { p_version: v1.id, p_approve: true, p_reason: 'ok' })).error === 'mfa_required', 'P7 Carolina sin segundo factor: no aprueba');
const pre = await caro.auth.mfa.listFactors();
let factorId = null;
if ((pre.data?.totp?.length ?? 0) > 0) check(false, 'P8 Carolina demo ya tenía un factor verificado: no se toca (aprobación no probada)');
else {
  const en = await caro.auth.mfa.enroll({ factorType: 'totp', friendlyName: `academy A1 ${Date.now()}`, issuer: 'Fuxia 360 staging' });
  factorId = en.data?.id;
  const okv = await caro.auth.mfa.challengeAndVerify({ factorId, code: totp(en.data.totp.secret) });
  check(!okv.error && (await caro.auth.mfa.getAuthenticatorAssuranceLevel()).data?.currentLevel === 'aal2', 'P8 Carolina verifica segundo factor temporal (aal2)');
  const d = await rpc(caro, 'f360_academy_decide', { p_version: v1.id, p_approve: true, p_reason: 'Revisado en recorrido A1' });
  check(d.ok && d.status === 'publicado' && d.self_approval === false, 'P9 Carolina aprueba y publica (dos personas)', JSON.stringify(d));
}
const ev = (await rpc(caro, 'f360_academy_admin_overview')).events ?? [];
check(['requested', 'approved', 'consumed'].every((a) => ev.some((e) => e.action === a && e.version === 1)), 'P10 historial del registro: solicitada → aprobada → usada');

// 3 · learning: lessons, progress, practice evaluation, fichas
const home = await rpc(a1, 'f360_academy_home');
const c1 = home.courses?.[0];
check(c1?.lessons?.length === 7, 'L1 Alumna 1 ve el curso publicado con 7 lecciones');
const l20 = c1.lessons.find((l) => l.key === '2.0');
const v20 = await rpc(a1, 'f360_academy_lesson', { p_lesson: l20.id });
check(v20.ok && v20.practice.length === 2 && v20.practice.every((q) => !('answer' in q)), 'L2 abre 2.0; práctica llega sin respuestas');
check((await rpc(a1, 'f360_academy_progress_save', { p_lesson: l20.id, p_card: 2, p_done: false })).ok, 'L3 guarda progreso en la tarjeta 2');
check((await rpc(a1, 'f360_academy_lesson', { p_lesson: l20.id })).progress?.card_index === 2, 'L4 retoma en la tarjeta 2');
const qA01 = v20.practice.find((q) => q.key === 'A01'), qA05 = v20.practice.find((q) => q.key === 'A05');
check((await rpc(a1, 'f360_academy_answer', { p_item: qA01.id, p_answer: { choice: 'b' } })).correct === true, 'L5 respuesta correcta calificada por el servidor');
check((await rpc(a1, 'f360_academy_answer', { p_item: qA05.id, p_answer: { choice: 'c' } })).correct === false, 'L6 respuesta incorrecta calificada por el servidor');
check((await rpc(a1, 'f360_academy_progress_save', { p_lesson: l20.id, p_card: 5, p_done: true })).ok, 'L7 termina la lección 2.0');
const l2p = c1.lessons.find((l) => l.key === '2.p');
const v2p = await rpc(a1, 'f360_academy_lesson', { p_lesson: l2p.id });
check(Object.keys(v2p.lesson?.products ?? {}).length === 5, 'L8 lección 2.p con las 5 fichas congeladas');
check((await rpc(a1, 'f360_academy_fichas')).fichas?.length === 5, 'L9 pantalla de fichas: 5 modelos');
check((await rpc(a2, 'f360_academy_lesson', { p_lesson: l20.id })).ok === false, 'L10 Alumna 2 sigue bloqueada con el curso publicado');
const team = await rpc(caro, 'f360_academy_team');
const row = team.learners?.find((x) => x.tester);
check(row && row.lessons_done === 1 && row.practice.answered === 2 && row.practice.correct === 1 && row.store, 'L11 Carolina ve el avance individual y la tienda', JSON.stringify(row));

// 4 · remove the temporary factor
if (factorId) {
  const un = await caro.auth.mfa.unenroll({ factorId });
  check(!un.error && ((await caro.auth.mfa.listFactors()).data?.all?.length ?? 0) === 0, 'Z1 factor temporal de Carolina retirado');
}
for (const sb of [a1, a2, caro, mario]) await sb.auth.signOut();
console.log(fails ? `\n${fails} FAIL` : '\nTODO PASS');
process.exit(fails ? 1 : 0);
