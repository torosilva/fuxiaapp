// Fuxia 360 → Shopify México: native colour swatches (Mario 2026-11-09: "sigo viendo todas las opciones de colores").
// Shopify draws swatches only when the Color option is linked to the standard category metafield shopify.color-pattern
// (metaobjects of type shopify--color-pattern: label + hex + base colour + base pattern). This script:
//   1) creates/updates one metaobject per colour name used in the store (hex = Fuxia 360 product_colors.hex, most used;
//      prints and two-tones without a hex in Fuxia 360 get an approximate tone below);
//   2) sets each product's Shopify category (Ballerinas → Flats, Sandalias → Sandals, Botas → Boots, Kids → Shoes);
//   3) links the product's Color option to shopify.color-pattern, value by value. Variant ids do not change.
// Input: JSON from prod_read [{ nombre, hex, n }] (colour name in Shopify, Fuxia 360 hex, uses).
// Run: node scripts/f360/shopify_colores.mjs <colores.json> [handle|--all] [--apply]
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const SHOP = 'z9fdqc-0z.myshopify.com', API = '2026-10';
const [file, scope, flag] = process.argv.slice(2);
if (!file || !scope) throw new Error('uso: shopify_colores.mjs <colores.json> <handle|--all> [--apply]');
const APPLY = flag === '--apply';

// Approximate tones for names Fuxia 360 has no hex for (prints / two-tones).
const APROX = {
  'Bambi Dark': '#8a6440', 'Beige con taupe': '#c4b196', 'Beige/Negro': '#d9c3a5', 'Cream Leo': '#d8c3a0', 'Cross Leo': '#b8864b',
  'Dorado/Negro': '#b8860b', 'Leo': '#b8864b', 'Mary Leo': '#b8864b', 'Negro - Reptil': '#2b2825', 'Reptil': '#6e6456',
  'Reptil/Beige': '#a8977c', 'Tigrillo': '#a8743a', 'Vaca': '#efebe4', 'Zebra cafe': '#7a5a3a',
};
const BASE = { Beige: 6, Black: 1, Blue: 2, Bronze: 657, Brown: 7, Gold: 4, Gray: 8, Green: 9, Navy: 15, Orange: 10, Red: 13, Silver: 5, White: 3 };
function baseColor(n) {
  const s = n.toLowerCase();
  const rules = [[/marino/, 'Navy'], [/negr/, 'Black'], [/azul|denim/, 'Blue'], [/blanc|vaca/, 'White'], [/bronce/, 'Bronze'],
    [/dorad|ocre|miel/, 'Gold'], [/plat/, 'Silver'], [/gris|plomo/, 'Gray'], [/verde/, 'Green'], [/rojo|vino/, 'Red'], [/terracota/, 'Orange'],
    [/beige|nude|talco|champagne|cream/, 'Beige'], [/bambi|camel|caramelo|caf|chocolate|leo|tigrillo|zebra|taupe|topo|reptil/, 'Brown']];
  for (const [re, b] of rules) if (re.test(s)) return BASE[b];
  return BASE.Beige;
}
const pattern = (n) => /leo|tigrillo|vaca|zebra|reptil/i.test(n) ? 24478 /* Animal */ : 2874 /* Solid */;
const slug = (n) => 'fx-' + n.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const rows = JSON.parse(readFileSync(file, 'utf8'));
const hexOf = {};
for (const r of rows) if (r.hex && !hexOf[r.nombre]) hexOf[r.nombre] = r.hex;   // rows come ordered by uses desc
for (const n of new Set(rows.map((r) => r.nombre))) if (!hexOf[n]) hexOf[n] = APROX[n] || null;
const missing = Object.entries(hexOf).filter(([, h]) => !h).map(([n]) => n);
if (missing.length) throw new Error('Sin tono: ' + missing.join(', '));

