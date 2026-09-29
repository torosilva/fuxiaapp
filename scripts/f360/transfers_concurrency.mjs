// STAGING ONLY — Transfers under REAL concurrency (separate committed transactions racing through PostgREST).
// Synthetic fixtures only: two locations 'ZZ PRUEBA T Origen/Destino', lab seller S1 as 'ZZ PRUEBA Vendedora', stock of
// the existing staging test product "Paula" received into the synthetic origin. Everything is removed at the end with
// transfer_fixtures.mjs (exact scope documented there).
// Run: scripts/s00a/run.sh ../f360/transfers_concurrency.mjs
import { client, loadEnv, phonePassword, PHONES, psql } from '../s00a/lib.mjs';
import { cleanupTransferFixtures, ZZ_PREFIX } from './transfer_fixtures.mjs';

const env = loadEnv();
const c = client(env);
const out = [];
const ok = (cond, name, detail = '') => out.push({ ok: !!cond, name, detail: String(detail).slice(0, 140) });
const rpc = (fn, args, token) => c.rest('POST', `rpc/${fn}`, { token, body: args });
const one = (sql) => psql(sql, {}, { readOnly: true }).trim().split('\n').pop();
const key = () => crypto.randomUUID();
const LEDGER_MISMATCHES = `WITH mv AS (SELECT variant_id, to_location_id AS loc, quantity AS q FROM f360.inventory_movements WHERE to_location_id IS NOT NULL
  UNION ALL SELECT variant_id, from_location_id, -quantity FROM f360.inventory_movements WHERE from_location_id IS NOT NULL),
  led AS (SELECT variant_id, loc, sum(q)::int AS q FROM mv GROUP BY 1, 2)
  SELECT count(*) FROM led FULL JOIN f360.inventory_balances b ON b.variant_id = led.variant_id AND b.location_id = led.loc WHERE coalesce(led.q, 0) <> coalesce(b.on_hand, 0);`;
const ciHash = () => one(`select md5(coalesce(string_agg(c::text, '|' order by c.id), '')) from public.channel_inventory c;`);

