// STAGING ONLY — companion of admin-web/e2e/carolina-acceptance.spec.ts.
// 1) Watches Woo (staging4) update BY ITSELF after Carolina's move (Nude 35 leaves Bodega CDMX → Woo −1), no manual call.
// 2) Returns the pair: receive 0 at "Demo · Tienda" → difference → "regresar al origen" (audited, nothing deleted).
// 3) Watches Woo go back up by itself. Run: scripts/s00a/run.sh ../f360/carolina_acceptance_restore.mjs
import { readFileSync } from 'node:fs';
import { client, loadEnv, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^WOO_(BASE_URL|USER|SECRET)=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
if (new URL(W.WOO_BASE_URL).hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not staging4');
const auth = 'Basic ' + Buffer.from(`${W.WOO_USER}:${W.WOO_SECRET}`).toString('base64');
const one = (sql) => psql(sql, {}, { readOnly: true }).trim().split('\n').pop();
const sku = 'F360-MACARENA-NUDE-35';
const variant = one(`select id from f360.product_variants where sku = '${sku}';`);
const wooVar = one(`select vl.woo_variation_id from f360.woo_variant_links vl join f360.sales_targets t on t.id = vl.target_id where t.key = 'woo_staging4' and vl.variant_id = '${variant}';`);
const wooStock = async () => (await (await fetch(`${W.WOO_BASE_URL}/wp-json/wc/v3/products/3621/variations/${wooVar}`, { headers: { Authorization: auth } })).json()).stock_quantity;
const bodega = () => Number(one(`select coalesce((select b.on_hand from f360.inventory_balances b join f360.locations l on l.id = b.location_id where l.name = 'Bodega CDMX' and b.variant_id = '${variant}'), 0);`));
const transfer = one(`select t.id from f360.transfers t join f360.transfer_lines tl on tl.transfer_id = t.id join f360.locations a on a.id = t.from_location_id join f360.locations b on b.id = t.to_location_id
  where t.status = 'in_transit' and a.name = 'Bodega CDMX' and b.name = 'Demo · Tienda' and tl.variant_id = '${variant}' order by t.requested_at desc limit 1;`);
if (!/^[0-9a-f-]{36}$/.test(transfer)) throw new Error('No hay una transferencia en camino de Carolina (Nude 35, Bodega → Demo · Tienda).');
let failed = 0;
async function waitWoo(expected, label) {
  const t0 = Date.now();
  while (Date.now() - t0 < 240_000) { const s = await wooStock(); if (s === expected) return console.log(`PASS | ${label}: Woo ${sku} = ${s} en ${Math.round((Date.now() - t0) / 1000)} s (automático)`); await new Promise((r) => setTimeout(r, 5000)); }
  failed++; console.log(`FAIL | ${label}: Woo = ${await wooStock()} (esperado ${expected})`);
}
const b0 = bodega();
console.log(`transferencia ${transfer} · Bodega ${sku} = ${b0}`);
await waitWoo(b0, 'después del movimiento de Carolina');
const c = client(env);
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const rpc = async (fn, args) => { const r = await c.rest('POST', `rpc/${fn}`, { token: owner.token, body: args }); if (!r.ok) throw new Error(`${fn}: ${r.json?.message}`); };
await rpc('f360_receive_transfer', { p_idempotency_key: crypto.randomUUID(), p_transfer_id: transfer, p_lines: [{ variant_id: variant, quantity: 0 }] });
await rpc('f360_resolve_transfer_difference', { p_idempotency_key: crypto.randomUUID(), p_transfer_id: transfer, p_lines: [{ variant_id: variant, quantity: 1, action: 'return' }], p_reason: 'Prueba de aceptación de Carolina: se regresa el par a Bodega' });
console.log(`regresado: Bodega ${sku} = ${bodega()}`);
await waitWoo(b0 + 1, 'después de regresar el par');
process.exit(failed ? 1 : 0);
