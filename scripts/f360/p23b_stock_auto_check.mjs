// STAGING ONLY — P2.3B: proves the automatic stock push (pg_cron → f360-woo-sync) end to end, with no manual call.
// Moves 1 pair of Macarena Nude 37 out of Bodega CDMX with a real transfer (Bodega → "En camino"), waits for Woo to show it
// by itself, then returns the pair (receive 0 → difference → "regresar al origen") and waits for Woo to show it back.
// Net effect: Bodega unchanged; the ledger keeps the audited transfer. Run: scripts/s00a/run.sh ../f360/p23b_stock_auto_check.mjs
import { readFileSync } from 'node:fs';
import { client, loadEnv, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^WOO_(BASE_URL|USER|SECRET)=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
if (new URL(W.WOO_BASE_URL).hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not staging4');
const auth = 'Basic ' + Buffer.from(`${W.WOO_USER}:${W.WOO_SECRET}`).toString('base64');
const wooStock = async () => (await (await fetch(`${W.WOO_BASE_URL}/wp-json/wc/v3/products/3621/variations/3624`, { headers: { Authorization: auth } })).json()).stock_quantity;
const one = (sql) => psql(sql, {}, { readOnly: true }).trim().split('\n').pop();
const c = client(env);
const rpc = async (fn, args, token) => { const r = await c.rest('POST', `rpc/${fn}`, { token, body: args }); if (!r.ok) throw new Error(`${fn}: ${r.json?.message}`); return r.json; };
const key = () => crypto.randomUUID();
const variant = one(`select v.id from f360.product_variants v join f360.products p on p.id = v.product_id join f360.product_colors c on c.id = v.color_id where p.name = 'Macarena' and c.name = 'Nude' and v.size_label = '37';`);
const bodega = one(`select id from f360.locations where name = 'Bodega CDMX';`);
const dest = one(`select id from f360.locations where name = 'Demo · Tienda';`);
const bal = () => Number(one(`select coalesce((select on_hand from f360.inventory_balances where variant_id = '${variant}' and location_id = '${bodega}'), 0);`));
async function waitWoo(expected, label) {
  const t0 = Date.now();
  while (Date.now() - t0 < 240_000) { const s = await wooStock(); if (s === expected) return console.log(`PASS | ${label}: Woo = ${s} en ${Math.round((Date.now() - t0) / 1000)} s, sin llamada manual`); await new Promise((r) => setTimeout(r, 5000)); }
  console.log(`FAIL | ${label}: Woo = ${await wooStock()} (esperado ${expected}) tras 240 s`); process.exitCode = 1;
}
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const b0 = bal(), w0 = await wooStock();
console.log(`antes: Bodega ${b0} · Woo ${w0}`);
if (b0 !== w0 || b0 < 1) throw new Error('Bodega y Woo no coinciden al empezar; no se prueba.');
const t = (await rpc('f360_request_transfer', { p_idempotency_key: key(), p_from_location_id: bodega, p_to_location_id: dest, p_lines: [{ variant_id: variant, quantity: 1 }] }, owner.token)).id;
await rpc('f360_send_transfer', { p_idempotency_key: key(), p_transfer_id: t }, owner.token);
console.log(`enviado 1 par a "En camino": Bodega ${bal()}`);
await waitWoo(b0 - 1, 'salida de Bodega');
await rpc('f360_receive_transfer', { p_idempotency_key: key(), p_transfer_id: t, p_lines: [{ variant_id: variant, quantity: 0 }] }, owner.token);
await rpc('f360_resolve_transfer_difference', { p_idempotency_key: key(), p_transfer_id: t, p_lines: [{ variant_id: variant, quantity: 1, action: 'return' }], p_reason: 'Prueba P2.3B: envío automático de existencias a Woo (se regresa el par)' }, owner.token);
console.log(`regresado al origen: Bodega ${bal()}`);
await waitWoo(b0, 'regreso a Bodega');
console.log(`después: Bodega ${bal()} · Woo ${await wooStock()} · transferencia ${t}`);
