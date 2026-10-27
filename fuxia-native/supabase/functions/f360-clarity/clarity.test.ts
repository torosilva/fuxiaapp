// f360-clarity — daily capture: 3 calls, import per breakdown, no token → no call, failures recorded (no network, no database).
// Run: node --test fuxia-native/supabase/functions/f360-clarity/clarity.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanUrl, validMetrics } from './clarity.ts';
import { handleClarity, type ClarityEnv } from './handler.ts';

const env: ClarityEnv = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', CLARITY_API_TOKEN: 'CLARITY-SECRETO', F360_SYNC_SECRET: 's3cret' };
const req = (body: unknown, auth = 'Bearer s3cret') => new Request('http://x', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) });
const res = (status: number, j: unknown) => ({ ok: status < 400, status, json: async () => j });
const NOW = new Date('2026-10-28T06:10:00Z');   // 00:10 CDMX

test('only well-formed metrics are kept', () => {
  assert.deepEqual(validMetrics([{ metricName: 'Traffic', information: [{ totalSessionCount: 3 }] }, { metricName: 'x y', information: [] }, { information: [] }]),
    [{ metricName: 'Traffic', information: [{ totalSessionCount: 3 }] }]);
  assert.throws(() => validMetrics({}));
});

test('URLs keep only path + utm: order keys and click ids are dropped', () => {
  assert.equal(cleanUrl('https://fuxiaballerinas.com/co/finalizar-compra/order-pay/5876/?key=wc_order_q2Rfj8nw8Ccyc'), 'https://fuxiaballerinas.com/co/finalizar-compra/order-pay/5876/');
  assert.equal(cleanUrl('https://fuxiaballerinas.com/mx/?utm_source=ig&utm_medium=social&fbclid=PAZXh0bgNhZW0'), 'https://fuxiaballerinas.com/mx/?utm_source=ig&utm_medium=social');
  assert.equal(cleanUrl('Instagram'), 'Instagram');
  const [m] = validMetrics([{ metricName: 'Traffic', information: [{ Url: 'https://x.com/p?gclid=1&email=a%40b.com', totalSessionCount: 2 }] }]);
  assert.deepEqual(m.information[0], { Url: 'https://x.com/p', totalSessionCount: 2 });
});

test('no token → 503 and Clarity is never called (the 10 daily calls are not spent)', async () => {
  let calls = 0;
  const r = await handleClarity(req({}), { ...env, CLARITY_API_TOKEN: '' }, { fetch: (async () => { calls++; return res(200, []); }) as never });
  assert.equal(r.status, 503); assert.equal(calls, 0);
});

test('daily: 3 calls of 1 day (Source, Device, URL), each imported with the CDMX day', async () => {
  const urls: string[] = []; const auth: string[] = []; const imports: Record<string, unknown>[] = [];
  const fx = (async (url: string, init?: { headers?: Record<string, string> }) => { urls.push(url); auth.push(init?.headers?.Authorization ?? ''); return res(200, [{ metricName: 'Traffic', information: [{ totalSessionCount: 1 }] }]); }) as never;
  const r = await handleClarity(req({ action: 'daily' }), env, { fetch: fx, rpc: (async (fn: string, a: Record<string, unknown>) => { if (fn === 'f360_clarity_import') imports.push(a); return { ok: true }; }) as never, now: NOW });
  assert.equal(r.status, 200);
  assert.equal(urls.length, 3);
  assert.ok(urls.every((u) => u.includes('numOfDays=1')));
  assert.deepEqual(imports.map((i) => i.p_dimension), ['Source', 'Device', 'URL']);
  assert.ok(imports.every((i) => i.p_window_end === '2026-10-28' && i.p_num_days === 1));
  assert.ok(auth.every((a) => a === 'Bearer CLARITY-SECRETO'));
});

test('quota exhausted → run recorded as failed, the token is never in the answer', async () => {
  const failed: Record<string, unknown>[] = [];
  const r = await handleClarity(req({}), env, { fetch: (async () => res(429, {})) as never, rpc: (async (fn: string, a: Record<string, unknown>) => { if (fn === 'f360_measurement_run_failed') failed.push(a); return {}; }) as never, now: NOW });
  const j = await r.json();
  assert.equal(r.status, 502); assert.match(j.error, /10 llamadas/);
  assert.equal(failed[0].p_source_key, 'clarity');
  assert.equal(JSON.stringify(j).includes('CLARITY-SECRETO'), false);
});

test('a seller session cannot trigger it', async () => {
  const r = await handleClarity(req({}, 'Bearer nope'), env, { fetch: (async () => res(401, {})) as never });
  assert.equal(r.status, 401);
});
