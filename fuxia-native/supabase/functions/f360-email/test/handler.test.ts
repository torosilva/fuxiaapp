import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleEmail } from '../handler.ts';
const base = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', F360_EMAIL_SECRET: 's', RESEND_API_KEY: '', EMAIL_FROM: '' };
const post = (a = 'Bearer s') => new Request('https://f/x', { method: 'POST', headers: { Authorization: a }, body: '{}' });
const mail = { id: 'm1', to: 'info@fuxiaballerinas.com', subject: 'S', text: 'T', reply_to: null };
function fake(calls: any[], resend = { status: 200, body: { id: 'r1' } }) {
  return (async (url: string, init: RequestInit) => { calls.push({ url: String(url), body: JSON.parse(String(init.body)) });
    if (String(url).endsWith('/f360_email_claim')) return new Response(JSON.stringify([mail]), { status: 200 });
    if (String(url).endsWith('/f360_email_result')) return new Response('1', { status: 200 });
    return new Response(JSON.stringify(resend.body), { status: resend.status }); }) as unknown as typeof fetch;
}
test('without secret: 401, nothing claimed', async () => { const c: any[] = []; assert.equal((await handleEmail(post('x'), base, fake(c))).status, 401); assert.equal(c.length, 0); });
test('no provider: stays pending without burning attempts', async () => {
  const c: any[] = []; await handleEmail(post(), base, fake(c));
  assert.ok(!c.some((x) => x.url.includes('resend'))); assert.deepEqual(c.at(-1).body.p_results[0], { id: 'm1', done: false, retry_free: true, result: 'sin proveedor de correo' });
});
test('Resend configured: sends and marks done', async () => {
  const c: any[] = []; await handleEmail(post(), { ...base, RESEND_API_KEY: 'k', EMAIL_FROM: 'Fuxia <hola@fuxiaballerinas.com>' }, fake(c));
  const r = c.find((x) => x.url.includes('resend')); assert.deepEqual(r.body.to, ['info@fuxiaballerinas.com']); assert.equal(c.at(-1).body.p_results[0].done, true);
});
test('Resend error: retried later', async () => {
  const c: any[] = []; await handleEmail(post(), { ...base, RESEND_API_KEY: 'k', EMAIL_FROM: 'x' }, fake(c, { status: 422, body: { message: 'domain not verified' } }));
  assert.equal(c.at(-1).body.p_results[0].done, false);
});
