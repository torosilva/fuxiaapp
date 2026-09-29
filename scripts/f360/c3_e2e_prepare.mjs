// STAGING ONLY — prepares the synthetic store for the C3 closed-loop E2E (admin-web/e2e/c3-closed-loop.spec.ts):
// legacy store 'ZZ PRUEBA C3 Tienda' with legacy rows (staging test product "Macarena"), C2 confirmed, cutover counted by A
// (lab C1), verified blind by B (lab C2), completed by the owner → opening balance from the count ONLY. A synthetic
// customer card. Writes the ids the spec needs to $CLAUDE_JOB_DIR/tmp or /tmp. Remove with: c3_cleanup.mjs
import { writeFileSync } from 'node:fs';
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';
import { C3_PREFIX } from './c3_fixtures.mjs';

const env = loadEnv();
// Shares lab users C1/C2 with the C3 demo ("Demo · …"): refuse while the demo exists, or its roles would be overwritten.
if (psql(`select count(*) from f360.user_roles where display_name like 'Demo · %';`, {}, { readOnly: true }).trim().split('\n').pop() !== '0'
  || psql(`select count(*) from f360.locations where name like 'Demo · %';`, {}, { readOnly: true }).trim().split('\n').pop() !== '0') {
  console.error('La demo C3 existe (usa los mismos usuarios de laboratorio). Primero: scripts/s00a/run.sh ../f360/demo_c3_cleanup.mjs'); process.exit(1);
}
const c = client(env);
const rpc = async (fn, args, token) => { const r = await c.rest('POST', `rpc/${fn}`, { token, body: args }); if (!r.ok || r.json?.ok === false) throw new Error(`${fn}: ${r.json?.message ?? r.json?.error}`); return r.json; };
const one = (sql) => psql(sql).trim().split('\n').pop();
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const A = await c.signIn(`${PHONES.C1.slice(1)}@fuxia.app`, phonePassword(env, PHONES.C1));
const B = await c.signIn(`${PHONES.C2.slice(1)}@fuxia.app`, phonePassword(env, PHONES.C2));
const [v35, v36] = one(`select string_agg(v.id::text, ',' order by v.size_label) from f360.product_variants v join f360.products p on p.id = v.product_id
  join f360.product_colors c on c.id = v.color_id where p.name = 'Macarena' and c.name = 'Negro' and v.size_label in ('35', '36');`).split(',');
const ch = one(`insert into public.channels (name, type, active) values ('${C3_PREFIX}Canal', 'store', true) returning id;`);
one(`insert into public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) values
  ('${ch}', 'Macarena', '35', 'Negro', 2000, 2, 0), ('${ch}', 'Macarena', '36', 'Negro', 2000, 1, 0) returning 1;`);
const cust = one(`insert into public.customers (phone, name, country, role) values ('+15550108993', '${C3_PREFIX}clienta', 'MX', 'customer') returning id;`);
const qr = `ZZC3E2E-${Date.now()}`;
one(`insert into public.loyalty_cards (customer_id, qr_code, total_points, pairs_count) values ('${cust}', '${qr}', 0, 0) returning id;`);
const L = (await rpc('f360_create_location', { p_name: `${C3_PREFIX}Tienda`, p_type: 'store', p_legacy_channel_id: ch }, owner.token)).id;
for (const [u, n, pin] of [[A, 'Vendedora A', '2468'], [B, 'Vendedora B', '1357']]) {
  await rpc('f360_set_user_role', { p_auth_user_id: u.uid, p_role: 'seller', p_display_name: `${C3_PREFIX}${n}` }, owner.token);
  await rpc('f360_set_location_assignment', { p_auth_user_id: u.uid, p_location_id: L, p_active: true }, owner.token);
  await rpc('f360_set_seller_pin', { p_auth_user_id: u.uid, p_pin: pin }, owner.token);
}
await rpc('f360_propose_legacy_mapping', { p_location_id: L }, owner.token);
for (const id of one(`select string_agg(channel_inventory_id::text, ',') from f360.legacy_inventory_map where location_id = '${L}';`).split(','))
  await rpc('f360_review_legacy_mapping', { p_channel_inventory_id: id, p_decision: 'confirmar' }, owner.token);
const C = (await rpc('f360_start_cutover', { p_idempotency_key: crypto.randomUUID(), p_location_id: L, p_note: 'E2E sintético' }, owner.token)).id;
await rpc('f360_cutover_count', { p_cutover_id: C, p_lines: [{ variant_id: v35, quantity: 2 }, { variant_id: v36, quantity: 1 }] }, A.token);
await rpc('f360_cutover_finish_count', { p_cutover_id: C }, A.token);
await rpc('f360_cutover_verify', { p_cutover_id: C, p_lines: [{ variant_id: v35, quantity: 2 }, { variant_id: v36, quantity: 1 }] }, B.token);
const done = await rpc('f360_complete_cutover', { p_idempotency_key: crypto.randomUUID(), p_cutover_id: C }, owner.token);
const file = `${process.env.CLAUDE_JOB_DIR ? process.env.CLAUDE_JOB_DIR + '/tmp' : '/tmp'}/c3_e2e.json`;
writeFileSync(file, JSON.stringify({ location_id: L, location: `${C3_PREFIX}Tienda`, v35, v36, qr, cutover: C, status: done.status }));
console.log(`prepared: cutover ${done.status}; ids in ${file}`);
