import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handlePush } from '../handler.ts';

const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', F360_PUSH_SECRET: 's3cret' };
const post = (auth = 'Bearer s3cret') => new Request('https://f/x', { method: 'POST', headers: { Authorization: auth }, body: '{"action":"send"}' });
function fake(notices: unknown[], expo: { status: number; body: unknown }, calls: { url: string; body: any }[] = []) {
  return (async (url: string, init: RequestInit) => {
    calls.push({ url: String(url), body: JSON.parse(String(init.body)) });
    if (String(url).endsWith('/f360_push_claim')) return new Response(JSON.stringify(notices), { status: 200 });
    if (String(url).endsWith('/f360_push_result')) return new Response('1', { status: 200 });
    return new Response(JSON.stringify(expo.body), { status: expo.status });
  }) as unknown as typeof fetch;
}
const notice = { id: 'n1', title: 'Apartado Fuxia Gold', body: 'Separa …', data: { type: 'f360_reservation' }, tokens: ['ExponentPushToken[abc]'] };

test('without the secret nothing is claimed', async () => {
  const calls: any[] = [];
  const r = await handlePush(post('Bearer nope'), env, fake([notice], { status: 200, body: {} }, calls));
  assert.equal(r.status, 401); assert.equal(calls.length, 0);
});
test('sends to Expo and reports the notice as done', async () => {
  const calls: any[] = [];
  const r = await handlePush(post(), env, fake([notice], { status: 200, body: { data: [{ status: 'ok' }] } }, calls));
  assert.equal((await r.json()).sent, 1);
  const expo = calls.find((c) => c.url.includes('exp.host'));
  assert.equal(expo.body[0].to, 'ExponentPushToken[abc]'); assert.equal(expo.body[0].channelId, 'apartados');
  assert.deepEqual(calls.at(-1).body.p_results, [{ id: 'n1', done: true, result: 'ok 1/1' }]);
});
test('no device → closed as "sin dispositivo", Expo not called', async () => {
  const calls: any[] = [];
  await handlePush(post(), env, fake([{ ...notice, tokens: [] }], { status: 200, body: {} }, calls));
  assert.ok(!calls.some((c) => c.url.includes('exp.host')));
  assert.equal(calls.at(-1).body.p_results[0].result, 'sin dispositivo');
});
test('Expo failure → left pending for the retry', async () => {
  const calls: any[] = [];
  await handlePush(post(), env, fake([notice], { status: 500, body: {} }, calls));
  assert.equal(calls.at(-1).body.p_results[0].done, false);
});
