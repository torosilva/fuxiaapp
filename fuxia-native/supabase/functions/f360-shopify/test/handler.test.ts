// f360-shopify — translation of Shopify orders to the Woo shape + webhook authenticity (no network, no database).
// Run: node --test fuxia-native/supabase/functions/f360-shopify/test/handler.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { gmt, refundDetails, toWooOrder, wooStatus } from '../../_shared/f360-shopify/orders.ts';
import { handleShopify } from '../handler.ts';

const SECRET = 'shpss_test';
const SHOP = 'z9fdqc-0z.myshopify.com';
const env = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', SHOPIFY_SHOP: SHOP, SHOPIFY_CLIENT_SECRET: SECRET, SHOPIFY_TARGET_KEY: 'shopify_mx' };
const sign = (body: string, secret = SECRET) => createHmac('sha256', secret).update(body).digest('base64');

const order = (over: Record<string, unknown> = {}) => ({
  id: 6612345678901, name: '#1002', order_number: 1002, test: false, email: 'ana@example.com', phone: null,
  created_at: '2026-11-09T10:21:00-06:00', updated_at: '2026-11-09T10:25:00-06:00', processed_at: '2026-11-09T10:21:05-06:00',
  cancelled_at: null, closed_at: null, currency: 'MXN', taxes_included: true,
  financial_status: 'paid', fulfillment_status: null, source_name: 'web',
  total_price: '5400.00', total_discounts: '280.00', total_tax: '744.83',
  landing_site: '/products/ballerinas-resorte-taches?utm_source=ig&utm_medium=paid&utm_campaign=otono&fbclid=SECRET',
  referring_site: 'https://l.instagram.com/',
  payment_gateway_names: ['shopify_payments'],
  customer: { id: 7788, email: 'ana@example.com', phone: '+525512345678', first_name: 'Ana', last_name: 'Pérez' },
  billing_address: { first_name: 'Ana', last_name: 'Pérez', address1: 'Bosques 405', address2: 'Del Valle', city: 'San Pedro', province_code: 'NL', zip: '66250', country_code: 'MX', phone: '+525512345678' },
  shipping_address: { first_name: 'Ana', last_name: 'Pérez', address1: 'Bosques 405', address2: 'Del Valle', city: 'San Pedro', province_code: 'NL', zip: '66250', country_code: 'MX', phone: null },
  discount_codes: [{ code: 'BIENVENIDA10', amount: '280.00' }],
  shipping_lines: [{ price: '0.00', discount_allocations: [], tax_lines: [] }],
  line_items: [
    { id: 111, product_id: 10305693941830, variant_id: 50958118649926, sku: 'BALLERINAS-RESORTE-TACHES-TAUPE-37', title: 'Twin Studs', variant_title: 'Taupe / 37',
      quantity: 1, price: '2800.00', discount_allocations: [{ amount: '280.00' }], tax_lines: [{ price: '347.59' }] },
    { id: 112, product_id: 10305693941831, variant_id: 50958118649927, sku: 'PAULA-TAUPE-39', title: 'Paula', variant_title: 'Taupe / 39',
      quantity: 1, price: '2880.00', discount_allocations: [], tax_lines: [{ price: '397.24' }] },
  ],
  refunds: [],
  ...over,
});

test('status: paid → processing (completed once fulfilled); refunds, cancellations and uncaptured money never count as a paid sale', () => {
  assert.equal(wooStatus(order()), 'processing');
  assert.equal(wooStatus(order({ fulfillment_status: 'fulfilled' })), 'completed');
  assert.equal(wooStatus(order({ financial_status: 'partially_refunded' })), 'processing');
  assert.equal(wooStatus(order({ financial_status: 'refunded', cancelled_at: '2026-11-10T00:00:00Z' })), 'refunded');
  assert.equal(wooStatus(order({ cancelled_at: '2026-11-10T00:00:00Z', financial_status: 'voided' })), 'cancelled');
  assert.equal(wooStatus(order({ financial_status: 'authorized' })), 'on-hold');
  assert.equal(wooStatus(order({ financial_status: 'pending' })), 'pending');
  assert.equal(wooStatus(order({ financial_status: 'expired' })), 'failed');
});

