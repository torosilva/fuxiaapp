// f360-ga4 — windows, report → rows (ROW summed, TODOS distinct), no key → no call, failures recorded (no network, no database).
// Run: node --test fuxia-native/supabase/functions/f360-ga4/ga4.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { toRows, windows } from './ga4.ts';
import { handleGa4, type Ga4Env } from './handler.ts';

const pem = generateKeyPairSync('rsa', { modulusLength: 2048 }).privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
const KEY = JSON.stringify({ client_email: 'x@y.iam.gserviceaccount.com', private_key: pem });
const env: Ga4Env = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', GA4_SA_KEY_JSON: KEY, F360_SYNC_SECRET: 's3cret' };
const req = (body: unknown, auth = 'Bearer s3cret') => new Request('http://x', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) });
const res = (status: number, j: unknown) => ({ ok: status < 400, status, json: async () => j });
const NOW = new Date('2026-10-30T07:30:00Z');   // 01:30 CDMX
const W = windows('2026-10-30');

test('windows end yesterday: 14 days and the 14 before', () => {
  assert.deepEqual(W, { actual: { from: '2026-10-16', to: '2026-10-29' }, anterior: { from: '2026-10-02', to: '2026-10-15' } });
});

test('rows: Mexico/Colombia by name, other countries summed into ROW, unknown events ignored', () => {
  const rep = { dimensionHeaders: [{ name: 'country' }, { name: 'sessionDefaultChannelGroup' }, { name: 'eventName' }, { name: 'dateRange' }],
    rows: [
      { dimensionValues: [{ value: 'Mexico' }, { value: 'Paid Social' }, { value: 'add_to_cart' }, { value: 'actual' }], metricValues: [{ value: '17' }] },
      { dimensionValues: [{ value: 'Spain' }, { value: 'Direct' }, { value: 'view_item' }, { value: 'anterior' }], metricValues: [{ value: '3' }] },
      { dimensionValues: [{ value: 'Chile' }, { value: 'Direct' }, { value: 'view_item' }, { value: 'anterior' }], metricValues: [{ value: '2' }] },
      { dimensionValues: [{ value: 'Mexico' }, { value: 'Direct' }, { value: 'scroll' }, { value: 'actual' }], metricValues: [{ value: '99' }] },
    ] };
  const rows = toRows(rep, W, true);
  assert.equal(rows.length, 2);
  assert.deepEqual(rows[0], { period: 'actual', date_from: '2026-10-16', date_to: '2026-10-29', market: 'MX', channel: 'Paid Social', step: 'add_to_cart', users: 17 });
  assert.equal(rows[1].market, 'ROW'); assert.equal(rows[1].users, 5); assert.equal(rows[1].period, 'anterior');
});

test('the key is accepted as JSON or as base64 JSON', async () => {
  const { parseKey } = await import('./ga4.ts');
  assert.equal(parseKey(KEY).client_email, 'x@y.iam.gserviceaccount.com');
  assert.equal(parseKey(Buffer.from(KEY).toString('base64')).client_email, 'x@y.iam.gserviceaccount.com');
  assert.throws(() => parseKey('{"client_email":"a"}'), /no es válida/);
});

test('without the key → 503 and no call', async () => {
  let calls = 0;
  const r = await handleGa4(req({ action: 'daily' }), { ...env, GA4_SA_KEY_JSON: '' }, { fetch: (async () => { calls++; return res(200, {}); }) as never, rpc: (async () => ({})) as never, now: NOW });
  assert.equal(r.status, 503); assert.equal(calls, 0);
});

test('wrong bearer and no session → 401', async () => {
  const r = await handleGa4(req({}, 'Bearer nope'), env, { fetch: (async () => res(401, {})) as never, rpc: (async () => ({})) as never, now: NOW });
  assert.equal(r.status, 401);
});

test('daily: token, two reports, one import with TODOS + channel rows', async () => {
  const urls: string[] = []; const imports: Record<string, unknown>[] = [];
  const fetchFn = async (url: string, init?: { body?: string }) => {
    urls.push(url);
    if (url.includes('oauth2')) { assert.match(String(init?.body), /assertion=[\w-]+\.[\w-]+\.[\w-]+/); return res(200, { access_token: 'tok' }); }
    const withChannel = String(init?.body).includes('sessionDefaultChannelGroup');
    return res(200, { dimensionHeaders: [{ name: 'country' }, ...(withChannel ? [{ name: 'sessionDefaultChannelGroup' }] : []), { name: 'eventName' }, { name: 'dateRange' }],
      rows: [{ dimensionValues: [{ value: 'Mexico' }, ...(withChannel ? [{ value: 'Organic Social' }] : []), { value: 'purchase' }, { value: 'actual' }], metricValues: [{ value: '2' }] }] });
  };
  const r = await handleGa4(req({ action: 'daily' }), env, { fetch: fetchFn as never, rpc: (async (fn: string, a: Record<string, unknown>) => { imports.push({ fn, ...a }); return { ok: true }; }) as never, now: NOW });
  assert.equal(r.status, 200);
  assert.equal(urls.filter((u) => u.includes(':runReport')).length, 2);
  assert.equal(imports.length, 1); assert.equal(imports[0].fn, 'f360_ga4_import'); assert.equal(imports[0].p_captured_on, '2026-10-30');
  const rows = imports[0].p_rows as { channel: string }[];
  assert.deepEqual(rows.map((x) => x.channel).sort(), ['Organic Social', 'TODOS']);
});

test('GA4 refuses → 502 and the failure is recorded', async () => {
  const calls: string[] = [];
  const fetchFn = async (url: string) => (url.includes('oauth2') ? res(200, { access_token: 'tok' }) : res(403, { error: { message: 'User does not have sufficient permissions' } }));
  const r = await handleGa4(req({ action: 'daily' }), env, { fetch: fetchFn as never, rpc: (async (fn: string) => { calls.push(fn); return {}; }) as never, now: NOW });
  assert.equal(r.status, 502);
  assert.deepEqual(calls, ['f360_measurement_run_failed']);
});
