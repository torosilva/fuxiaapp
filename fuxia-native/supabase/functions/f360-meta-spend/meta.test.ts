// f360-meta-spend — transform, windows, auth and failure recording (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { marketOf, toSpendRows, windows, mxToday } from './meta.ts';
import { handleMetaSpend, type MetaEnv } from './handler.ts';

const env: MetaEnv = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', META_ADS_TOKEN: 'TOKEN-SECRETO', META_AD_ACCOUNT_ID: '966161362834783', F360_SYNC_SECRET: 's3cret' };
const req = (body: unknown, auth = 'Bearer s3cret') => new Request('http://x', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) });
const res = (status: number, j: unknown) => ({ ok: status < 400, status, json: async () => j });

test('market: MX, CO, other countries ROW, missing UNKNOWN', () => {
  assert.equal(marketOf('MX'), 'MX'); assert.equal(marketOf('co'), 'CO'); assert.equal(marketOf('US'), 'ROW'); assert.equal(marketOf('unknown'), 'UNKNOWN'); assert.equal(marketOf(), 'UNKNOWN');
});

test('rows: per campaign × day × market, ROW countries summed in cents, empty rows dropped', () => {
  const rows = toSpendRows([
    { date_start: '2026-08-01', campaign_id: '1', campaign_name: 'A', country: 'MX', spend: '100.10', impressions: '10', clicks: '1' },
    { date_start: '2026-08-01', campaign_id: '1', campaign_name: 'A', country: 'US', spend: '0.10', impressions: '2', clicks: '0' },
    { date_start: '2026-08-01', campaign_id: '1', campaign_name: 'A', country: 'VE', spend: '0.20', impressions: '1', clicks: '1' },
    { date_start: '2026-08-01', campaign_id: '1', campaign_name: 'A', country: 'MY', spend: '0', impressions: '0', clicks: '0' },
    { date_start: '2026-08-01', campaign_id: '1', campaign_name: 'A', country: 'CO', spend: '50', impressions: '5', clicks: '0' },
  ], '966161362834783', 'MXN');
  assert.deepEqual(rows.map((r) => [r.market, r.spend, r.impressions, r.clicks]), [['CO', '50.00', '5', '0'], ['MX', '100.10', '10', '1'], ['ROW', '0.30', '3', '1']]);
  assert.ok(rows.every((r) => r.currency === 'MXN' && r.account_id === '966161362834783'));
});

test('rows: Meta-attributed purchases, their value and add-to-carts summed per market; a row with only purchases is kept', () => {
  const buy = (n: string, v: string) => ({ actions: [{ action_type: 'offsite_conversion.fb_pixel_purchase', value: n }, { action_type: 'offsite_conversion.fb_pixel_add_to_cart', value: '4' }, { action_type: 'link_click', value: '9' }],
    action_values: [{ action_type: 'offsite_conversion.fb_pixel_purchase', value: v }] });
  const rows = toSpendRows([
    { date_start: '2026-10-17', campaign_id: '1', country: 'CO', spend: '10', impressions: '5', ...buy('2', '4600.50') },
    { date_start: '2026-10-17', campaign_id: '1', country: 'CO', spend: '0', impressions: '0', ...buy('1', '100') },
    { date_start: '2026-10-17', campaign_id: '2', country: 'MX', spend: '0', impressions: '0', ...buy('1', '2800') },
    { date_start: '2026-10-17', campaign_id: '3', country: 'MX', spend: '5', impressions: '1' },
  ], '966161362834783', 'MXN');
  assert.deepEqual(rows.map((r) => [r.campaign_id, r.meta_purchases, r.meta_purchase_value, r.meta_add_to_cart]),
    [['1', '3', '4700.50', '8'], ['2', '1', '2800.00', '4'], ['3', '0', '0.00', '0']]);
});

test('windows: ≤31 days, contiguous, cover the range', () => {
  const w = windows('2026-05-01', '2026-10-10');
  assert.equal(w[0][0], '2026-05-01'); assert.equal(w.at(-1)![1], '2026-10-10');
  for (let i = 1; i < w.length; i++) assert.equal(Date.parse(w[i][0]) - Date.parse(w[i - 1][1]), 864e5);
  assert.ok(w.every(([a, b]) => (Date.parse(b) - Date.parse(a)) / 864e5 <= 30));
});

test('mx date: 03:00 UTC is still yesterday in CDMX', () => assert.equal(mxToday(new Date('2026-10-11T03:00:00Z')), '2026-10-10'));

test('auth: no secret / wrong secret → 401; GET → 405; bad backfill → 400', async () => {
  const deps = { fetch: (async () => { throw new Error('no network'); }) as never, rpc: (async () => { throw new Error('no db'); }) as never };
  assert.equal((await handleMetaSpend(req({ action: 'daily' }, ''), { ...env, SUPABASE_ANON_KEY: '' }, deps)).status, 401);
  assert.equal((await handleMetaSpend(req({ action: 'daily' }, 'Bearer nope'), { ...env, SUPABASE_ANON_KEY: '' }, deps)).status, 401);
  assert.equal((await handleMetaSpend(new Request('http://x'), env, deps)).status, 405);
  assert.equal((await handleMetaSpend(req({ action: 'backfill', from: '2026-10-09', to: '2099-01-01' }), env, deps)).status, 400);
});

test('daily: last 7 full days, account currency from Meta, rows to the import RPC', async () => {
  const calls: Array<[string, Record<string, unknown>]> = [];
  const fetchFn = async (url: string) => url.includes('/insights')
    ? res(200, { data: [{ date_start: '2026-10-09', campaign_id: '9', campaign_name: 'X', country: 'MX', spend: '12.5', impressions: '3', clicks: '1' }] })
    : res(200, { currency: 'MXN' });
  const r = await handleMetaSpend(req({ action: 'daily' }), env, { fetch: fetchFn as never, now: new Date('2026-10-10T15:00:00Z'),
    rpc: (async (fn: string, args: Record<string, unknown>) => { calls.push([fn, args]); return { ok: true }; }) as never });
  assert.equal(r.status, 200);
  assert.deepEqual(calls.map((c) => [c[0], c[1].p_from, c[1].p_to, c[1].p_currency]), [['f360_marketing_spend_api_import', '2026-10-03', '2026-10-09', 'MXN']]);
  assert.equal((calls[0][1].p_rows as Array<{ spend: string }>)[0].spend, '12.50');
});

test('Meta error → failure recorded, 502, token never echoed', async () => {
  const calls: string[] = [];
  const fetchFn = async () => res(400, { error: { code: 190, message: 'Error validating access token' } });
  const r = await handleMetaSpend(req({ action: 'daily' }), env, { fetch: fetchFn as never, now: new Date('2026-10-10T15:00:00Z'),
    rpc: (async (fn: string) => { calls.push(fn); return null; }) as never });
  const text = await r.text();
  assert.equal(r.status, 502); assert.deepEqual(calls, ['f360_measurement_run_failed']);
  assert.match(text, /code 190/); assert.doesNotMatch(text, /TOKEN-SECRETO/);
});
