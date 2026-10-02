// STAGING ONLY — Track D1: READ-ONLY discovery of the legacy Woo catalog on staging4 (a copy of production).
// GET requests only (products + variations, every status). Writes NOTHING to Woo or Supabase.
// Output: docs/fuxia360/audit/trackd/d1_catalog_staging4.json (catalog data only: no customers, orders or secrets).
// Run: node scripts/f360/d1_legacy_discovery.mjs
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^WOO_(BASE_URL|USER|SECRET)=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
if (new URL(W.WOO_BASE_URL).hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not staging4');
const auth = 'Basic ' + Buffer.from(`${W.WOO_USER}:${W.WOO_SECRET}`).toString('base64');

async function getAll(path) {
  const out = [];
  for (let page = 1; ; page++) {
    const sep = path.includes('?') ? '&' : '?';
    const r = await fetch(`${W.WOO_BASE_URL}/wp-json/wc/v3/${path}${sep}per_page=100&page=${page}`, { method: 'GET', headers: { Authorization: auth } });
    if (!r.ok) throw new Error(`GET ${path} page ${page}: HTTP ${r.status}`);
    const rows = await r.json();
    out.push(...rows);
    if (page >= Number(r.headers.get('x-wp-totalpages') || 1)) return out;
  }
}

const pick = (o, keys) => Object.fromEntries(keys.map((k) => [k, o[k]]));
const attrs = (a) => (a || []).map((x) => ({ id: x.id, name: x.name, slug: x.slug, option: x.option, options: x.options, variation: x.variation }));
const P = ['id', 'name', 'slug', 'status', 'type', 'sku', 'global_unique_id', 'manage_stock', 'stock_quantity', 'stock_status', 'backorders', 'price', 'regular_price', 'sale_price', 'catalog_visibility', 'date_created', 'date_modified'];
const V = ['id', 'sku', 'global_unique_id', 'status', 'manage_stock', 'stock_quantity', 'stock_status', 'backorders', 'price', 'regular_price', 'sale_price', 'menu_order'];

const products = await getAll('products?status=any&orderby=id&order=asc');
const catalog = [];
for (const p of products) {
  const variations = p.type === 'variable' ? await getAll(`products/${p.id}/variations?status=any&orderby=id&order=asc`) : [];
  catalog.push({
    ...pick(p, P),
    categories: (p.categories || []).map((c) => ({ id: c.id, slug: c.slug })),
    attributes: attrs(p.attributes),
    variations: variations.map((v) => ({ ...pick(v, V), parent_manage_stock: v.manage_stock === 'parent', attributes: attrs(v.attributes) })),
  });
}

mkdirSync('docs/fuxia360/audit/trackd', { recursive: true });
writeFileSync('docs/fuxia360/audit/trackd/d1_catalog_staging4.json', JSON.stringify({ source: W.WOO_BASE_URL, read_at: new Date().toISOString(), method: 'GET wc/v3 only', products: catalog }, null, 1));
const vars = catalog.flatMap((p) => p.variations.map((v) => ({ ...v, parent: p })));
console.log(JSON.stringify({ products: catalog.length, variations: vars.length }, null, 0));
