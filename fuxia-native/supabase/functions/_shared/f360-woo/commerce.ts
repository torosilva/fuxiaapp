// G1 Commerce Facts — Woo order economics + first-party attribution (pure helpers + poll; runtime-agnostic, fetch only).
// WHITELIST ONLY: amounts, ids, statuses, dates, currency, payment method id, Woo customer id (number), billing COUNTRY
// code, and Woo Order Attribution values. Never names, emails, phones, addresses, IPs, raw user agents, customer notes,
// refund reasons, coupon codes or Meta metadata (DQ-01: Meta "purchase" is not a sales signal).
import type { Rpc } from './sync.ts';

type Obj = Record<string, unknown>;
const arr = (x: unknown) => (Array.isArray(x) ? (x as Obj[]) : []);
const str = (x: unknown) => (x === null || x === undefined ? '' : String(x));
const num = (x: unknown) => { const n = Number(x); return Number.isFinite(n) ? n : 0; };
const round2 = (n: number) => Math.round(n * 100) / 100;

/** Browser / OS class from a user agent. The raw string is never returned or stored. */
export function browserClass(ua: string): { browser_class: string; os_class: string } {
  const os = /iPhone|iPad|iPod/i.test(ua) ? 'ios' : /Android/i.test(ua) ? 'android' : /Macintosh|Mac OS X/i.test(ua) ? 'macos' : /Windows/i.test(ua) ? 'windows' : ua ? 'other' : '';
  const browser = !ua ? '' : /Instagram/i.test(ua) ? 'instagram_iab' : /FBAN|FBAV|FB_IAB/i.test(ua) ? 'facebook_iab'
    : /Edg\//i.test(ua) ? 'edge' : /Firefox|FxiOS/i.test(ua) ? 'firefox' : /CriOS|Chrome\//i.test(ua) ? 'chrome' : /Safari\//i.test(ua) ? 'safari' : 'other';
  return { browser_class: browser, os_class: os };
}

