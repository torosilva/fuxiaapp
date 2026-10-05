import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleStorefront } from '../handler.ts';

const ORIGIN = 'https://staging4.fuxiaballerinas.com';
const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc-0123456789abcdef', ALLOWED_ORIGINS: ORIGIN, TARGET_KEY: 'woo_staging4' };
function fakeFetch(answers: Record<string, unknown>, calls: { fn: string; args: Record<string, unknown> }[] = []) {
  return (async (url: string, init: RequestInit) => {
    const fn = String(url).split('/rpc/')[1];
    calls.push({ fn, args: JSON.parse(String(init.body)) });
    const a = answers[fn];
    return new Response(JSON.stringify(a instanceof Error ? { message: a.message } : a), { status: a instanceof Error ? 400 : 200 });
  }) as unknown as typeof fetch;
}
const post = (body: unknown, origin = ORIGIN, headers: Record<string, string> = {}) =>
  new Request('https://f/x', { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });

test('only the store origin may call it (CORS)', async () => {
  const r = await handleStorefront(post({ action: 'promise', woo_product_id: 1 }, 'https://evil.example'), env, fakeFetch({}));
  assert.equal(r.status, 403);
});
test('promise: channel from configuration, never from the browser; market normalized', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const data = { market: 'MX', variations: { '10': { case: 'in_stock', headline: 'Entrega Inmediata en Zona Metropolitana' } }, trust: [] };
  const r = await handleStorefront(post({ action: 'promise', woo_product_id: 9601, market: 'mx', target: 'woo_production' }), env, fakeFetch({ f360_storefront_promise: data }, calls));
  assert.deepEqual(await r.json(), data);
  assert.equal(calls[0].args.p_target_key, 'woo_staging4');
  assert.equal(calls[0].args.p_market, 'MX');
});
test('promise: database error → empty promise (page keeps its own state)', async () => {
  const r = await handleStorefront(post({ action: 'promise', woo_product_id: 9602, market: 'CO' }), env, fakeFetch({ f360_storefront_promise: new Error('x') }));
  assert.deepEqual(await r.json(), { variations: {}, trust: [] });
});
test('notify_me forwards consent, hashes the IP (never stores it raw)', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const r = await handleStorefront(post({ action: 'notify_me', woo_product_id: 9603, woo_variation_id: 77, market: 'MX', phone: '55 1234 5678', consent: true, name: '<b>Ana</b>' },
    ORIGIN, { 'x-forwarded-for': '203.0.113.9, 10.0.0.1' }), env, fakeFetch({ f360_stock_intent_create: { ok: true, already: false } }, calls));
  assert.equal(r.status, 200);
  const a = calls[0].args;
  assert.equal(a.p_consent, true); assert.equal(a.p_source, 'pdp'); assert.equal(a.p_name, 'bAna/b');
  assert.match(String(a.p_ip_hash), /^[0-9a-f]{32}$/); assert.ok(!String(JSON.stringify(a)).includes('203.0.113.9'));
});
test('notify_me: consent must be literally true; refusals pass through as 400', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const r = await handleStorefront(post({ action: 'notify_me', woo_product_id: 9603, woo_variation_id: 77, phone: '5512345678', consent: 'yes' }), env,
    fakeFetch({ f360_stock_intent_create: { ok: false, code: 'consent', error: 'Marca la casilla para que te podamos avisar.' } }, calls));
  assert.equal(calls[0].args.p_consent, false); assert.equal(r.status, 400);
});
test('notify_me honeypot → ok without calling the database', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const r = await handleStorefront(post({ action: 'notify_me', woo_product_id: 1, woo_variation_id: 2, website: 'spam' }), env, fakeFetch({}, calls));
  assert.equal(r.status, 200); assert.equal(calls.length, 0);
});
test('unconfigured channel → 500 (fail closed)', async () => {
  const r = await handleStorefront(post({ action: 'promise', woo_product_id: 1 }), { ...env, TARGET_KEY: '' }, fakeFetch({}));
  assert.equal(r.status, 500);
});

