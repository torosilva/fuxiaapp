// STAGING ONLY — S0.3/S0.5 real concurrency (separate committed transactions racing each other).
// Synthetic fixtures (channel "ZZ PRUEBA S0.3 concurrencia", its stock rows, a legacy location, lab seller S1's role/
// assignment/PIN, a synthetic customer + card) are created here and the EXACT rows are removed at the end. The
// append-only guard on offline_sale_items is lifted ONLY inside that cleanup transaction, ONLY for this channel.
// Audit rows (loyalty_apply_audit, seller events, access changes) stay — append-only by design.
// Run: scripts/s00a/run.sh ../f360/s03_concurrency.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const out = [];
const ok = (cond, name, detail = '') => out.push({ ok: !!cond, name, detail: String(detail).slice(0, 120) });
const rpc = (fn, args, token) => c.rest('POST', `rpc/${fn}`, { token, body: args });
const one = (sql) => psql(sql).trim().split('\n').pop();
const PIN = String(1000 + Math.floor(Math.random() * 9000));
const f = {};

try {
  const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
  const s1 = await c.signIn(`${PHONES.S1.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.S1));
  f.s1 = s1.uid;
  f.ch = one(`insert into public.channels (name, type, active) values ('ZZ PRUEBA S0.3 concurrencia', 'store', true) returning id;`);
  f.last = one(`insert into public.channel_inventory (channel_id, product_name, sku, size, color, price, stock, sold) values ('${f.ch}', 'ZZ Último par', 'ZZ-LAST', '37', 'Negro', 2800, 1, 0) returning id;`);
  f.plenty = one(`insert into public.channel_inventory (channel_id, product_name, sku, size, color, price, stock, sold) values ('${f.ch}', 'ZZ Muchos', 'ZZ-MANY', '38', 'Nude', 1900, 50, 0) returning id;`);
  f.cust = one(`insert into public.customers (phone, name, country, role) values ('+15550108990', 'ZZ S03 clienta concurrencia', 'MX', 'customer') returning id;`);
  f.card = one(`insert into public.loyalty_cards (customer_id, qr_code, total_points, pairs_count) values ('${f.cust}', 'ZZS03-CONC-${Date.now()}', 0, 0) returning id;`);
  const qr = one(`select qr_code from public.loyalty_cards where id = '${f.card}';`);
  const loc = await rpc('f360_create_location', { p_name: 'ZZ PRUEBA S0.3 concurrencia (sintética)', p_type: 'store', p_legacy_channel_id: f.ch }, owner.token);
  f.loc = loc.json.id;
  await rpc('f360_set_user_role', { p_auth_user_id: s1.uid, p_role: 'seller', p_display_name: 'S1 (sintética)' }, owner.token);
  await rpc('f360_set_location_assignment', { p_auth_user_id: s1.uid, p_location_id: f.loc, p_active: true }, owner.token);
  await rpc('f360_set_seller_pin', { p_auth_user_id: s1.uid, p_pin: PIN }, owner.token);
  const shift = await rpc('f360_start_seller_shift', { p_location_id: f.loc, p_pin: PIN }, s1.token);
  const tok = shift.json.token;
  const sell = (lines, extra = {}) => rpc('f360_record_store_sale', { p_token: tok, p_idempotency_key: crypto.randomUUID(), p_lines: lines, p_payment_method: 'cash', ...extra }, s1.token);

  // 1 · two simultaneous sales for the LAST pair
  const [a, b] = await Promise.all([sell([{ channel_inventory_id: f.last, quantity: 1 }]), sell([{ channel_inventory_id: f.last, quantity: 1 }])]);
  const wins = [a, b].filter((r) => r.ok && r.json?.ok).length;
  const lastSold = one(`select sold from public.channel_inventory where id = '${f.last}';`);
  ok(wins === 1 && lastSold === '1', 'two simultaneous sales of the last pair → exactly one succeeds; stock never negative',
     `wins=${wins} sold=${lastSold} loser="${[a, b].find((r) => !r.ok)?.json?.message ?? ''}"`);

  // 2 · two simultaneous sales with the SAME customer card (loyalty concurrency through the sale)
  const [c1r, c2r] = await Promise.all([sell([{ channel_inventory_id: f.plenty, quantity: 1 }], { p_customer_qr: qr }), sell([{ channel_inventory_id: f.plenty, quantity: 1 }], { p_customer_qr: qr })]);
  const pts2 = one(`select total_points from public.loyalty_cards where id = '${f.card}';`);
  ok(c1r.json?.ok && c2r.json?.ok && pts2 === '200', 'two simultaneous sales to the same card → 100 + 100 = 200 (no lost update)', `points=${pts2}`);

  // 3 · ten simultaneous direct loyalty credits on the same card
  await Promise.all(Array.from({ length: 10 }, (_, i) => c.svcRest('POST', 'rpc/loyalty_apply', { body: { p_card_id: f.card, p_lines: [{ quantity: 1, sku: 'ZZ-C' }],
    p_amount: 1, p_channel: 'store', p_ref_type: 'conc', p_ref_id: String(i), p_idempotency_key: `conc:${f.card}:${i}`, p_actor: { type: 'test' } } })));
  const pts3 = one(`select total_points from public.loyalty_cards where id = '${f.card}';`);
  ok(pts3 === '1200', '10 simultaneous loyalty credits → exactly +1000', `points=${pts3}`);

  // 4 · double tap in flight: the same idempotency key twice AT THE SAME TIME
  const key = crypto.randomUUID();
  const body = { p_token: tok, p_idempotency_key: key, p_lines: [{ channel_inventory_id: f.plenty, quantity: 1 }], p_payment_method: 'card' };
  const [d1, d2] = await Promise.all([rpc('f360_record_store_sale', body, s1.token), rpc('f360_record_store_sale', body, s1.token)]);
  const nSales = one(`select count(*) from public.offline_sales where idempotency_key = '${key}';`);
  ok(nSales === '1' && d1.json?.ok && d2.json?.ok && d1.json.sale_id === d2.json.sale_id, 'simultaneous double tap (same key) → one sale; both calls get the same sale',
     `sales=${nSales} d1=${d1.json?.sale_id ?? d1.json?.message} d2=${d2.json?.sale_id ?? d2.json?.message}`);
  const plentySold = one(`select sold from public.channel_inventory where id = '${f.plenty}';`);
  ok(plentySold === '3', 'stock of the busy row reflects exactly the successful sales', `sold=${plentySold}`);
  const facts = one(`select count(*) from f360.store_sale_facts where legacy_channel_id = '${f.ch}';`);
  ok(facts === '4', 'Growth facts = one per successful sale', `facts=${facts}`);
} finally {
  if (f.ch) {
    psql(`BEGIN;
      ALTER TABLE public.offline_sale_items DISABLE TRIGGER offline_sale_items_append_only;
      DELETE FROM public.offline_sale_items WHERE sale_id IN (SELECT id FROM public.offline_sales WHERE channel_id = '${f.ch}');
      ALTER TABLE public.offline_sale_items ENABLE TRIGGER offline_sale_items_append_only;
      DELETE FROM public.purchase_items WHERE transaction_id IN (SELECT id FROM public.transactions WHERE loyalty_card_id = '${f.card ?? '00000000-0000-0000-0000-000000000000'}');
      DELETE FROM public.transactions WHERE loyalty_card_id = '${f.card ?? '00000000-0000-0000-0000-000000000000'}';
      DELETE FROM public.offline_sales WHERE channel_id = '${f.ch}';
      DELETE FROM public.loyalty_cards WHERE id = '${f.card ?? '00000000-0000-0000-0000-000000000000'}';
      DELETE FROM public.customers WHERE id = '${f.cust ?? '00000000-0000-0000-0000-000000000000'}';
      DELETE FROM f360.seller_sessions WHERE auth_user_id = '${f.s1}';
      DELETE FROM f360.seller_credentials WHERE auth_user_id = '${f.s1}';
      DELETE FROM f360.location_assignments WHERE auth_user_id = '${f.s1}' AND location_id = '${f.loc ?? '00000000-0000-0000-0000-000000000000'}';
      DELETE FROM f360.user_roles WHERE auth_user_id = '${f.s1}' AND display_name = 'S1 (sintética)';
      DELETE FROM f360.locations WHERE id = '${f.loc ?? '00000000-0000-0000-0000-000000000000'}' AND name LIKE 'ZZ PRUEBA S0.3%';
      DELETE FROM public.channel_inventory WHERE channel_id = '${f.ch}';
      DELETE FROM public.channels WHERE id = '${f.ch}' AND name LIKE 'ZZ PRUEBA S0.3%';
      COMMIT;`);
    const left = one(`select (select count(*) from public.channels where name like 'ZZ PRUEBA S0.3%') + (select count(*) from f360.locations where name like 'ZZ PRUEBA S0.3%') + (select count(*) from public.customers where name like 'ZZ S03 clienta%');`);
    out.push({ ok: left === '0', name: 'synthetic fixtures removed', detail: `left=${left}` });
  }
}
for (const r of out) console.log(`${r.ok ? 'PASS' : 'FAIL'} | ${r.name} | ${r.detail}`);
const failed = out.filter((r) => !r.ok).length;
console.log(failed ? `\n${failed} FAILED` : '\nALL PASS');
process.exit(failed ? 1 : 0);
