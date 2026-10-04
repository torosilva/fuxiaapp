// G1 Commerce Facts — whitelist, attribution, refunds, poll and webhook wiring (no network, no database).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { browserClass, commercePoll, orderAttribution, orderEconomics, refundDetail, type CommerceWoo } from '../commerce.ts';
import { handleOrders } from '../../../f360-woo-orders/handler.ts';

const UA_IG = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22F76 Instagram 400.0.0';
const fullOrder = () => ({
  id: 501, status: 'completed', created_via: 'store-api', currency: 'MXN', prices_include_tax: false,
  date_created_gmt: '2026-08-01T10:00:00', date_paid_gmt: '2026-08-01T10:05:00', date_completed_gmt: '2026-08-02T10:00:00', date_modified_gmt: '2026-08-02T10:00:00',
  discount_total: '280', discount_tax: '0', shipping_total: '200', shipping_tax: '0', cart_tax: '0', total: '2720', total_tax: '0',
  payment_method: 'woo-mercado-pago-custom', payment_method_title: 'Tarjeta', transaction_id: 'MP-SECRET-1', customer_id: 77,
  customer_ip_address: '201.1.2.3', customer_user_agent: UA_IG, customer_note: 'déjalo con el portero', order_key: 'wc_order_SECRETKEY',
  billing: { first_name: 'Ana', last_name: 'Pérez', email: 'ana@example.com', phone: '5512345678', address_1: 'Calle 1', city: 'CDMX', postcode: '01000', country: 'MX' },
  shipping: { first_name: 'Ana', address_1: 'Calle 1', country: 'MX' },
  line_items: [{ id: 11, name: 'Paula Gamuza Vino', product_id: 100, variation_id: 101, sku: 'BALL-PAULA', quantity: 1, price: 2520,
    subtotal: '2800', subtotal_tax: '0', total: '2520', total_tax: '0',
    meta_data: [{ key: 'pa_medida', value: '37' }, { key: '_advanced_woo_discount_item_total_discount', value: { initial_price: 3200, discounted_price: 2800 } }] }],
  shipping_lines: [{ method_id: 'flat_rate', total: '200', total_tax: '0' }],
  fee_lines: [{ name: 'Comisión', total: '50', total_tax: '8' }],
  coupon_lines: [{ code: 'ANA10', discount: '280', discount_tax: '0' }],
  refunds: [{ id: 900, reason: 'La clienta Ana pidió cambio', total: '-500' }],
  meta_data: [
    { key: '_wc_order_attribution_source_type', value: 'utm' }, { key: '_wc_order_attribution_source_type', value: 'admin' },
    { key: '_wc_order_attribution_utm_source', value: 'ig' }, { key: '_wc_order_attribution_utm_medium', value: 'paid' },
    { key: '_wc_order_attribution_utm_campaign', value: '120251089837130626' }, { key: '_wc_order_attribution_utm_id', value: '120251089837130626' },
    { key: '_wc_order_attribution_referrer', value: 'https://l.instagram.com/?u=https%3A%2F%2Fx&e=SECRET' },
    { key: '_wc_order_attribution_session_entry', value: 'https://staging4.fuxiaballerinas.com/mx/producto/paula/?fbclid=SECRETCLICK' },
    { key: '_wc_order_attribution_session_start_time', value: '2026-08-01 09:55:00' },
    { key: '_wc_order_attribution_session_pages', value: '7' }, { key: '_wc_order_attribution_session_count', value: '1' },
    { key: '_wc_order_attribution_device_type', value: 'Mobile' }, { key: '_wc_order_attribution_user_agent', value: UA_IG },
    { key: '_meta_purchase_tracked_server', value: '1' }, { key: '_meta_event_id', value: 'abcd-meta-event' },
    { key: '_ivole_cr_consent', value: 'no' },
  ],
});

test('economics payload is a strict whitelist: no PII, no Meta metadata, no notes / reasons / coupon codes / raw UA', () => {
  const s = JSON.stringify(orderEconomics(fullOrder()));
  for (const bad of ['Ana', 'Pérez', 'ana@example.com', '5512345678', 'Calle 1', '01000', '201.1.2.3', 'portero', 'SECRETKEY', 'MP-SECRET-1',
    'ANA10', 'pidió cambio', 'abcd-meta-event', '_meta_', 'Instagram 400', 'fbclid', 'SECRETCLICK', 'e=SECRET', 'Paula Gamuza Vino', 'payment_method_title', 'ivole'])
    assert.ok(!s.includes(bad), `leaked: ${bad}`);
});

