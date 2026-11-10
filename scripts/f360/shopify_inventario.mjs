// Fuxia 360 → Shopify México: real inventory (Mario 2026-11-09, "inventario real automático").
// Input: a JSON array from prod_read: { v: shopify_variant_id, p: shopify_product_id, i: inventory_item_id, mto: bool, q: online_ats }.
// Per product, in ONE call per product:
//   · inventoryPolicy CONTINUE for make-to-order models (they keep selling at 0 and are made to order), DENY otherwise;
//   · inventoryItem.tracked = true.
// Then sets the "available" quantity at the store's single location (inventorySetQuantities, 100 per call).
// Order matters: the policy is written in the same call that turns tracking on, so no make-to-order size is ever sold out.
// Credentials: ~/.fuxia-shopify.client_id / ~/.fuxia-shopify.secret (never printed).
// Run: node scripts/f360/shopify_inventario.mjs <ats.json>            (dry run: prints what would change)
//      node scripts/f360/shopify_inventario.mjs <ats.json> --apply
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';

const SHOP = 'z9fdqc-0z.myshopify.com', API = '2026-10', LOCATION = 'gid://shopify/Location/97074643014';
const [file, flag] = process.argv.slice(2);
if (!file) throw new Error('uso: shopify_inventario.mjs <ats.json> [--apply]');
const APPLY = flag === '--apply';
const rows = JSON.parse(readFileSync(file, 'utf8'));
if (!Array.isArray(rows) || !rows.length) throw new Error('JSON vacío');

const read = (f) => readFileSync(`${homedir()}/${f}`, 'utf8').trim();
const tok = await (await fetch(`https://${SHOP}/admin/oauth/access_token`, {
  method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({ grant_type: 'client_credentials', client_id: read('.fuxia-shopify.client_id'), client_secret: read('.fuxia-shopify.secret') }),
})).json();
if (!/write_products/.test(tok.scope || '') || !/write_inventory/.test(tok.scope || '')) throw new Error('Faltan permisos write_products/write_inventory');
async function gql(query, variables) {
  for (let a = 0; a < 5; a++) {
    const r = await fetch(`https://${SHOP}/admin/api/${API}/graphql.json`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Shopify-Access-Token': tok.access_token }, body: JSON.stringify({ query, variables }) });
    const j = await r.json();
    if (j.errors?.some((e) => e.extensions?.code === 'THROTTLED')) { await new Promise((s) => setTimeout(s, 2000)); continue; }
    if (j.errors) throw new Error(JSON.stringify(j.errors).slice(0, 300));
    return j.data;
  }
  throw new Error('THROTTLED');
}

const byProduct = new Map();
for (const r of rows) { if (!byProduct.has(r.p)) byProduct.set(r.p, []); byProduct.get(r.p).push(r); }
console.log(`${rows.length} tallas en ${byProduct.size} productos · ${rows.filter((r) => r.q > 0).length} con existencia (${rows.reduce((s, r) => s + r.q, 0)} pares) · ${rows.filter((r) => r.mto).length} sobre pedido (CONTINUE) · ${rows.filter((r) => !r.mto).length} DENY`);
if (!APPLY) { console.log('DRY RUN: nada cambió. Usa --apply.'); process.exit(0); }

let prodOk = 0, errs = [];
for (const [pid, vs] of byProduct) {
  const d = await gql(`mutation($p: ID!, $v: [ProductVariantsBulkInput!]!) { productVariantsBulkUpdate(productId: $p, variants: $v) { userErrors { field message } } }`, {
    p: `gid://shopify/Product/${pid}`,
    v: vs.map((r) => ({ id: `gid://shopify/ProductVariant/${r.v}`, inventoryPolicy: r.mto ? 'CONTINUE' : 'DENY', inventoryItem: { tracked: true } })),
  });
  const ue = d.productVariantsBulkUpdate.userErrors;
  if (ue.length) errs.push(`${pid}: ${ue[0].message}`); else prodOk++;
}
console.log(`política + rastreo: ${prodOk}/${byProduct.size} productos${errs.length ? ' · errores: ' + errs.slice(0, 3).join(' | ') : ''}`);

let qOk = 0;
for (let k = 0; k < rows.length; k += 100) {
  const chunk = rows.slice(k, k + 100);
  const d = await gql(`mutation($in: InventorySetQuantitiesInput!) { inventorySetQuantities(input: $in) { userErrors { field message } } }`, {
    in: { name: 'available', reason: 'correction', ignoreCompareQuantity: true, referenceDocumentUri: 'fuxia360://inventario-real/2026-11-09',
          quantities: chunk.map((r) => ({ inventoryItemId: `gid://shopify/InventoryItem/${r.i}`, locationId: LOCATION, quantity: r.q })) },
  });
  const ue = d.inventorySetQuantities.userErrors;
  if (ue.length) errs.push(`cantidades ${k}: ${ue[0].message}`); else qOk += chunk.length;
}
console.log(`cantidades: ${qOk}/${rows.length}${errs.length ? ' · errores: ' + errs.slice(-3).join(' | ') : ''}`);
