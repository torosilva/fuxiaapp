// STAGING ONLY — READ-ONLY reconciliation Fuxia 360 ↔ Woo (staging4). Writes NOTHING (no run record, no push, no fix):
// reads every Woo-linked variant's expected stock (= on_hand at the channel's source location) and Woo's stock via GET.
// Run: scripts/s00a/run.sh ../f360/p23b_readonly_reconcile.mjs
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^WOO_(BASE_URL|USER|SECRET)=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
if (new URL(W.WOO_BASE_URL).hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not staging4');
const auth = 'Basic ' + Buffer.from(`${W.WOO_USER}:${W.WOO_SECRET}`).toString('base64');
const rows = psql(`select v.sku, pl.woo_product_id, vl.woo_variation_id, coalesce(b.on_hand, 0), l.name
  from f360.sales_targets t join f360.locations l on l.id = t.fulfillment_location_id
  join f360.woo_variant_links vl on vl.target_id = t.id join f360.product_variants v on v.id = vl.variant_id
  join f360.woo_product_links pl on pl.target_id = t.id and pl.product_id = v.product_id
  left join f360.inventory_balances b on b.variant_id = v.id and b.location_id = t.fulfillment_location_id
  where t.key = 'woo_staging4' order by v.sku;`, {}, { readOnly: true }).trim().split('\n').filter((l) => l.includes('|')).map((l) => l.split('|'));
const byProduct = new Map();
for (const r of rows) byProduct.set(r[1], [...(byProduct.get(r[1]) ?? []), r]);
let same = 0; const diff = [];
for (const [pid, rs] of byProduct) {
  const vars = await (await fetch(`${W.WOO_BASE_URL}/wp-json/wc/v3/products/${pid}/variations?per_page=100`, { headers: { Authorization: auth } })).json();
  for (const [sku, , vid, f360] of rs) {
    const w = vars.find((x) => String(x.id) === vid);
    if (w && w.manage_stock === true && w.stock_quantity === Number(f360)) same++; else diff.push(`${sku}: F360 ${f360} · Woo ${w ? w.stock_quantity : 'no existe'}`);
  }
}
console.log(`origen: ${rows[0]?.[4]} · variantes vinculadas: ${rows.length} · coinciden: ${same} · diferencias: ${diff.length}`);
for (const d of diff) console.log('  DIFERENCIA', d);
const nz = rows.filter((r) => Number(r[3]) > 0).map((r) => `${r[0].replace('F360-MACARENA-', '')}=${r[3]}`).join(' ');
console.log(`con stock: ${nz}`);
process.exit(diff.length ? 1 : 0);
