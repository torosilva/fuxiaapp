// STAGING ONLY — THE live moment of the C3 demo: "Demo · Vendedora" sells 1 Macarena Nude 37 to "Demo · Clienta" (card),
// through exactly the RPCs the store app calls: start shift with PIN → catalog → sale with the customer's QR.
// Prereq: demo_c3_prepare.mjs. Run: scripts/s00a/run.sh ../f360/demo_c3_sale.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';

const DEMO = 'Demo · ';
const env = loadEnv();
const c = client(env);
const rpc = async (fn, args, token) => { const r = await c.rest('POST', `rpc/${fn}`, { token, body: args }); if (!r.ok || r.json?.ok === false) throw new Error(`${fn}: ${r.json?.message ?? r.json?.error}`); return r.json; };
const one = (sql) => psql(sql, {}, { readOnly: true }).trim().split('\n').pop();
const L = one(`select id from f360.locations where name = '${DEMO}Tienda' and ledger_authority = 'f360';`);
if (!L) { console.error('Primero: scripts/s00a/run.sh ../f360/demo_c3_prepare.mjs'); process.exit(1); }
const seller = await c.signIn(`${PHONES.C1.slice(1)}@fuxia.app`, phonePassword(env, PHONES.C1));
const shift = await rpc('f360_start_seller_shift', { p_location_id: L, p_pin: '2468' }, seller.token);
const catalog = await rpc('f360_shift_catalog', { p_token: shift.token }, seller.token);
const item = catalog.items.find((i) => i.product_name === 'Macarena' && i.color === 'Nude' && i.size === '37');
if (!item) { console.error('No queda Macarena Nude 37 en la tienda demo.'); process.exit(1); }
const points0 = Number(one(`select total_points from public.loyalty_cards where qr_code = 'DEMO-C3-CLIENTA';`));
const sale = await rpc('f360_record_store_sale', { p_token: shift.token, p_idempotency_key: crypto.randomUUID(),
  p_lines: [{ variant_id: item.variant_id, quantity: 1 }], p_payment_method: 'card', p_customer_qr: 'DEMO-C3-CLIENTA' }, seller.token);
const after = one(`select on_hand from f360.inventory_balances where location_id = '${L}' and variant_id = '${item.variant_id}';`);
const points1 = Number(one(`select total_points from public.loyalty_cards where qr_code = 'DEMO-C3-CLIENTA';`));
console.log(`Venta registrada: ${sale.seller} vendió 1 Macarena Nude 37 en ${sale.location} por $${Number(sale.total).toLocaleString('es-MX')} (tarjeta).`);
console.log(`Clienta: ${DEMO}Clienta · puntos ${points0} → ${points1} (+${sale.points}).`);
console.log(`Inventario Macarena Nude 37: ${item.available} → ${after}.`);
console.log('Ahora en Fuxia 360: Ventas → Hoy.');