test('economics payload keeps the money, ids, country code and the implicit WDR price as a secondary hint', () => {
  const e = orderEconomics(fullOrder()) as Record<string, any>;
  assert.equal(e.total, '2720'); assert.equal(e.discount_total, '280'); assert.equal(e.shipping_total, '200');
  assert.equal(e.fees_total, 50); assert.equal(e.fees_tax, 8); assert.equal(e.coupon_count, 1);
  assert.equal(e.billing_country, 'MX'); assert.equal(e.woo_customer_id, 77); assert.equal(e.created_via, 'store-api');
  assert.deepEqual(e.line_items[0], { id: 11, product_id: 100, variation_id: 101, sku: 'BALL-PAULA', quantity: 1, subtotal: '2800', subtotal_tax: '0',
    total: '2520', total_tax: '0', list_price_hint: 3200, list_price_source: 'wdr_initial_price' });
  assert.deepEqual(e.refunds, [{ id: 900, amount: 500, created_at: null, detail: false }]);   // header-only until the detail is read
});

test('attribution: first non-admin source_type, referrer host only, landing path without query, UA reduced to classes', () => {
  const a = orderAttribution(fullOrder()) as Record<string, unknown>;
  assert.equal(a.source_type, 'utm'); assert.equal(a.utm_campaign, '120251089837130626');
  assert.equal(a.referrer_host, 'l.instagram.com'); assert.equal(a.session_entry_path, '/mx/producto/paula/');
  assert.equal(a.browser_class, 'instagram_iab'); assert.equal(a.os_class, 'ios'); assert.equal(a.session_pages, '7');
  assert.equal(orderAttribution({ meta_data: [] }), null, 'API-created order without attribution → null');
  assert.deepEqual(browserClass('Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/128.0 Mobile Safari/537.36'), { browser_class: 'chrome', os_class: 'android' });
  assert.deepEqual(browserClass('Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) [FBAN/FBIOS;FBAV/480.0]'), { browser_class: 'facebook_iab', os_class: 'ios' });
});

test('refund detail: Woo negatives → positive amounts, line link through _refunded_item_id, shipping and tax split, no reason', () => {
  const d = refundDetail({ id: 900, amount: '500.00', reason: 'secreto', date_created_gmt: '2026-08-03T10:00:00',
    line_items: [{ id: 1, quantity: -1, total: '-431.03', total_tax: '-68.97', meta_data: [{ key: '_refunded_item_id', value: '11' }] }],
    shipping_lines: [] });
  assert.deepEqual(d, { id: 900, amount: 500, created_at: '2026-08-03T10:00:00', detail: true, product_amount: 431.03, shipping_amount: 0, tax_amount: 68.97,
    lines: [{ woo_line_id: 11, quantity: 1, total: 431.03, total_tax: 68.97 }] });
  assert.ok(!JSON.stringify(d).includes('secreto'));
  const e = orderEconomics(fullOrder(), [d]) as Record<string, any>;
  assert.equal(e.refunds[0].detail, true, 'a detailed refund replaces the header-only one');
});

function fakeRpc(results: Record<string, unknown>, calls: { fn: string; args: Record<string, unknown> }[], fail: Set<string> = new Set()) {
  return async <T>(fn: string, args: Record<string, unknown>): Promise<T> => {
    calls.push({ fn, args });
    if (fail.has(fn)) throw new Error(`${fn} failed`);
    const r = results[fn]; return (typeof r === 'function' ? (r as (a: unknown) => unknown)(args) : r) as T;
  };
}

