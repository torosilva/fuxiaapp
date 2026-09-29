// STAGING ONLY — C3 end to end under REAL concurrency (separate committed transactions through PostgREST).
// Synthetic fixtures only: channel + location 'ZZ PRUEBA C3 Tienda', its legacy rows (product "Macarena", staging test
// product), lab users C1/C2 as sellers 'ZZ PRUEBA C3 Persona A/B', a synthetic customer 'ZZ PRUEBA C3 clienta'.
// Everything is removed at the end with c3_fixtures.mjs (exact scope documented there).
// Run: scripts/s00a/run.sh ../f360/c3_concurrency.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';
import { C3_PREFIX, cleanupC3Fixtures } from './c3_fixtures.mjs';

const env = loadEnv();
// Shares lab users C1/C2 with the C3 demo ("Demo · …"): refuse while the demo exists, or its roles would be overwritten.
if (psql(`select count(*) from f360.user_roles where display_name like 'Demo · %';`, {}, { readOnly: true }).trim().split('\n').pop() !== '0'
  || psql(`select count(*) from f360.locations where name like 'Demo · %';`, {}, { readOnly: true }).trim().split('\n').pop() !== '0') {
  console.error('La demo C3 existe (usa los mismos usuarios de laboratorio). Primero: scripts/s00a/run.sh ../f360/demo_c3_cleanup.mjs'); process.exit(1);
}
const c = client(env);
const out = [];
const ok = (cond, name, detail = '') => out.push({ ok: !!cond, name, detail: String(detail).slice(0, 150) });
const rpc = (fn, args, token) => c.rest('POST', `rpc/${fn}`, { token, body: args });
const one = (sql) => psql(sql, {}, { readOnly: true }).trim().split('\n').pop();
const write = (sql) => psql(sql).trim().split('\n').pop();
const key = () => crypto.randomUUID();
const LEDGER_MISMATCHES = `WITH mv AS (SELECT variant_id, to_location_id AS loc, quantity AS q FROM f360.inventory_movements WHERE to_location_id IS NOT NULL
  UNION ALL SELECT variant_id, from_location_id, -quantity FROM f360.inventory_movements WHERE from_location_id IS NOT NULL),
  led AS (SELECT variant_id, loc, sum(q)::int AS q FROM mv GROUP BY 1, 2)
  SELECT count(*) FROM led FULL JOIN f360.inventory_balances b ON b.variant_id = led.variant_id AND b.location_id = led.loc WHERE coalesce(led.q, 0) <> coalesce(b.on_hand, 0);`;

