import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleIntake } from '../handler.ts';
const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', F360_HILO_SECRET: 's' };
const post = (b: unknown, a = 'Bearer s') => new Request('https://f/x', { method: 'POST', headers: { Authorization: a }, body: JSON.stringify(b) });
const fake = (calls: any[]) => (async (u: string, i: RequestInit) => { calls.push(JSON.parse(String(i.body))); return new Response('{"id":"c1","new":true}', { status: 200 }); }) as unknown as typeof fetch;
test('secret required', async () => { const c: any[] = []; assert.equal((await handleIntake(post({ conversation_id: 'x' }, 'Bearer no'), env, fake(c))).status, 401); assert.equal(c.length, 0); });
test('maps channel, page context and transcript; strips markup', async () => {
  const c: any[] = [];
  const r = await handleIntake(post({ conversation_id: 'conv1', channel: 'web', reason: 'requested', summary: 'Hola <b>', last_messages: [{ role: 'user', content: 'quiero ayuda' }, { role: 'assistant', content: 'claro' }],
    metadata: { source: 'web_pdp', page: { producto: 'Botas Largas', color: 'Café', talla_mx: '24', pais: 'mx', url: 'https://staging4/x' } } }), env, fake(c));
  assert.equal(r.status, 200);
  assert.deepEqual(c[0].p, { conversation_id: 'conv1', source: 'hilo_web', reason: 'requested', summary: 'Hola b', transcript: [{ role: 'user', content: 'quiero ayuda' }, { role: 'assistant', content: 'claro' }],
    email: null, country: 'mx', product: 'Botas Largas', color: 'Café', size: '24 MX', page_url: 'https://staging4/x' });
});
test('mobile → hilo_app', async () => { const c: any[] = []; await handleIntake(post({ conversation_id: 'c', channel: 'mobile' }), env, fake(c)); assert.equal(c[0].p.source, 'hilo_app'); });
test('missing conversation → 400', async () => { assert.equal((await handleIntake(post({}), env, fake([]))).status, 400); });