let created = false;
try {
  const ci0 = ciHash();
  const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
  const s1 = await c.signIn(`${PHONES.S1.replace('+', '')}@fuxia.app`, phonePassword(env, PHONES.S1));
  const variant = one(`select v.id from f360.product_variants v join f360.products p on p.id = v.product_id join f360.product_colors c on c.id = v.color_id
    where p.name = 'Paula' and c.name = 'Camel' and v.size_label = '37';`);
  created = true;
  const A = (await rpc('f360_create_location', { p_name: `${ZZ_PREFIX}Origen`, p_type: 'warehouse' }, owner.token)).json.id;
  const B = (await rpc('f360_create_location', { p_name: `${ZZ_PREFIX}Destino`, p_type: 'store' }, owner.token)).json.id;
  await rpc('f360_set_user_role', { p_auth_user_id: s1.uid, p_role: 'seller', p_display_name: 'ZZ PRUEBA Vendedora' }, owner.token);
  await rpc('f360_set_location_assignment', { p_auth_user_id: s1.uid, p_location_id: B, p_active: true }, owner.token);
  const bal = (loc) => Number(one(`select coalesce((select on_hand from f360.inventory_balances where variant_id = '${variant}' and location_id = ${loc === 'transit' ? 'f360.transit_location()' : `'${loc}'`}), 0);`));
  const receive = (n) => rpc('f360_receive_inventory', { p_idempotency_key: key(), p_location_id: A, p_lines: [{ variant_id: variant, quantity: n }] }, owner.token);
  const request = (qty) => rpc('f360_request_transfer', { p_idempotency_key: key(), p_from_location_id: A, p_to_location_id: B, p_lines: [{ variant_id: variant, quantity: qty }] }, owner.token);
  const transitBefore = bal('transit');

  // 1 · two transfers race for the LAST pair at the origin
  await receive(1);
  const [t1, t2] = [(await request(1)).json.id, (await request(1)).json.id];
  const [r1, r2] = await Promise.all([rpc('f360_send_transfer', { p_idempotency_key: key(), p_transfer_id: t1 }, owner.token),
    rpc('f360_send_transfer', { p_idempotency_key: key(), p_transfer_id: t2 }, owner.token)]);
  const wins = [r1, r2].filter((r) => r.ok).length;
  ok(wins === 1 && bal(A) === 0 && bal('transit') === transitBefore + 1, 'two simultaneous sends for the last pair → exactly one; origin never negative',
    `wins=${wins} origin=${bal(A)} loser="${[r1, r2].find((r) => !r.ok)?.json?.message ?? ''}"`);
  const winner = r1.ok ? t1 : t2;
  const loser = r1.ok ? t2 : t1;
  ok(one(`select status from f360.transfers where id = '${loser}';`) === 'requested', 'losing transfer stays "requested" (nothing moved)', '');

  // 2 · simultaneous double-click on SEND with the same key
  await receive(2);
  const t3 = (await request(2)).json.id;
  const k3 = key();
  const [d1, d2] = await Promise.all([1, 2].map(() => rpc('f360_send_transfer', { p_idempotency_key: k3, p_transfer_id: t3 }, owner.token)));
  const ev3 = one(`select count(*) from f360.inventory_events where idempotency_key = '${k3}';`);
  ok(d1.ok && d2.ok && ev3 === '1' && bal(A) === 0 && [d1, d2].some((d) => d.json.replayed), 'simultaneous double-click on send (same key) → one event; both calls succeed',
    `events=${ev3} origin=${bal(A)} replayed=${d1.json?.replayed}/${d2.json?.replayed}`);

  // 3 · two people confirm the same receipt at the same time (different keys)
  const [x1, x2] = await Promise.all([rpc('f360_receive_transfer', { p_idempotency_key: key(), p_transfer_id: t3 }, s1.token),
    rpc('f360_receive_transfer', { p_idempotency_key: key(), p_transfer_id: t3 }, owner.token)]);
  ok([x1, x2].filter((r) => r.ok).length === 1 && bal(B) === 2, 'simultaneous receipts → destination +2 exactly once', `B=${bal(B)} msg="${[x1, x2].find((r) => !r.ok)?.json?.message ?? ''}"`);

  // 4 · simultaneous double-click on REQUEST with the same key
  const k4 = key();
  const body4 = { p_idempotency_key: k4, p_from_location_id: A, p_to_location_id: B, p_lines: [{ variant_id: variant, quantity: 1 }] };
  const [q1, q2] = await Promise.all([1, 2].map(() => rpc('f360_request_transfer', body4, owner.token)));
  ok(q1.ok && q2.ok && q1.json.id === q2.json.id && one(`select count(*) from f360.transfer_changes where idempotency_key = '${k4}';`) === '1',
    'simultaneous double-click on request (same key) → one transfer', `${q1.json?.number}/${q2.json?.number}`);

  // finish the winner so every synthetic pair is out of "En camino"
  await rpc('f360_receive_transfer', { p_idempotency_key: key(), p_transfer_id: winner }, s1.token);
  ok(bal('transit') === transitBefore, '"En camino" back to its starting level once everything was received', `transit=${bal('transit')}`);
  ok(one(LEDGER_MISMATCHES) === '0', 'balances = ledger after the races (every variant, every location)', '');
  ok(ciHash() === ci0, 'no write to public.channel_inventory', '');
} catch (e) {
  ok(false, 'harness error', e.message);
} finally {
  if (created) {
    const left = cleanupTransferFixtures();
    ok(left === '0', 'synthetic fixtures removed', `left=${left}`);
    ok(one(LEDGER_MISMATCHES) === '0', 'balances = ledger after cleanup', '');
  }
}
for (const r of out) console.log(`${r.ok ? 'PASS' : 'FAIL'} | ${r.name} | ${r.detail}`);
const failed = out.filter((r) => !r.ok).length;
console.log(failed ? `\n${failed} FAILED` : '\nALL PASS');
process.exit(failed ? 1 : 0);
