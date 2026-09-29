// STAGING ONLY — prepares the C3 DEMO for Carolina (synthetic, removable with demo_c3_cleanup.mjs):
//   "Demo · Tienda" — starts as a legacy store (legacy rows of the staging test product Macarena), C2 confirmed,
//   cutover: counted by "Demo · Vendedora" (lab C1), verified blind by "Demo · Verificadora" (lab C2), completed by Carolina
//   → the store now sells from Fuxia 360 with an opening balance that came ONLY from the verified count.
//   "Demo · Clienta" (lab phone) with a loyalty card. NO sale is made here: the sale is the live moment (demo_c3_sale.mjs).
// Refuses if anything named "Demo · …" already exists. Run: scripts/s00a/run.sh ../f360/demo_c3_prepare.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';

export const DEMO = 'Demo · ';
const env = loadEnv();
const c = client(env);
const rpc = async (fn, args, token) => { const r = await c.rest('POST', `rpc/${fn}`, { token, body: args }); if (!r.ok || r.json?.ok === false) throw new Error(`${fn}: ${r.json?.message ?? r.json?.error}`); return r.json; };
const one = (sql) => psql(sql).trim().split('\n').pop();
if (one(`select (select count(*) from f360.locations where name like '${DEMO}%') + (select count(*) from public.channels where name like '${DEMO}%')
  + (select count(*) from public.customers where name like '${DEMO}%') + (select count(*) from f360.user_roles where display_name like '${DEMO}%');`) !== '0') {
  console.error('La demo ya existe. Para empezar de cero: scripts/s00a/run.sh ../f360/demo_c3_cleanup.mjs'); process.exit(1);
}
if (one(`select count(*) from f360.user_roles where display_name like 'ZZ PRUEBA C3 %';`) !== '0') {
  console.error('Hay fixtures de prueba C3 activos con los mismos usuarios. Primero: scripts/s00a/run.sh ../f360/c3_cleanup.mjs'); process.exit(1);
}
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const A = await c.signIn(`${PHONES.C1.slice(1)}@fuxia.app`, phonePassword(env, PHONES.C1));
const B = await c.signIn(`${PHONES.C2.slice(1)}@fuxia.app`, phonePassword(env, PHONES.C2));
const vid = (color, size) => one(`select v.id from f360.product_variants v join f360.products p on p.id = v.product_id join f360.product_colors c on c.id = v.color_id
  where p.name = 'Macarena' and c.name = '${color}' and v.size_label = '${size}';`);
// what the store physically has (legacy system says the same; the opening balance comes from the COUNT below)
const STOCK = [['Nude', '36', 2], ['Nude', '37', 3], ['Nude', '38', 2], ['Negro', '37', 2], ['Rojo', '37', 1]];
const ch = one(`insert into public.channels (name, type, active) values ('${DEMO}Canal tienda', 'store', true) returning id;`);
one(`insert into public.channel_inventory (channel_id, product_name, color, size, price, stock, sold) values
  ${STOCK.map(([co, s, q]) => `('${ch}', 'Macarena', '${co}', '${s}', 2800, ${q}, 0)`).join(', ')} returning 1;`);
const cust = one(`insert into public.customers (phone, name, country, role) values ('+15550108994', '${DEMO}Clienta', 'MX', 'customer') returning id;`);
const qr = 'DEMO-C3-CLIENTA';
one(`insert into public.loyalty_cards (customer_id, qr_code, total_points, pairs_count) values ('${cust}', '${qr}', 0, 0) returning id;`);
const L = (await rpc('f360_create_location', { p_name: `${DEMO}Tienda`, p_type: 'store', p_legacy_channel_id: ch }, owner.token)).id;
for (const [u, n, pin] of [[A, 'Vendedora', '2468'], [B, 'Verificadora', '1357']]) {
  await rpc('f360_set_user_role', { p_auth_user_id: u.uid, p_role: 'seller', p_display_name: `${DEMO}${n}` }, owner.token);
  await rpc('f360_set_location_assignment', { p_auth_user_id: u.uid, p_location_id: L, p_active: true }, owner.token);
  await rpc('f360_set_seller_pin', { p_auth_user_id: u.uid, p_pin: pin }, owner.token);
}
await rpc('f360_propose_legacy_mapping', { p_location_id: L }, owner.token);
for (const id of one(`select string_agg(channel_inventory_id::text, ',') from f360.legacy_inventory_map where location_id = '${L}';`).split(','))
  await rpc('f360_review_legacy_mapping', { p_channel_inventory_id: id, p_decision: 'confirmar' }, owner.token);
const C = (await rpc('f360_start_cutover', { p_idempotency_key: crypto.randomUUID(), p_location_id: L, p_note: 'Demo C3' }, owner.token)).id;
const lines = STOCK.map(([co, s, q]) => ({ variant_id: vid(co, s), quantity: q }));
await rpc('f360_cutover_count', { p_cutover_id: C, p_lines: lines }, A.token);
await rpc('f360_cutover_finish_count', { p_cutover_id: C }, A.token);
await rpc('f360_cutover_verify', { p_cutover_id: C, p_lines: lines }, B.token);
const done = await rpc('f360_complete_cutover', { p_idempotency_key: crypto.randomUUID(), p_cutover_id: C }, owner.token);
console.log(`Demo lista: "${DEMO}Tienda" migrada (${done.status}, ${done.counted_pairs} pares por conteo verificado).`);
console.log(`Macarena Nude 37 en la tienda: ${one(`select on_hand from f360.inventory_balances where location_id = '${L}' and variant_id = '${vid('Nude', '37')}';`)} pares.`);
console.log('Venta en vivo: scripts/s00a/run.sh ../f360/demo_c3_sale.mjs');
