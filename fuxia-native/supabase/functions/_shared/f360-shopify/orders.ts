// Shopify → Fuxia 360 (pure helpers, runtime-agnostic). Mario 2026-11-09: the agency moved México to Shopify
// (mx.fuxiaballerinas.com); Colombia stays on WooCommerce. A Shopify order is translated to the WooCommerce order shape that
// Fuxia 360 already ingests (f360_ingest_woo_order, f360_capture_order_economics, shipping, loyalty), so ventas, tablero,
// Growth, inventario, puntos and the thank-you WhatsApp work unchanged. The channel's own ids are kept as they are: Shopify's
// variant id is the "variation id" of the shopify_mx sales target (f360.woo_variant_links holds the link per target).
// Webhook payloads are the REST order JSON (docs: shopify.dev/docs/api/admin-rest/latest/resources/order).

type Obj = Record<string, unknown>;
const arr = (x: unknown) => (Array.isArray(x) ? (x as Obj[]) : []);
const obj = (x: unknown) => (x && typeof x === 'object' && !Array.isArray(x) ? (x as Obj) : {});
const str = (x: unknown) => (x === null || x === undefined ? '' : String(x));
const num = (x: unknown) => { const n = Number(x); return Number.isFinite(n) ? n : 0; };
const money = (n: number) => (Math.round(n * 100) / 100).toFixed(2);

/** ISO timestamp with offset → Woo's "_gmt" form (UTC, no offset): the database reads it as UTC. */
export function gmt(ts: unknown): string {
  const s = str(ts);
  if (!s) return '';
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 19);
}

/** Shopify financial / fulfillment / cancel state → the Woo status Fuxia 360 already understands.
 *  paid → processing (completed once fulfilled); refunded → refunded; cancelled or voided → cancelled; pending → pending;
 *  authorized / partially_paid → on-hold (money not captured yet: never moves stock); expired → failed. */
export function wooStatus(o: Obj): string {
  const fin = str(o.financial_status);
  if (fin === 'refunded') return 'refunded';
  if (o.cancelled_at || fin === 'voided') return 'cancelled';
  if (fin === 'paid' || fin === 'partially_refunded') return str(o.fulfillment_status) === 'fulfilled' ? 'completed' : 'processing';
  if (fin === 'authorized' || fin === 'partially_paid') return 'on-hold';
  if (fin === 'expired') return 'failed';
  return 'pending';
}