let created = false;
try {
  const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
  const A = await c.signIn(`${PHONES.C1.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.C1));
  const B = await c.signIn(`${PHONES.C2.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.C2));
  const [v1, v2] = one(`select string_agg(v.id::text, ',' order by v.size_label) from (select v.* from f360.product_variants v join f360.products p on p.id = v.product_id
    join f360.product_colors c on c.id = v.color_id where p.name = 'Macarena' and c.name = 'Negro' and v.size_label in ('35', '36')) v;`).split(',');
  created = true;
  // legacy store with 1 pair of Negro 35 (the last pair) and 3 of Negro 36; a synthetic customer card
  const ch = write(`insert into public.channels (name, type, active) values ('${C3_PREFIX}Canal', 'store', true) returning id;`);
  write(`insert into public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) values
    ('${ch}', 'Macarena', '35', 'Negro', 2000, 1, 0), ('${ch}', 'Macarena', '36', 'Negro', 2000, 3, 0) returning 1;`);
  const cust = write(`insert into public.customers (phone, name, country, role) values ('+15550108992', '${C3_PREFIX}clienta', 'MX', 'customer') returning id;`);
  const qr = `ZZC3-${Date.now()}`;
  const card = write(`insert into public.loyalty_cards (customer_id, qr_code, total_points, pairs_count) values ('${cust}', '${qr}', 0, 0) returning id;`);
  const L = (await rpc('f360_create_location', { p_name: `${C3_PREFIX}Tienda`, p_type: 'store', p_legacy_channel_id: ch }, owner.token)).json.id;
  for (const [u, n, pin] of [[A, 'Persona A', '2468'], [B, 'Persona B', '1357']]) {
    await rpc('f360_set_user_role', { p_auth_user_id: u.uid, p_role: 'seller', p_display_name: `${C3_PREFIX}${n}` }, owner.token);
    await rpc('f360_set_location_assignment', { p_auth_user_id: u.uid, p_location_id: L, p_active: true }, owner.token);
    await rpc('f360_set_seller_pin', { p_auth_user_id: u.uid, p_pin: pin }, owner.token);
  }
  const ciBefore = one(`select md5(string_agg(c::text, '|' order by id)) from public.channel_inventory c where channel_id = '${ch}';`);

  // C2 + cutover with double control
  await rpc('f360_propose_legacy_mapping', { p_location_id: L }, owner.token);
  for (const id of one(`select string_agg(channel_inventory_id::text, ',') from f360.legacy_inventory_map where location_id = '${L}';`).split(','))
    await rpc('f360_review_legacy_mapping', { p_channel_inventory_id: id, p_decision: 'confirmar' }, owner.token);
  const C = (await rpc('f360_start_cutover', { p_idempotency_key: key(), p_location_id: L }, owner.token)).json.id;
  // a legacy sale racing the cutover start is impossible afterwards: the legacy stock is frozen
  const tokA0 = (await rpc('f360_start_seller_shift', { p_location_id: L, p_pin: '2468' }, A.token)).json.token;
  const late = await rpc('f360_record_store_sale', { p_token: tokA0, p_idempotency_key: key(), p_lines: [{ channel_inventory_id: one(`select id from public.channel_inventory where channel_id = '${ch}' limit 1;`), quantity: 1 }], p_payment_method: 'cash' }, A.token);
  ok(!late.ok && /corte/.test(late.json?.message ?? ''), 'legacy sale after the cutover started → refused', late.json?.message);
  await rpc('f360_cutover_count', { p_cutover_id: C, p_lines: [{ variant_id: v1, quantity: 1 }, { variant_id: v2, quantity: 3 }] }, A.token);
  await rpc('f360_cutover_finish_count', { p_cutover_id: C }, A.token);
  const ver = await rpc('f360_cutover_verify', { p_cutover_id: C, p_lines: [{ variant_id: v1, quantity: 1 }, { variant_id: v2, quantity: 3 }] }, B.token);
  ok(ver.json?.status === 'ready', 'count by A, blind verification by B → ready', ver.json?.status ?? ver.json?.message);

  // 1 · two operators complete at the same time (different keys) → exactly one opening balance
  const [c1, c2] = await Promise.all([rpc('f360_complete_cutover', { p_idempotency_key: key(), p_cutover_id: C }, owner.token),
    rpc('f360_complete_cutover', { p_idempotency_key: key(), p_cutover_id: C }, owner.token)]);
  const wins = [c1, c2].filter((r) => r.ok && r.json?.ok).length;
  const openings = one(`select count(*) from f360.inventory_events where event_type = 'OPENING_PHYSICAL_COUNT' and business_reference_id = '${L}';`);
  ok(wins === 1 && openings === '1' && one(`select ledger_authority from f360.locations where id = '${L}';`) === 'f360',
    'two simultaneous completions → exactly one opening balance; location f360', `wins=${wins} openings=${openings} loser="${[c1, c2].find((r) => !(r.ok && r.json?.ok))?.json?.message ?? ''}"`);
  const bal = (v) => Number(one(`select coalesce((select on_hand from f360.inventory_balances where location_id = '${L}' and variant_id = '${v}'), 0);`));
  ok(bal(v1) === 1 && bal(v2) === 3, 'opening balances = verified count', `35:${bal(v1)} 36:${bal(v2)}`);

  // 2 · two sellers sell the LAST pair at the same time
  const tokA = (await rpc('f360_start_seller_shift', { p_location_id: L, p_pin: '2468' }, A.token)).json.token;
  const tokB = (await rpc('f360_start_seller_shift', { p_location_id: L, p_pin: '1357' }, B.token)).json.token;
  const sale = (tok, u, lines, extra = {}) => rpc('f360_record_store_sale', { p_token: tok, p_idempotency_key: key(), p_lines: lines, p_payment_method: 'cash', ...extra }, u.token);
  const [s1, s2] = await Promise.all([sale(tokA, A, [{ variant_id: v1, quantity: 1 }]), sale(tokB, B, [{ variant_id: v1, quantity: 1 }])]);
  const sw = [s1, s2].filter((r) => r.ok && r.json?.ok).length;
  ok(sw === 1 && bal(v1) === 0, 'two simultaneous F360 sales of the last pair → exactly one; never negative',
    `wins=${sw} left=${bal(v1)} loser="${[s1, s2].find((r) => !r.ok)?.json?.message ?? ''}"`);

  // 3 · double tap in flight (same key)
  const k3 = key();
  const body3 = { p_token: tokA, p_idempotency_key: k3, p_lines: [{ variant_id: v2, quantity: 1 }], p_payment_method: 'card' };
  const [d1, d2] = await Promise.all([1, 2].map(() => rpc('f360_record_store_sale', body3, A.token)));
  ok(d1.ok && d2.ok && d1.json.sale_id === d2.json.sale_id && one(`select count(*) from public.offline_sales where idempotency_key = '${k3}';`) === '1' && bal(v2) === 2,
    'simultaneous double tap (same key) → one sale, stock −1 once', `${d1.json?.sale_id ?? d1.json?.message} / ${d2.json?.sale_id ?? d2.json?.message}`);

  // 4 · two sellers sell to the SAME customer at the same time → loyalty exact
  const [l1, l2] = await Promise.all([sale(tokA, A, [{ variant_id: v2, quantity: 1 }], { p_customer_qr: qr }), sale(tokB, B, [{ variant_id: v2, quantity: 1 }], { p_customer_qr: qr })]);
  const pts = one(`select total_points from public.loyalty_cards where id = '${card}';`);
  ok(l1.json?.ok && l2.json?.ok && pts === '200' && bal(v2) === 0, 'two simultaneous sales to one customer → +200 exactly, stock exact', `points=${pts} left=${bal(v2)}`);

  // 5 · one fact per sale, one SALE event per sale, legacy untouched
  const sales = one(`select count(*) from public.offline_sales where location_id = '${L}' and sale_event_id is not null;`);
  const facts = one(`select count(*) from f360.store_sale_facts where location_id = '${L}' and source = 'store_f360';`);
  const events = one(`select count(*) from f360.inventory_events e where e.event_type = 'SALE' and e.business_reference_id in (select id::text from public.offline_sales where location_id = '${L}');`);
  ok(sales === '4' && facts === '4' && events === '4', 'sales = Growth/C360 facts = SALE events (4 each)', `sales=${sales} facts=${facts} events=${events}`);
  ok(one(`select md5(string_agg(c::text, '|' order by id)) from public.channel_inventory c where channel_id = '${ch}';`) === ciBefore, 'channel_inventory never written (cutover + F360 sales)', '');
  ok(one(LEDGER_MISMATCHES) === '0', 'balances = ledger (every variant, every location)', '');
} catch (e) {
  ok(false, 'harness error', e.message);
} finally {
  if (created) {
    const left = cleanupC3Fixtures();
    ok(left === '0', 'synthetic fixtures removed', `left=${left}`);
    ok(one(LEDGER_MISMATCHES) === '0', 'balances = ledger after cleanup', '');
  }
}
for (const r of out) console.log(`${r.ok ? 'PASS' : 'FAIL'} | ${r.name} | ${r.detail}`);
const failed = out.filter((r) => !r.ok).length;
console.log(failed ? `\n${failed} FAILED` : '\nALL PASS');
process.exit(failed ? 1 : 0);
