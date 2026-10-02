// Track D2 — READ-ONLY aggregated online sales per variation (Mario's P4, 2026-10-02). STAGING4 ONLY.
// Uses the WooCommerce Analytics report (already aggregated by Woo): no order, customer, address, email or phone is read.
// Context for Carolina and to prioritise review ONLY. It is NEVER inventory and NEVER an opening balance.
// Output: docs/fuxia360/audit/trackd/d2_sales_by_variation.json. Run: node scripts/f360/d2_sales_aggregates.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^WOO_(BASE_URL|USER|SECRET)=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
if (new URL(W.WOO_BASE_URL).hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not staging4');
const auth = 'Basic ' + Buffer.from(`${W.WOO_USER}:${W.WOO_SECRET}`).toString('base64');

async function report(after) {
  const out = [];
  for (let page = 1; ; page++) {
    const r = await fetch(`${W.WOO_BASE_URL}/wp-json/wc-analytics/reports/variations?per_page=100&page=${page}&after=${after}&orderby=items_sold&order=desc`, { method: 'GET', headers: { Authorization: auth } });
    if (!r.ok) throw new Error(`report page ${page}: HTTP ${r.status}`);
    for (const x of await r.json()) out.push({ product_id: x.product_id, variation_id: x.variation_id, items_sold: x.items_sold, orders_count: x.orders_count });
    if (page >= Number(r.headers.get('x-wp-totalpages') || 1)) return out;
  }
}

const since90 = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 19);
const [all, d90] = await Promise.all([report('2015-01-01T00:00:00'), report(since90)]);
const by = new Map();
for (const x of all) by.set(x.variation_id, { product_id: x.product_id, variation_id: x.variation_id, sold_all: x.items_sold, orders_all: x.orders_count, sold_90d: 0 });
for (const x of d90) { const e = by.get(x.variation_id) ?? { product_id: x.product_id, variation_id: x.variation_id, sold_all: 0, orders_all: 0 }; e.sold_90d = x.items_sold; by.set(x.variation_id, e); }
const rows = [...by.values()].sort((a, b) => b.sold_all - a.sold_all);
writeFileSync('docs/fuxia360/audit/trackd/d2_sales_by_variation.json', JSON.stringify({
  source: 'staging4 wc-analytics/reports/variations (aggregates only; staging4 is a clone of production ~2026-09-24)', read_at: new Date().toISOString(),
  window_90d_from: since90, use: 'context for review only; NEVER inventory or opening balance', rows,
}, null, 1));
console.log(JSON.stringify({ variations_with_sales: rows.length, pairs_all: rows.reduce((n, r) => n + r.sold_all, 0), pairs_90d: rows.reduce((n, r) => n + r.sold_90d, 0) }));