test('dates: Shopify offsets become UTC without offset (the database reads _gmt as UTC)', () => {
  assert.equal(gmt('2026-11-09T10:21:00-06:00'), '2026-11-09T16:21:00');
  assert.equal(gmt(null), '');
});

test('order → Woo shape: Shopify ids kept, raw amounts, discounts per line, address codes, attribution path only', () => {
  const w = toWooOrder(order()) as Record<string, any>;
  assert.equal(w.id, 6612345678901); assert.equal(w.number, '1002'); assert.equal(w.status, 'processing');
  assert.equal(w.created_via, 'checkout'); assert.equal(w.currency, 'MXN'); assert.equal(w.prices_include_tax, true);
  assert.equal(w.date_paid_gmt, '2026-11-09T16:21:05'); assert.equal(w.date_modified_gmt, '2026-11-09T16:25:00');
  assert.equal(w.total, '5400.00'); assert.equal(w.discount_total, '280.00'); assert.equal(w.shipping_total, '0.00');
  assert.equal(w.payment_method, 'shopify_payments'); assert.equal(w.customer_id, 7788);
  assert.equal(w.line_items[0].variation_id, 50958118649926); assert.equal(w.line_items[0].subtotal, '2800.00'); assert.equal(w.line_items[0].total, '2520.00');
  assert.equal(w.line_items[1].total, '2880.00');
  assert.equal(w.billing.state, 'NL'); assert.equal(w.billing.postcode, '66250'); assert.equal(w.billing.country, 'MX');
  assert.equal(w.billing.phone, '+525512345678'); assert.equal(w.shipping.phone, '+525512345678', 'shipping without phone falls back to the order/customer phone');
  const meta = Object.fromEntries(w.meta_data.map((m: any) => [m.key.replace('_wc_order_attribution_', ''), m.value]));
  assert.equal(meta.source_type, 'utm'); assert.equal(meta.utm_source, 'ig'); assert.equal(meta.utm_campaign, 'otono');
  assert.equal(meta.session_entry, 'https://mx.fuxiaballerinas.com/products/ballerinas-resorte-taches');
  assert.ok(!JSON.stringify(w.meta_data).includes('fbclid'), 'never the query string beyond utm_*');
});

test('unpaid order: no paid date; draft order from the admin is a manual sale', () => {
  const w = toWooOrder(order({ financial_status: 'pending', source_name: 'shopify_draft_order' })) as Record<string, any>;
  assert.equal(w.status, 'pending'); assert.equal(w.date_paid_gmt, ''); assert.equal(w.created_via, 'admin');
});

test('refunds come with their detail from the order itself (line, quantity, amount, shipping)', () => {
  const r = refundDetails(order({ refunds: [{ id: 900, created_at: '2026-11-10T09:00:00-06:00',
    refund_line_items: [{ line_item_id: 111, quantity: 1, subtotal: 2520, total_tax: 347.59 }],
    transactions: [{ kind: 'refund', status: 'success', amount: '2520.00' }, { kind: 'refund', status: 'failure', amount: '99.00' }],
    order_adjustments: [{ kind: 'shipping_refund', amount: '-150.00' }] }] }));
  assert.deepEqual(r[0], { id: 900, amount: 2520, created_at: '2026-11-10T15:00:00', detail: true, product_amount: 2520, shipping_amount: 150, tax_amount: 347.59,
    lines: [{ woo_line_id: 111, quantity: 1, total: 2520, total_tax: 347.59 }] });
});

const req = (body: string, h: Record<string, string> = {}) => new Request('http://x', { method: 'POST', body, headers: {
  'x-shopify-topic': 'orders/updated', 'x-shopify-webhook-id': 'wh-1', 'x-shopify-shop-domain': SHOP, 'x-shopify-hmac-sha256': sign(body), ...h } });

