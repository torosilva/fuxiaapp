// f360-instagram — transforms, auth, no-token behaviour and failure recording (no network, no database).
// Run: node --test fuxia-native/supabase/functions/f360-instagram/ig.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { kindOf, shortcodeOf, toAccountDay, toMediaRow, toMetrics } from './ig.ts';
import { handleInstagram, type IgEnv } from './handler.ts';

const env: IgEnv = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', META_ADS_TOKEN: 'TOKEN-SECRETO', F360_SYNC_SECRET: 's3cret' };
const req = (body: unknown, auth = 'Bearer s3cret') => new Request('http://x', { method: 'POST', headers: { Authorization: auth }, body: JSON.stringify(body) });
const res = (status: number, j: unknown) => ({ ok: status < 400, status, json: async () => j });
const NOW = new Date('2026-10-27T18:00:00Z');

test('kind: reels, stories, carousels and posts are told apart', () => {
  assert.equal(kindOf({ media_type: 'VIDEO', media_product_type: 'REELS' }), 'reel');
  assert.equal(kindOf({ media_type: 'IMAGE', media_product_type: 'STORY' }), 'story');
  assert.equal(kindOf({ media_type: 'CAROUSEL_ALBUM', media_product_type: 'FEED' }), 'carousel');
  assert.equal(kindOf({ media_type: 'IMAGE', media_product_type: 'FEED' }), 'post');
});

test('shortcode from the permalink; foreign links dropped', () => {
  assert.equal(shortcodeOf('https://www.instagram.com/reel/DPx1aBcDeF/'), 'DPx1aBcDeF');
  assert.equal(shortcodeOf('https://www.instagram.com/p/C0deX_y-z/'), 'C0deX_y-z');
  assert.equal(toMediaRow({ id: '1', timestamp: '2026-10-01T00:00:00+0000', permalink: 'https://evil.example/p/x' }).permalink, null);
});

test('metrics: saved → saves, watch time → ms, missing stays absent, negative/invalid → null (never 0)', () => {
  const m = toMetrics([{ name: 'reach', values: [{ value: 1200 }] }, { name: 'saved', values: [{ value: 7 }] }, { name: 'ig_reels_avg_watch_time', values: [{ value: 5300 }] },
    { name: 'shares', values: [{ value: -1 }] }, { name: 'weird', values: [{ value: 9 }] }]);
  assert.deepEqual(m, { reach: 1200, saves: 7, avg_watch_ms: 5300, shares: null });
  assert.equal('views' in m, false);
});

test('account day: total_value metrics and follows / unfollows from the follow_type breakdown', () => {
  const d = toAccountDay('2026-10-20', [
    { name: 'reach', total_value: { value: 3400 } }, { name: 'profile_views', total_value: { value: 210 } },
    { name: 'follows_and_unfollows', total_value: { breakdowns: [{ results: [{ dimension_values: ['FOLLOWER'], value: 15 }, { dimension_values: ['NON_FOLLOWER'], value: 4 }] }] } }]);
  assert.deepEqual(d, { date: '2026-10-20', reach: 3400, profile_views: 210, follows: 15, unfollows: 4 });
});

test('handler: no token → 503 and Meta is never called', async () => {
  let calls = 0;
  const r = await handleInstagram(req({ action: 'daily' }), { ...env, META_ADS_TOKEN: '' }, { fetch: (async () => { calls++; return res(200, {}); }) as never, rpc: (async () => ({})) as never });
  assert.equal(r.status, 503); assert.equal(calls, 0);
});

test('handler: wrong secret and no session → 401; bad action → 400', async () => {
  const fx = (async () => res(401, {})) as never;
  assert.equal((await handleInstagram(req({ action: 'daily' }, 'Bearer nope'), env, { fetch: fx })).status, 401);
  assert.equal((await handleInstagram(req({ action: 'borrar' }), env, { fetch: fx, rpc: (async () => ({})) as never })).status, 400);
  assert.equal((await handleInstagram(req({ action: 'backfill', from: '2025-01-01' }), env, { fetch: fx, rpc: (async () => ({})) as never, now: NOW })).status, 400);
});

test('handler: missing permissions → run recorded as failed with the hint; the token is never in the error', async () => {
  const rpcCalls: [string, Record<string, unknown>][] = [];
  const fx = (async () => res(400, { error: { message: 'Object does not exist, cannot be loaded due to missing permissions', code: 100 } })) as never;
  const r = await handleInstagram(req({ action: 'daily' }), env, { fetch: fx, rpc: (async (fn: string, a: Record<string, unknown>) => { rpcCalls.push([fn, a]); return {}; }) as never, now: NOW });
  const j = await r.json();
  assert.equal(r.status, 502);
  assert.match(j.error, /instagram_manage_insights/);
  assert.equal(JSON.stringify(j).includes('TOKEN-SECRETO'), false);
  assert.equal(rpcCalls[0][0], 'f360_measurement_run_failed'); assert.equal(rpcCalls[0][1].p_source_key, 'instagram');
});

test('handler: daily → 3 account days + followers today + posts of the last 60 days with their metrics, one import', async () => {
  const urls: string[] = []; let imported: Record<string, unknown> | null = null;
  const fx = (async (url: string) => {
    urls.push(url);
    if (url.includes('/insights?') && url.includes('metric_type=total_value')) return res(200, { data: [{ name: 'reach', total_value: { value: 100 } }] });
    if (url.includes('fields=followers_count')) return res(200, { followers_count: 25000 });
    if (url.includes('/media?')) return res(200, { data: [
      { id: '18000000000000001', media_type: 'VIDEO', media_product_type: 'REELS', timestamp: '2026-10-20T18:00:00+0000', permalink: 'https://www.instagram.com/reel/ABCDE12345/' },
      { id: '18000000000000002', media_type: 'IMAGE', media_product_type: 'FEED', timestamp: '2026-07-01T18:00:00+0000' }] });
    if (url.includes('/18000000000000001/insights')) return res(200, { data: [{ name: 'reach', values: [{ value: 900 }] }] });
    return res(404, {});
  }) as never;
  const r = await handleInstagram(req({ action: 'daily' }), env, { fetch: fx, rpc: (async (fn: string, a: Record<string, unknown>) => { if (fn === 'f360_instagram_import') imported = a; return { ok: true }; }) as never, now: NOW });
  assert.equal(r.status, 200);
  const acc = imported!.p_account as { date: string; reach?: number; followers_count?: number }[];
  assert.deepEqual(acc.map((a) => a.date), ['2026-10-26', '2026-10-25', '2026-10-24', '2026-10-27']);
  assert.equal(acc[3].followers_count, 25000);
  const media = imported!.p_media as { media_id: string; kind: string; metrics?: { reach?: number } }[];
  assert.equal(media.length, 1, 'the July post is older than 60 days');
  assert.equal(media[0].kind, 'reel'); assert.equal(media[0].metrics?.reach, 900);
  assert.ok(urls.every((u) => !u.includes('/stories')));
});
