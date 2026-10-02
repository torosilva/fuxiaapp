// Track D2 — READ-ONLY delta: Woo PRODUCTION public catalog vs staging4 public catalog (Mario's P1, 2026-10-02).
// Public Store API only (what any visitor sees): GET, NO credentials, NO cookies, NO admin, nothing is written anywhere.
// Output: docs/fuxia360/audit/trackd/d2_prod_vs_staging4.json + a summary on stdout.
// Run: node scripts/f360/d2_prod_delta.mjs
import { writeFileSync } from 'node:fs';

const HOSTS = { production: 'https://fuxiaballerinas.com', staging4: 'https://staging4.fuxiaballerinas.com' };

async function storeCatalog(base) {
  const out = [];
  for (let page = 1; ; page++) {
    const r = await fetch(`${base}/wp-json/wc/store/v1/products?per_page=100&page=${page}&orderby=id&order=asc`, {
      method: 'GET', headers: { 'User-Agent': 'Fuxia360-D2-readonly', Accept: 'application/json' }, redirect: 'error', credentials: 'omit',
    });
    if (!r.ok) throw new Error(`${base} page ${page}: HTTP ${r.status}`);
    out.push(...(await r.json()));
    if (page >= Number(r.headers.get('x-wp-totalpages') || 1)) break;
  }
  return out.map((p) => ({
    id: p.id, name: p.name, slug: p.slug, sku: p.sku, type: p.type,
    price: p.prices?.regular_price, sale: p.prices?.sale_price !== p.prices?.regular_price ? p.prices?.sale_price : null,
    categories: (p.categories || []).map((c) => c.slug).sort().join('|'),
    attributes: (p.attributes || []).map((a) => `${a.name}:${(a.terms || []).map((t) => t.name).join('/')}`).join(' · '),
    in_stock: p.is_in_stock,
    variations: (p.variations || []).map((v) => ({ id: v.id, attrs: (v.attributes || []).map((a) => `${a.name}=${a.value}`).join(',') })).sort((a, b) => a.id - b.id),
  }));
}

const [prod, stg] = await Promise.all([storeCatalog(HOSTS.production), storeCatalog(HOSTS.staging4)]);
const S = new Map(stg.map((p) => [p.id, p]));
const Pm = new Map(prod.map((p) => [p.id, p]));
const FIELDS = ['name', 'slug', 'sku', 'type', 'price', 'sale', 'categories', 'attributes', 'in_stock'];
const delta = { only_in_production: [], only_in_staging4: [], changed: [] };
for (const p of prod) {
  const s = S.get(p.id);
  if (!s) { delta.only_in_production.push(p); continue; }
  const diffs = FIELDS.filter((f) => JSON.stringify(p[f]) !== JSON.stringify(s[f])).map((f) => ({ field: f, staging4: s[f], production: p[f] }));
  const sv = new Map(s.variations.map((v) => [v.id, v.attrs])); const pv = new Map(p.variations.map((v) => [v.id, v.attrs]));
  const added = p.variations.filter((v) => !sv.has(v.id)); const removed = s.variations.filter((v) => !pv.has(v.id));
  const reattr = p.variations.filter((v) => sv.has(v.id) && sv.get(v.id) !== v.attrs).map((v) => ({ id: v.id, staging4: sv.get(v.id), production: v.attrs }));
  if (added.length) diffs.push({ field: 'variations_added', production: added });
  if (removed.length) diffs.push({ field: 'variations_removed', staging4: removed });
  if (reattr.length) diffs.push({ field: 'variation_attributes', changes: reattr });
  if (diffs.length) delta.changed.push({ id: p.id, name: p.name, diffs });
}
for (const s of stg) if (!Pm.has(s.id)) delta.only_in_staging4.push(s);

const summary = {
  read_at: new Date().toISOString(), method: 'public Store API, GET, no credentials',
  production: { products: prod.length, variations: prod.reduce((n, p) => n + p.variations.length, 0) },
  staging4: { products: stg.length, variations: stg.reduce((n, p) => n + p.variations.length, 0) },
  only_in_production: delta.only_in_production.length, only_in_staging4: delta.only_in_staging4.length, changed: delta.changed.length,
};
writeFileSync('docs/fuxia360/audit/trackd/d2_prod_vs_staging4.json', JSON.stringify({ summary, ...delta }, null, 1));
console.log(JSON.stringify(summary, null, 1));
for (const p of delta.only_in_production) console.log('+ PROD', p.id, p.name, p.sku, p.variations.length, 'variaciones');
for (const p of delta.only_in_staging4) console.log('- STG4', p.id, p.name, p.sku);
for (const c of delta.changed) console.log('~', c.id, c.name, c.diffs.map((d) => d.field).join(', '));