test('poll: pages Woo, reads refund detail only when needed, captures each order, closes the run with the newest cursor', async () => {
  const pages: Record<number, unknown[]> = { 1: [fullOrder(), { ...fullOrder(), id: 502, refunds: [], date_modified_gmt: '2026-08-03T11:00:00' }] };
  let refundReads = 0;
  const woo: CommerceWoo = { listOrders: async (_a, p) => (pages[p] ?? []) as Record<string, unknown>[], listRefunds: async () => { refundReads++; return [{ id: 900, amount: '500', line_items: [] }]; } };
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = fakeRpc({ f360_commerce_run_begin: { run_id: 7, modified_after: null }, f360_capture_order_economics: { result: 'inserted', refunds: 1 }, f360_commerce_run_end: { ok: true } }, calls);
  const out = await commercePoll(rpc, woo, 'woo_staging4', 'backfill');
  assert.equal(out.ok, true); assert.equal(out.stats.fetched, 2); assert.equal(out.stats.inserted, 2); assert.equal(refundReads, 1);
  const end = calls.find((c) => c.fn === 'f360_commerce_run_end')!;
  assert.equal(end.args.p_cursor, '2026-08-03T11:00:00Z'); assert.equal(end.args.p_ok, true);
  assert.ok(calls.filter((c) => c.fn === 'f360_capture_order_economics').every((c) => c.args.p_via === 'backfill'));
});

test('poll: a Woo failure closes the run as failed (no cursor move → source becomes STALE, never silently fresh)', async () => {
  const woo: CommerceWoo = { listOrders: async () => { throw new Error('Woo HTTP 503'); }, listRefunds: async () => [] };
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc = fakeRpc({ f360_commerce_run_begin: { run_id: 8, modified_after: '2026-08-01T00:00:00Z' }, f360_commerce_run_end: { ok: false } }, calls);
  const out = await commercePoll(rpc, woo, 'woo_staging4', 'poll');
  assert.equal(out.ok, false);
  const end = calls.find((c) => c.fn === 'f360_commerce_run_end')!;
  assert.equal(end.args.p_ok, false); assert.equal(end.args.p_cursor, null); assert.match(String(end.args.p_error), /503/);
});

const SECRET = 'test-webhook-secret';
const signed = (body: string) => createHmac('sha256', SECRET).update(body).digest('base64');
const env = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', WOO_TARGET_KEY: 'woo_staging4', WOO_WEBHOOK_SECRET: SECRET };
const req = (body: string) => new Request('http://x', { method: 'POST', body, headers: { 'x-wc-webhook-topic': 'order.updated', 'x-wc-webhook-delivery-id': 'd1', 'x-wc-webhook-signature': signed(body) } });

test('webhook: inventory ingest receives ONLY the minimal order; commerce capture receives the whitelisted economics', async (t) => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    const fn = String(url).split('/rpc/')[1]; const args = JSON.parse(String(init.body)); calls.push({ fn, args });
    const body = fn === 'f360_ingest_woo_order' ? { result: 'applied' } : { result: 'inserted', refunds: 1 };
    return new Response(JSON.stringify(body), { status: 200 });
  }) as typeof fetch;
  t.after(() => { globalThis.fetch = realFetch; });
  const body = JSON.stringify(fullOrder());
  const res = await handleOrders(req(body), env, { commerceWoo: { listOrders: async () => [], listRefunds: async () => [{ id: 900, amount: '500', line_items: [] }] } });
  const out = await res.json();
  assert.equal(res.status, 200); assert.equal(out.result, 'applied'); assert.equal(out.commerce, 'inserted');
  assert.deepEqual(calls.map((c) => c.fn), ['f360_ingest_woo_order', 'f360_capture_order_economics']);
  const ingest = JSON.stringify(calls[0].args.p_order);
  assert.ok(!ingest.includes('2720') && !ingest.includes('utm'), 'inventory payload unchanged (no money, no attribution)');
  const cap = calls[1].args as Record<string, any>;
  assert.equal(cap.p_via, 'webhook'); assert.equal(cap.p_order.refunds[0].detail, true);
  assert.ok(!JSON.stringify(cap).includes('ana@example.com'));
});

test('webhook: a commerce capture failure answers 5xx so Woo retries (the inventory step is idempotent)', async (t) => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string) => {
    const fn = String(url).split('/rpc/')[1];
    return fn === 'f360_ingest_woo_order' ? new Response(JSON.stringify({ result: 'applied' }), { status: 200 }) : new Response(JSON.stringify({ message: 'boom' }), { status: 500 });
  }) as typeof fetch;
  t.after(() => { globalThis.fetch = realFetch; });
  const res = await handleOrders(req(JSON.stringify({ ...fullOrder(), refunds: [] })), env, { commerceWoo: null });
  assert.equal(res.status, 500);
});
