import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleReserve, normalizePhone } from '../handler.ts';

const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', ALLOWED_ORIGINS: 'https://staging4.fuxiaballerinas.com', TEST_PHONES: '+15550100099', TEST_CODE: '246810' };
const ORIGIN = 'https://staging4.fuxiaballerinas.com';
function fakeFetch(answers: Record<string, unknown>, calls: { fn: string; args: unknown }[] = []) {
  return (async (url: string, init: RequestInit) => {
    const fn = String(url).split('/rpc/')[1];
    calls.push({ fn, args: JSON.parse(String(init.body)) });
    const a = answers[fn];
    return new Response(JSON.stringify(a instanceof Error ? { message: a.message } : a), { status: a instanceof Error ? 400 : 200 });
  }) as unknown as typeof fetch;
}
const post = (body: unknown, origin = ORIGIN) => new Request('https://f/x', { method: 'POST', headers: { Origin: origin, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('phones: Mexican 10 digits → +52; international kept', () => {
  assert.equal(normalizePhone('55 1234 5678'), '+525512345678');
  assert.equal(normalizePhone('+1 555 010 0099'), '+15550100099');
  assert.equal(normalizePhone('123'), null);
});
test('only the store origin may call it (CORS)', async () => {
  const r = await handleReserve(post({ action: 'availability', woo_variation_id: 1 }, 'https://evil.example'), env, fakeFetch({}));
  assert.equal(r.status, 403);
});
test('availability returns store names only', async () => {
  const r = await handleReserve(post({ action: 'availability', woo_variation_id: 315 }), env, fakeFetch({ f360_store_availability: { variant_id: 'v', stores: [{ location_id: 'l', name: 'Tienda Polanco' }] } }));
  assert.deepEqual(await r.json(), { stores: [{ location_id: 'l', name: 'Tienda Polanco' }] });
  assert.equal(r.headers.get('Access-Control-Allow-Origin'), ORIGIN);
});
test('send_code: unknown / not Gold / not a test phone are refused; Gold test phone ok (nothing sent)', async () => {
  assert.equal((await handleReserve(post({ action: 'send_code', phone: '+15550100099' }), env, fakeFetch({ f360_gold_check: { exists: false, gold: false } }))).status, 404);
  assert.equal((await handleReserve(post({ action: 'send_code', phone: '+15550100099' }), env, fakeFetch({ f360_gold_check: { exists: true, gold: false } }))).status, 403);
  const real = await handleReserve(post({ action: 'send_code', phone: '5512345678' }), env, fakeFetch({ f360_gold_check: { exists: true, gold: true } }));
  assert.equal(real.status, 403); assert.match((await real.json()).error, /en pruebas/);
  const ok = await handleReserve(post({ action: 'send_code', phone: '+15550100099' }), env, fakeFetch({ f360_gold_check: { exists: true, gold: true, first_name: 'Ana' } }));
  assert.deepEqual(await ok.json(), { sent: true, first_name: 'Ana', test: true });
});
test('reserve: wrong code refused before touching the database; right code reserves', async () => {
  const calls: { fn: string; args: unknown }[] = [];
  const bad = await handleReserve(post({ action: 'reserve', phone: '+15550100099', code: '000000', woo_variation_id: 315, location_id: 'l' }), env, fakeFetch({}, calls));
  assert.equal(bad.status, 401); assert.equal(calls.length, 0);
  const ok = await handleReserve(post({ action: 'reserve', phone: '+15550100099', code: '246810', woo_variation_id: 315, location_id: 'l' }), env,
    fakeFetch({ f360_store_availability: { variant_id: 'v315', stores: [] }, f360_reserve_for_phone: { id: 'r', store: 'Tienda Polanco', variant: 'X', expires_at: 't' } }, calls));
  assert.equal(ok.status, 200);
  assert.deepEqual(calls.at(-1), { fn: 'f360_reserve_for_phone', args: { p_phone: '+15550100099', p_location_id: 'l', p_variant_id: 'v315' } });
});
test('a la medida: any phone leaves a request (validated); honeypot ignored', async () => {
  const calls: { fn: string; args: any }[] = [];
  let r = await handleReserve(post({ action: 'a_la_medida', phone: '55 1234 5678', name: 'Ana <b>', color: 'Verde', size: '25', woo_product_id: 145, product_name: 'Botas' }), env,
    fakeFetch({ f360_custom_request_create: { id: 'x', product: 'Botas Largas' } }, calls));
  assert.deepEqual(await r.json(), { ok: true, product: 'Botas Largas' });
  assert.equal(calls[0].args.p.phone, '+525512345678'); assert.equal(calls[0].args.p.name, 'Ana b');
  r = await handleReserve(post({ action: 'a_la_medida', phone: '55 1234 5678', name: 'Ana', color: '' }), env, fakeFetch({}));
  assert.equal(r.status, 400);
  const c2: any[] = [];
  r = await handleReserve(post({ action: 'a_la_medida', phone: '55 1234 5678', name: 'x', color: 'y', website: 'spam' }), env, fakeFetch({}, c2));
  assert.equal(c2.length, 0);
});
test('catalog: availability states for the shop page, store origin only', async () => {
  const calls: any[] = [];
  const r = await handleReserve(post({ action: 'catalog' }), env, fakeFetch({ f360_storefront_catalog: { items: [{ woo_product_id: 1, name: 'X', colors: [] }] } }, calls));
  assert.deepEqual((await r.json()).items[0].name, 'X');
  assert.equal((await handleReserve(post({ action: 'catalog' }, 'https://evil.example'), env, fakeFetch({}))).status, 403);
});
test('search_log: records the term only (short terms ignored)', async () => {
  const calls: any[] = [];
  await handleReserve(post({ action: 'search_log', term: 'botas <b>', country: 'mx' }), env, fakeFetch({ f360_log_search: null }, calls));
  assert.deepEqual(calls[0].args, { p_term: 'botas b', p_country: 'mx' });
  const c2: any[] = [];
  await handleReserve(post({ action: 'search_log', term: 'ab' }), env, fakeFetch({}, c2));
  assert.equal(c2.length, 0);
});