function stubRpc(t: { after: (fn: () => void) => void }) {
  const calls: { fn: string; args: Record<string, any> }[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    const fn = String(url).split('/rpc/')[1]; calls.push({ fn, args: JSON.parse(String(init.body)) });
    if (fn === 'f360_shopify_localize') {   // the database swaps Shopify ids for link ids (here: variant → 7, product → 3)
      const o = calls.at(-1)!.args.p_order;
      return new Response(JSON.stringify({ ...o, line_items: o.line_items.map((l: any) => ({ ...l, shopify_variant_id: l.variation_id, variation_id: 7, product_id: 3 })) }), { status: 200 });
    }
    const body = fn === 'f360_ingest_woo_order' ? { result: 'applied' } : fn === 'f360_capture_order_shipping' ? { result: 'saved' }
      : fn === 'f360_web_order_loyalty' ? { result: 'registered' } : { result: 'inserted' };
    return new Response(JSON.stringify(body), { status: 200 });
  }) as typeof fetch;
  t.after(() => { globalThis.fetch = realFetch; });
  return calls;
}

test('webhook: a signed order from our shop goes through the same four steps as a Woo order, under the Shopify channel', async (t) => {
  const calls = stubRpc(t);
  const res = await handleShopify(req(JSON.stringify(order())), env);
  const out = await res.json();
  assert.equal(res.status, 200); assert.equal(out.result, 'applied'); assert.equal(out.loyalty, 'registered');
  assert.deepEqual(calls.map((c) => c.fn), ['f360_shopify_localize', 'f360_ingest_woo_order', 'f360_capture_order_economics', 'f360_capture_order_shipping', 'f360_web_order_loyalty']);
  assert.ok(calls.every((c) => c.args.p_target_key === 'shopify_mx'));
  assert.equal(calls[0].args.p_order.line_items[0].variation_id, 50958118649926, 'localize receives Shopify ids');
  assert.deepEqual(calls[1].args.p_delivery, { delivery_id: 'wh-1', topic: 'order.updated' });
  const ingest = calls[1].args.p_order;
  assert.equal(ingest.line_items[0].variation_id, 7, 'ingest receives the Fuxia 360 channel id'); assert.equal(ingest.status, 'processing');
  assert.ok(!JSON.stringify(ingest).includes('ana@example.com') && !JSON.stringify(ingest).includes('5400'), 'inventory step: no customer data, no money');
  assert.equal(calls[2].args.p_order.payment_method, 'shopify_payments'); assert.equal(calls[2].args.p_order.line_items[0].variation_id, 7);
  assert.equal(calls[4].args.p_order.phone, '+525512345678');
});

test('webhook: bad signature or another shop is refused and recorded; nothing is ingested', async (t) => {
  const calls = stubRpc(t);
  const body = JSON.stringify(order());
  assert.equal((await handleShopify(req(body, { 'x-shopify-hmac-sha256': sign(body, 'otro') }), env)).status, 401);
  assert.equal((await handleShopify(req(body, { 'x-shopify-shop-domain': 'otra-tienda.myshopify.com' }), env)).status, 403);
  assert.deepEqual(calls.map((c) => c.fn), ['f360_record_webhook_rejection', 'f360_record_webhook_rejection']);
});

test('webhook: Shopify test orders and other topics are acknowledged and never recorded', async (t) => {
  const calls = stubRpc(t);
  const test1 = await handleShopify(req(JSON.stringify(order({ test: true }))), env);
  assert.equal(test1.status, 200); assert.equal((await test1.json()).ignored, 'pedido de prueba');
  const other = await handleShopify(req(JSON.stringify({ id: 1 }), { 'x-shopify-topic': 'products/update' }), env);
  assert.equal((await other.json()).ignored, 'products/update');
  assert.equal(calls.length, 0);
});