const hostOf = (u: string) => { try { return new URL(u).hostname || null; } catch { return null; } };
const pathOf = (u: string) => { try { return new URL(u).pathname || null; } catch { return u.startsWith('/') ? u.split(/[?#]/)[0] : null; } };

/** Woo Order Attribution (first-party, last click within a 30-min session). Duplicate keys: first value that is not "admin". */
export function orderAttribution(o: Obj): Obj | null {
  const meta = arr(o.meta_data).filter((m) => str(m.key).startsWith('_wc_order_attribution_'));
  if (!meta.length) return null;
  const pick = (k: string) => {
    const vals = meta.filter((m) => m.key === `_wc_order_attribution_${k}`).map((m) => str(m.value)).filter((v) => v !== '');
    return (k === 'source_type' ? vals.find((v) => v !== 'admin') ?? vals[0] : vals[0]) ?? null;
  };
  const ua = pick('user_agent') ?? '';
  const entry = pick('session_entry');
  const ref = pick('referrer');
  return {
    source_type: pick('source_type'), utm_source: pick('utm_source'), utm_medium: pick('utm_medium'),
    utm_campaign: pick('utm_campaign'), utm_content: pick('utm_content'), utm_term: pick('utm_term'), utm_id: pick('utm_id'),
    referrer_host: ref ? hostOf(ref) : null,
    session_entry_path: entry ? pathOf(entry) : null,                    // path only: never the query string
    session_start_at: pick('session_start_time'),
    session_pages: pick('session_pages'), session_count: pick('session_count'),
    device_type: pick('device_type'), ...browserClass(ua),
  };
}

/** Refund detail from GET /orders/{id}/refunds (Woo returns refunded line amounts as negative numbers). */
export function refundDetail(r: Obj): Obj {
  const lines = arr(r.line_items).map((l) => ({
    woo_line_id: num(arr(l.meta_data).find((m) => m.key === '_refunded_item_id')?.value) || null,
    quantity: Math.abs(num(l.quantity)), total: Math.abs(num(l.total)), total_tax: Math.abs(num(l.total_tax)),
  }));
  const ship = arr(r.shipping_lines);
  return {
    id: num(r.id), amount: Math.abs(num(r.amount)), created_at: str(r.date_created_gmt) || null, detail: true,
    product_amount: round2(lines.reduce((s, l) => s + l.total, 0)),
    shipping_amount: round2(ship.reduce((s, x) => s + Math.abs(num(x.total)), 0)),
    tax_amount: round2(lines.reduce((s, l) => s + l.total_tax, 0) + ship.reduce((s, x) => s + Math.abs(num(x.total_tax)), 0)),
    lines,
  };
}

/** The economics payload for public.f360_capture_order_economics. `refunds` may be replaced by detailed ones. */
export function orderEconomics(o: Obj, detailedRefunds?: Obj[]): Obj {
  const fees = arr(o.fee_lines);
  const billing = (o.billing ?? {}) as Obj;
  const country = str(billing.country).toUpperCase();
  const byId = new Map((detailedRefunds ?? []).map((r) => [num(r.id), r]));
  return {
    id: num(o.id), status: str(o.status), created_via: str(o.created_via) || null,
    date_created_gmt: str(o.date_created_gmt) || null, date_paid_gmt: str(o.date_paid_gmt) || null,
    date_completed_gmt: str(o.date_completed_gmt) || null, date_modified_gmt: str(o.date_modified_gmt ?? o.date_modified),
    currency: str(o.currency) || null, prices_include_tax: o.prices_include_tax === true,
    discount_total: str(o.discount_total), discount_tax: str(o.discount_tax), shipping_total: str(o.shipping_total),
    shipping_tax: str(o.shipping_tax), cart_tax: str(o.cart_tax), total: str(o.total), total_tax: str(o.total_tax),
    fees_total: round2(fees.reduce((s, f) => s + num(f.total), 0)), fees_tax: round2(fees.reduce((s, f) => s + num(f.total_tax), 0)),
    coupon_count: arr(o.coupon_lines).length,
    payment_method: str(o.payment_method) || null,
    woo_customer_id: num(o.customer_id) || null,
    billing_country: /^[A-Z]{2}$/.test(country) ? country : null,
    line_items: arr(o.line_items).map((l) => {
      const wdr = arr(l.meta_data).find((m) => m.key === '_advanced_woo_discount_item_total_discount')?.value as Obj | undefined;
      const initial = wdr ? num(wdr.initial_price) : 0;
      const discounted = wdr ? num(wdr.discounted_price) : 0;
      return {
        id: num(l.id), product_id: num(l.product_id) || null, variation_id: num(l.variation_id) || null, sku: str(l.sku) || null,
        quantity: num(l.quantity), subtotal: str(l.subtotal), subtotal_tax: str(l.subtotal_tax), total: str(l.total), total_tax: str(l.total_tax),
        // implicit price-rule discount (Woo Discount Rules): SECONDARY data, never used to build revenue
        list_price_hint: initial > discounted && initial > 0 ? initial : null,
        list_price_source: initial > discounted && initial > 0 ? 'wdr_initial_price' : null,
      };
    }),
    refunds: arr(o.refunds).map((r) => byId.get(num(r.id)) ?? { id: num(r.id), amount: Math.abs(num(r.total)), created_at: null, detail: false }),
    attribution: orderAttribution(o),
  };
}

/** Minimal Woo reads the commerce poll needs (read-only GETs). */
export type CommerceWoo = {
  listOrders: (modifiedAfterGmt: string | null, page: number) => Promise<Obj[]>;
  listRefunds: (orderId: number) => Promise<Obj[]>;
};
export function commerceWoo(cfg: { baseUrl: string; user: string; secret: string; timeoutMs?: number }): CommerceWoo {
  const base = `${cfg.baseUrl.replace(/\/+$/, '')}/wp-json/wc/v3`;
  const auth = 'Basic ' + btoa(`${cfg.user}:${cfg.secret}`);
  const get = async (path: string) => {
    const res = await fetch(`${base}${path}`, { headers: { Authorization: auth, Accept: 'application/json' }, signal: AbortSignal.timeout(cfg.timeoutMs ?? 60_000) });
    if (!res.ok) throw new Error(`Woo HTTP ${res.status}`);
    return (await res.json()) as Obj[];
  };
  return {
    listOrders: (after, page) => get(`/orders?status=any&orderby=modified&order=asc&per_page=100&page=${page}&dates_are_gmt=true` +
      (after ? `&modified_after=${encodeURIComponent(after)}` : '')),
    listRefunds: (id) => get(`/orders/${id}/refunds?per_page=100`),
  };
}

export type PollStats = { fetched: number; inserted: number; updated: number; unchanged: number; stale: number; refunds: number; refund_details: number; errors: number; pages: number };

/** Poll (heartbeat) or backfill: pages every order modified after the cursor, captures economics idempotently. */
export async function commercePoll(rpc: Rpc, woo: CommerceWoo, targetKey: string, kind: 'poll' | 'backfill', maxPages = 20) {
  const begin = await rpc<{ run_id: number; modified_after: string | null }>('f360_commerce_run_begin', { p_target_key: targetKey, p_kind: kind });
  const stats: PollStats = { fetched: 0, inserted: 0, updated: 0, unchanged: 0, stale: 0, refunds: 0, refund_details: 0, errors: 0, pages: 0 };
  let cursor: string | null = null;
  const after = begin.modified_after ? new Date(begin.modified_after).toISOString().slice(0, 19) : null;
  try {
    for (let page = 1; page <= maxPages; page++) {
      const orders = await woo.listOrders(after, page);
      stats.pages++;
      for (const o of orders) {
        stats.fetched++;
        let detailed: Obj[] | undefined;
        if (arr(o.refunds).length) {
          try { detailed = (await woo.listRefunds(num(o.id))).map(refundDetail); stats.refund_details += detailed.length; } catch { detailed = undefined; }   // header-only, PARTIAL
        }
        try {
          const r = await rpc<{ result: keyof PollStats; refunds: number }>('f360_capture_order_economics',
            { p_target_key: targetKey, p_order: orderEconomics(o, detailed), p_via: kind });
          if (r.result in stats) stats[r.result]++;
          stats.refunds += r.refunds ?? 0;
          const m = str(o.date_modified_gmt);
          if (m && (!cursor || m > cursor)) cursor = m;
        } catch { stats.errors++; }
      }
      if (orders.length < 100) break;
    }
    const ok = stats.errors === 0;
    await rpc('f360_commerce_run_end', { p_run_id: begin.run_id, p_ok: ok, p_stats: stats, p_error: ok ? null : `${stats.errors} pedidos con error`,
      p_cursor: cursor ? `${cursor}Z` : null });
    return { run_id: begin.run_id, ok, stats };
  } catch (e) {
    await rpc('f360_commerce_run_end', { p_run_id: begin.run_id, p_ok: false, p_stats: stats, p_error: (e as Error).message, p_cursor: null });
    return { run_id: begin.run_id, ok: false, stats, error: (e as Error).message };
  }
}
