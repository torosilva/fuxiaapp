import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleReserve, normalizePhone } from '../handler.ts';

const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'svc', ALLOWED_ORIGINS: 'https://staging4.fuxiaballerinas.com', TEST_PHONES: '+15550100099', TEST_CODE: '246810', TARGET_KEY: 'woo_staging4' };
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
  // the channel comes from configuration: a browser-sent target_key is ignored
  const c3: any[] = [];
  await handleReserve(post({ action: 'a_la_medida', phone: '55 1234 5678', name: 'Ana', color: 'Verde', target_key: 'woo_production' }), env,
    fakeFetch({ f360_custom_request_create: { id: 'y', product: 'Botas' } }, c3));
  assert.equal(c3[0].args.p.target_key, 'woo_staging4');
  r = await handleReserve(post({ action: 'a_la_medida', phone: '55 1234 5678', name: 'Ana', color: 'Verde' }), { ...env, TARGET_KEY: '' }, fakeFetch({}));
  assert.equal(r.status, 500);                                    // unconfigured channel → fail closed
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
  assert.equal(calls[0].args.p_target_key, 'woo_staging4');       // from configuration
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
test('scarcity: boolean only; errors and bad input fail closed', async () => {
  let r = await handleReserve(post({ action: 'scarcity', woo_variation_id: 3733 }), env, fakeFetch({ f360_scarcity_state: { reliable: true } }));
  assert.deepEqual(await r.json(), { reliable: true });
  r = await handleReserve(post({ action: 'scarcity', woo_variation_id: 3733 }), env, fakeFetch({ f360_scarcity_state: new Error('x') }));
  assert.deepEqual(await r.json(), { reliable: false });
  r = await handleReserve(post({ action: 'scarcity', woo_variation_id: 'abc' }), env, fakeFetch({}));
  assert.deepEqual(await r.json(), { reliable: false });
});
test('contacto: completes the Hilo case of the conversation with name + phone', async () => {
  const calls: any[] = [];
  const r = await handleReserve(post({ action: 'contacto', conversation_id: 'conv1', name: 'Ana', phone: '55 1234 5678', product_name: 'Botas' }), env, fakeFetch({ f360_case_upsert: { id: 'c1' } }, calls));
  assert.deepEqual(await r.json(), { ok: true });
  assert.equal(calls[0].args.p.conversation_id, 'conv1'); assert.equal(calls[0].args.p.phone, '+525512345678');
  assert.equal((await handleReserve(post({ action: 'contacto', name: 'Ana', phone: '55 1234 5678' }), env, fakeFetch({}))).status, 400);
});

// "Link de pago" (checkout rescue): Woo prices the order; the browser sends only ids/quantities.
const wooEnv = { ...env, WOO_BASE_URL: 'https://staging4.fuxiaballerinas.com', WOO_USER: 'u', WOO_SECRET: 's' };
function payFetch(wooAnswers: { status: number; body: unknown }[], calls: { url: string; body: any }[] = []) {
  return (async (url: string, init: RequestInit) => {
    const body = init.body ? JSON.parse(String(init.body)) : null; calls.push({ url: String(url), body });
    if (String(url).includes('/rpc/f360_pay_link_open')) return new Response(JSON.stringify({ id: 'case-1' }), { status: 200 });
    if (String(url).includes('/rpc/')) return new Response('null', { status: 200 });
    const a = wooAnswers.shift()!; return new Response(JSON.stringify(a.body), { status: a.status });
  }) as unknown as typeof fetch;
}
const payBody = { action: 'pay_link', country: 'mx', name: 'Ana López', phone: '5512345678', email: 'ana@x.mx',
  items: [{ id: 3729, quantity: 1, price: 1 }], coupons: ['BIENVENIDA10'], address: { address_1: 'Calle 1', city: 'CDMX', postcode: '01000' } };
test('pay_link: creates a pending Woo order from ids/quantities only and returns the /mx/ payment page', async () => {
  const calls: { url: string; body: any }[] = [];
  const r = await handleReserve(post(payBody), wooEnv, payFetch([{ status: 201, body: { id: 4200, total: '3780', currency_symbol: '$',
    payment_url: 'https://staging4.fuxiaballerinas.com/finalizar-compra/order-pay/4200/?pay_for_order=true&key=wc_order_x' } }], calls));
  const j = await r.json();
  assert.equal(r.status, 200);
  assert.equal(j.url, 'https://staging4.fuxiaballerinas.com/mx/finalizar-compra/order-pay/4200/?pay_for_order=true&key=wc_order_x');
  assert.equal(j.order, 4200);
  const woo = calls.find((c) => c.url.endsWith('/wp-json/wc/v3/orders'))!;
  assert.equal(woo.body.status, 'pending'); assert.equal(woo.body.set_paid, false);
  assert.deepEqual(woo.body.line_items, [{ product_id: 3729, quantity: 1 }]);           // no price from the browser
  assert.deepEqual(woo.body.coupon_lines, [{ code: 'BIENVENIDA10' }]);
  assert.equal(woo.body.billing.phone, '+525512345678'); assert.equal(woo.body.billing.first_name, 'Ana'); assert.equal(woo.body.billing.last_name, 'López');
  assert.ok(calls.some((c) => c.url.includes('/rpc/f360_pay_link_done') && c.body.p_order === 4200));
});
test('pay_link: a coupon Woo rejects is dropped instead of blocking the link', async () => {
  const calls: { url: string; body: any }[] = [];
  const r = await handleReserve(post(payBody), wooEnv, payFetch([{ status: 400, body: { message: 'Cupón no válido' } },
    { status: 201, body: { id: 4201, total: '4200', payment_url: 'https://staging4.fuxiaballerinas.com/finalizar-compra/order-pay/4201/?key=k' } }], calls));
  assert.equal(r.status, 200);
  const woo = calls.filter((c) => c.url.endsWith('/wp-json/wc/v3/orders'));
  assert.equal(woo.length, 2); assert.deepEqual(woo[1].body.coupon_lines, []);
});
test('pay_link: refused outside Mexico, without e-mail, with empty cart, or when the DB limit is hit', async () => {
  assert.equal((await handleReserve(post({ ...payBody, country: 'co' }), wooEnv, payFetch([]))).status, 400);
  assert.equal((await handleReserve(post({ ...payBody, email: 'x' }), wooEnv, payFetch([]))).status, 400);
  assert.equal((await handleReserve(post({ ...payBody, items: [{ id: -1, quantity: 99 }] }), wooEnv, payFetch([]))).status, 400);
  const lim = (async (url: string) => String(url).includes('/rpc/f360_pay_link_open')
    ? new Response(JSON.stringify({ message: 'Ya te generamos links hoy.' }), { status: 400 }) : new Response('{}', { status: 500 })) as unknown as typeof fetch;
  const r = await handleReserve(post(payBody), wooEnv, lim);
  assert.equal(r.status, 429); assert.match((await r.json()).error, /links hoy/);
});
test('pay_link: Woo down → friendly error and the case records the failure', async () => {
  const calls: { url: string; body: any }[] = [];
  const r = await handleReserve(post({ ...payBody, coupons: [] }), wooEnv, payFetch([{ status: 500, body: { message: 'boom' } }], calls));
  assert.equal(r.status, 502);
  assert.ok(calls.some((c) => c.url.includes('/rpc/f360_pay_link_done') && c.body.p_error === 'boom'));
});