const read = (f) => readFileSync(`${homedir()}/${f}`, 'utf8').trim();
const tok = await (await fetch(`https://${SHOP}/admin/oauth/access_token`, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'client_credentials', client_id: read('.fuxia-shopify.client_id'), client_secret: read('.fuxia-shopify.secret') }) })).json();
async function gql(query, variables) {
  for (let a = 0; a < 6; a++) {
    const j = await (await fetch(`https://${SHOP}/admin/api/${API}/graphql.json`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': tok.access_token }, body: JSON.stringify({ query, variables }) })).json();
    if (j.errors?.some((e) => e.extensions?.code === 'THROTTLED')) { await new Promise((s) => setTimeout(s, 2000)); continue; }
    if (j.errors) throw new Error(JSON.stringify(j.errors).slice(0, 400));
    return j.data;
  }
  throw new Error('THROTTLED');
}
const CATEGORY = { 'Ballerinas': 'aa-8-9', 'Sandalia Plana': 'aa-8-6', 'Sandalia Alta': 'aa-8-6', 'Botas': 'aa-8-3', 'Kids': 'aa-8' };

// products in scope
const q = scope === '--all' ? '' : `handle:${scope}`;
let after = null, products = [];
do {
  const d = await gql(`query($q:String,$a:String){ products(first:50, query:$q, after:$a){ pageInfo{ hasNextPage endCursor } nodes{ id handle productType category{ id }
    options{ id name linkedMetafield{ key } optionValues{ id name } } } } }`, { q, a: after });
  products.push(...d.products.nodes); after = d.products.pageInfo.hasNextPage ? d.products.pageInfo.endCursor : null;
} while (after);
const names = new Set(products.flatMap((p) => p.options.filter((o) => o.name === 'Color').flatMap((o) => o.optionValues.map((v) => v.name))));
const noHex = [...names].filter((n) => !hexOf[n]);
console.log(`${products.length} productos · ${names.size} colores${noHex.length ? ' · SIN TONO: ' + noHex.join(', ') : ''}`);
if (noHex.length) throw new Error('Hay colores sin tono');
if (!APPLY) { for (const n of names) console.log(`  ${n} → ${hexOf[n]}`); console.log('DRY RUN: nada cambió.'); process.exit(0); }

// 1) metaobjects (upsert by handle)
const mo = {};
for (const n of names) {
  const d = await gql(`mutation($h:MetaobjectHandleInput!,$m:MetaobjectUpsertInput!){ metaobjectUpsert(handle:$h, metaobject:$m){ metaobject{ id } userErrors{ message } } }`, {
    h: { type: 'shopify--color-pattern', handle: slug(n) },
    m: { fields: [{ key: 'label', value: n }, { key: 'color', value: hexOf[n] },
      { key: 'color_taxonomy_reference', value: JSON.stringify([`gid://shopify/TaxonomyValue/${baseColor(n)}`]) },
      { key: 'pattern_taxonomy_reference', value: `gid://shopify/TaxonomyValue/${pattern(n)}` }] } });
  const ue = d.metaobjectUpsert.userErrors; if (ue.length) throw new Error(`${n}: ${ue.map((e) => e.message).join('; ')}`);
  mo[n] = d.metaobjectUpsert.metaobject.id;
}
console.log(`colores en Shopify: ${Object.keys(mo).length}`);

// 2) + 3) per product
let ok = 0, errs = [];
for (const p of products) {
  const cat = CATEGORY[p.productType];
  if (cat && p.category?.id !== `gid://shopify/TaxonomyCategory/${cat}`) {
    const d = await gql(`mutation($p:ProductUpdateInput!){ productUpdate(product:$p){ userErrors{ message } } }`, { p: { id: p.id, category: `gid://shopify/TaxonomyCategory/${cat}` } });
    if (d.productUpdate.userErrors.length) { errs.push(`${p.handle} categoría: ${d.productUpdate.userErrors[0].message}`); continue; }
  }
  const opt = p.options.find((o) => o.name === 'Color');
  if (!opt || opt.linkedMetafield) { ok++; continue; }
  const d = await gql(`mutation($p:ID!,$o:OptionUpdateInput!,$v:[OptionValueUpdateInput!]){ productOptionUpdate(productId:$p, option:$o, optionValuesToUpdate:$v){ userErrors{ field message code } } }`, {
    p: p.id, o: { id: opt.id, linkedMetafield: { namespace: 'shopify', key: 'color-pattern' } },
    v: opt.optionValues.map((v) => ({ id: v.id, linkedMetafieldValue: mo[v.name] })) });
  const ue = d.productOptionUpdate.userErrors;
  if (ue.length) errs.push(`${p.handle}: ${ue[0].message}`); else ok++;
}
console.log(`productos con círculos: ${ok}/${products.length}${errs.length ? '\n' + errs.slice(0, 8).join('\n') : ''}`);