test('promise_lines: validated ids → same rule per line; channel from config', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const data = { market: 'MX', lines: { '10': { case: 'made_to_order', headline: 'Producción: 10 días hábiles' } } };
  const r = await handleStorefront(post({ action: 'promise_lines', woo_variation_ids: [10, 11], market: 'MX' }), env, fakeFetch({ f360_storefront_promise_lines: data }, calls));
  assert.deepEqual(await r.json(), data);
  assert.deepEqual(calls[0].args.p_woo_variation_ids, [10, 11]); assert.equal(calls[0].args.p_target_key, 'woo_staging4');
  const bad = await handleStorefront(post({ action: 'promise_lines', woo_variation_ids: ['x'] }), env, fakeFetch({}));
  assert.equal(bad.status, 400);
});
test('server key: Hilo can read promises without a browser Origin, but cannot register intents', async () => {
  const key = 'k'.repeat(32), e2 = { ...env, SERVER_KEY: key };
  const ok = await handleStorefront(post({ action: 'promise', woo_product_id: 5 }, '', { 'x-f360-key': key }), e2, fakeFetch({ f360_storefront_promise: { variations: {} } }));
  assert.equal(ok.status, 200);
  const wrong = await handleStorefront(post({ action: 'promise', woo_product_id: 5 }, '', { 'x-f360-key': 'k'.repeat(31) + 'x' }), e2, fakeFetch({}));
  assert.equal(wrong.status, 403);
  const notify = await handleStorefront(post({ action: 'notify_me', woo_product_id: 5, woo_variation_id: 6, phone: '5512345678', consent: true }, '', { 'x-f360-key': key }), e2, fakeFetch({}));
  assert.equal(notify.status, 403);
});
test('review_sync (CRO-3B1): server key only; browsers are refused', async () => {
  const r = await handleStorefront(post({ action: 'review_sync', review: { woo_review_id: 1, woo_product_id: 2, rating: 5 } }), env, fakeFetch({}));
  assert.equal(r.status, 403);
});
test('review_sync forwards only the allowed shape: no text/author, hash normalized, junk claims dropped', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const senv = { ...env, SERVER_KEY: 'k'.repeat(32) };
  const hash = 'AB'.repeat(32);
  const r = await handleStorefront(new Request('https://f/x', { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-f360-key': 'k'.repeat(32) },
    body: JSON.stringify({ action: 'review_sync', review: { woo_review_id: 163, woo_product_id: 937, rating: 5, status: 'approved', media_count: 1,
      reviewed_at: '2026-07-31T10:00:00Z', content: 'texto', author: 'Ana', email: 'ana@example.com',
      claims: { woo_order_ids: [123, 'x', -1], email_sha256: hash, woo_user_id: 'abc', email: 'ana@example.com' } } }) }),
    senv, fakeFetch({ f360_review_sync: { ok: true, verification: 'UNVERIFIED' } }, calls));
  assert.equal(r.status, 200);
  const p = calls[0].args.p_review as Record<string, unknown>;
  assert.equal(calls[0].args.p_target_key, 'woo_staging4');
  assert.deepEqual(Object.keys(p).sort(), ['claims', 'media_count', 'rating', 'reviewed_at', 'status', 'woo_product_id', 'woo_review_id', 'woo_verified']);
  assert.deepEqual(p.claims, { woo_order_ids: [123], email_sha256: hash.toLowerCase(), woo_user_id: null });
  assert.ok(!JSON.stringify(calls[0].args).includes('@'));
});
test('review_sync: invalid rating → 400 without calling the database', async () => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const senv = { ...env, SERVER_KEY: 'k'.repeat(32) };
  const r = await handleStorefront(new Request('https://f/x', { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-f360-key': 'k'.repeat(32) },
    body: JSON.stringify({ action: 'review_sync', review: { woo_review_id: 1, woo_product_id: 2, rating: 9 } }) }), senv, fakeFetch({}, calls));
  assert.equal(r.status, 400); assert.equal(calls.length, 0);
});