/** "orders/updated" → "order.updated" (the Woo topic form the database records). */
export const wooTopic = (shopifyTopic: string) => shopifyTopic.replace(/^orders\//, 'order.');

const address = (a: Obj, email: string, fallbackPhone: string) => ({
  first_name: str(a.first_name), last_name: str(a.last_name), address_1: str(a.address1), address_2: str(a.address2),
  city: str(a.city), state: str(a.province_code), postcode: str(a.zip), country: str(a.country_code).toUpperCase(),
  phone: str(a.phone) || fallbackPhone, email,
});

const lineTotal = (li: Obj) => num(li.price) * num(li.quantity) - arr(li.discount_allocations).reduce((s, d) => s + num(d.amount), 0);
const lineTax = (li: Obj) => arr(li.tax_lines).reduce((s, t) => s + num(t.price), 0);

/** Attribution Shopify gives on the order (landing page + referrer) in the Woo Order Attribution form. Path only. */
function attributionMeta(o: Obj): Obj[] {
  const landing = str(o.landing_site);
  const referrer = str(o.referring_site);
  if (!landing && !referrer) return [];
  let q = new URLSearchParams();
  let path = '';
  try { const u = new URL(landing, 'https://shop.invalid'); q = u.searchParams; path = u.pathname; } catch { /* no landing */ }
  const utm = (k: string) => q.get(`utm_${k}`) ?? '';
  const meta: Obj[] = [];
  const add = (k: string, v: string) => { if (v) meta.push({ key: `_wc_order_attribution_${k}`, value: v }); };
  add('source_type', utm('source') ? 'utm' : referrer ? 'referral' : 'typein');
  for (const k of ['source', 'medium', 'campaign', 'content', 'term', 'id']) add(`utm_${k}`, utm(k));
  add('referrer', referrer);
  add('session_entry', path ? `https://mx.fuxiaballerinas.com${path}` : '');
  return meta;
}

/** Refunds with their detail (Shopify sends it inside the order: no extra read like Woo needs). */
export function refundDetails(o: Obj): Obj[] {
  return arr(o.refunds).map((r) => {
    const lines = arr(r.refund_line_items).map((l) => ({
      woo_line_id: num(l.line_item_id) || null, quantity: Math.abs(num(l.quantity)), total: Math.abs(num(l.subtotal)), total_tax: Math.abs(num(l.total_tax)),
    }));
    const amount = arr(r.transactions).filter((t) => str(t.kind) === 'refund' && str(t.status) === 'success').reduce((s, t) => s + num(t.amount), 0);
    const shipping = arr(r.order_adjustments).filter((a) => str(a.kind) === 'shipping_refund').reduce((s, a) => s + Math.abs(num(a.amount)), 0);
    return {
      id: num(r.id), amount: Math.round(amount * 100) / 100, created_at: gmt(r.created_at) || null, detail: true,
      product_amount: Math.round(lines.reduce((s, l) => s + l.total, 0) * 100) / 100,
      shipping_amount: Math.round(shipping * 100) / 100,
      tax_amount: Math.round(lines.reduce((s, l) => s + l.total_tax, 0) * 100) / 100,
      lines,
    };
  });
}

/** One Shopify order → the WooCommerce order shape. Amounts are the RAW amounts the customer paid (Shopify México shows
 *  prices with IVA included: `taxes_included`); nothing is recomputed. */
export function toWooOrder(o: Obj): Obj {
  const items = arr(o.line_items);
  const customer = obj(o.customer);
  const email = str(o.email) || str(customer.email);
  const phone = str(o.phone) || str(customer.phone);
  const billingSrc = Object.keys(obj(o.billing_address)).length ? obj(o.billing_address) : obj(o.shipping_address);
  const status = wooStatus(o);
  const paid = ['processing', 'completed', 'refunded'].includes(status) || str(o.financial_status) === 'partially_refunded';
  const shippingTotal = arr(o.shipping_lines).reduce((s, l) => s + num(l.price) - arr(l.discount_allocations).reduce((d, x) => d + num(x.amount), 0), 0);
  const shippingTax = arr(o.shipping_lines).reduce((s, l) => s + arr(l.tax_lines).reduce((t, x) => t + num(x.price), 0), 0);
  const source = str(o.source_name);
  return {
    id: num(o.id), number: str(o.order_number) || str(o.name).replace(/^#/, ''), status,
    created_via: source === 'web' ? 'checkout' : source === 'shopify_draft_order' ? 'admin' : 'rest-api',
    currency: str(o.currency) || null, prices_include_tax: o.taxes_included === true,
    date_created_gmt: gmt(o.created_at), date_modified_gmt: gmt(o.updated_at),
    date_paid_gmt: paid ? gmt(o.processed_at) || gmt(o.created_at) : '',
    date_completed_gmt: status === 'completed' ? gmt(o.closed_at) || gmt(o.updated_at) : '',
    discount_total: money(num(o.total_discounts)), discount_tax: '0.00',
    shipping_total: money(shippingTotal), shipping_tax: money(shippingTax),
    cart_tax: money(items.reduce((s, li) => s + lineTax(li), 0)), total: money(num(o.total_price)), total_tax: money(num(o.total_tax)),
    payment_method: arr(o.payment_gateway_names).map(str)[0] ?? '',
    customer_id: num(customer.id) || 0,
    billing: address(billingSrc, email, phone),
    shipping: address(obj(o.shipping_address), email, phone),
    coupon_lines: arr(o.discount_codes).map((d) => ({ code: str(d.code) })),
    fee_lines: [],
    line_items: items.map((li) => ({
      id: num(li.id), product_id: num(li.product_id) || null, variation_id: num(li.variant_id) || null,
      sku: str(li.sku) || null, name: [str(li.title), str(li.variant_title)].filter(Boolean).join(' · '), quantity: num(li.quantity),
      subtotal: money(num(li.price) * num(li.quantity)), subtotal_tax: money(lineTax(li)), total: money(lineTotal(li)), total_tax: money(lineTax(li)),
      meta_data: [],
    })),
    refunds: arr(o.refunds).map((r) => ({ id: num(r.id), total: '0' })),
    meta_data: attributionMeta(o),
  };
}
