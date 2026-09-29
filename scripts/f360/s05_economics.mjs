// STAGING ONLY — S0.5 economics BEFORE/AFTER. The same scenarios on fresh synthetic cards:
//   before: the deployed claim-sale (scan_qr → creditPoints), i.e. today's in-store loyalty path
//   after : public.loyalty_apply (S0.5)
// Compares every loyalty outcome. Synthetic customers/cards (phones +1555010 7xx) are removed at the end of each phase.
// Run: scripts/s00a/run.sh ../f360/s05_economics.mjs before|after
import { readFileSync, writeFileSync } from 'node:fs';
import { client, loadEnv, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const c = client(env);
const phase = process.argv[2];
const OUT = 'docs/fuxia360/audit/s00a_results/s05_economics.json';
const CH_X = '00000000-0000-4000-a000-000000000301';
const line = (q, price = 2800, extra = {}) => ({ inventory_id: CH_X, product_name: 'STAGING Ballerina Test', size: '37', color: 'Negro', ...(q == null ? {} : { quantity: q }), unit_price: price, ...extra });
const SCEN = [
  { id: 'E1', desc: '0 pts, 1 pair', pts: 0, pairs: 0, lines: [line(1)] },
  { id: 'E2', desc: '250 pts, 1 pair → crosses 300 (silver)', pts: 250, pairs: 2, lines: [line(1)] },
  { id: 'E3', desc: '850 pts, 1 line qty 2 → crosses 900 (gold)', pts: 850, pairs: 8, lines: [line(2)] },
  { id: 'E4', desc: '0 pts, 3 lines (1+2+1)', pts: 0, pairs: 0, lines: [line(1), line(2, 1900), line(1, 2400)] },
  { id: 'E5', desc: 'gold 1000 pts, 1 pair (stays gold)', pts: 1000, pairs: 10, lines: [line(1)] },
  { id: 'E6', desc: '299 pts, line WITHOUT quantity (counts as 1)', pts: 299, pairs: 2, lines: [line(null)] },
];
const total = (ls) => ls.reduce((a, l) => a + (l.quantity ?? 1) * l.unit_price, 0);

function makeCard(tag, i, s) {
  const phone = `+1555010${phase === 'before' ? 7 : 8}${String(i).padStart(2, '0')}`;
  const out = psql(`
    with cu as (insert into public.customers (phone, name, country, role) values ('${phone}', 'ZZ S05 ${tag} ${s.id}', 'MX', 'customer') returning id),
    ca as (insert into public.loyalty_cards (customer_id, qr_code, total_points, pairs_count) select id, 'ZZS05-${tag}-${s.id}-${Date.now()}', ${s.pts}, ${s.pairs} from cu returning id, customer_id, qr_code)
    select json_build_object('card', id, 'customer', customer_id, 'qr', qr_code) from ca;`).trim().split('\n').pop();
  return JSON.parse(out);
}
const cardState = (card) => JSON.parse(psql(`select json_build_object('total_points', total_points, 'pairs_count', pairs_count, 'tier', tier,
  'total_pairs_count', total_pairs_count, 'purchases_this_year', purchases_this_year, 'last_purchase_set', last_purchase_at is not null) from public.loyalty_cards where id = '${card}';`, {}, { readOnly: true }).trim());
const txState = (card) => JSON.parse(psql(`select coalesce(json_agg(json_build_object('points_earned', t.points_earned, 'pairs_in_order', t.pairs_in_order, 'amount', t.amount::numeric,
  'channel', t.channel, 'status', t.status, 'currency', t.currency, 'items_saved', (select count(*) from public.purchase_items pi where pi.transaction_id = t.id))), '[]')
  from public.transactions t where t.loyalty_card_id = '${card}';`, {}, { readOnly: true }).trim());
function cleanup(ids) {
  if (!ids.length) return;
  const cards = ids.map((x) => `'${x.card}'`).join(','), custs = ids.map((x) => `'${x.customer}'`).join(',');
  psql(`BEGIN;
    delete from public.purchase_items where transaction_id in (select id from public.transactions where loyalty_card_id in (${cards}));
    -- loyalty_apply_audit rows stay: the audit is append-only by design
    delete from public.transactions where loyalty_card_id in (${cards});
    delete from public.offline_sales where customer_id in (${custs});
    delete from public.loyalty_cards where id in (${cards});
    delete from public.customers where id in (${custs});
    COMMIT;`);
}

const created = [];
const results = {};
try {
  for (const [i, s] of SCEN.entries()) {
    const k = makeCard(phase, i + 1, s);
    created.push(k);
    const start = cardState(k.card);
    if (phase === 'before') {
      const r = await c.fn('claim-sale', { body: { action: 'scan_qr', qr_code: k.qr, items: s.lines, total: total(s.lines), channel_id: CH_X, staff_id: null } });
      if (!r.ok) throw new Error(`claim-sale ${s.id}: ${r.status} ${r.text}`);
    } else {
      const r = await c.svcRest('POST', 'rpc/loyalty_apply', { body: { p_card_id: k.card, p_lines: s.lines, p_amount: total(s.lines), p_channel: 'store',
        p_ref_type: 'econ_test', p_ref_id: s.id, p_idempotency_key: `econ:${k.card}`, p_actor: { type: 'test' } } });
      if (!r.ok) throw new Error(`loyalty_apply ${s.id}: ${r.status} ${r.text}`);
    }
    results[s.id] = { desc: s.desc, start, end: cardState(k.card), tx: txState(k.card) };
    console.log(`${phase.toUpperCase()} ${s.id} ${s.desc}: ${JSON.stringify(results[s.id].end)} tx=${JSON.stringify(results[s.id].tx)}`);
  }
} finally { cleanup(created); console.log(`cleanup: ${created.length} synthetic cards/customers removed`); }

if (phase === 'before') {
  writeFileSync(OUT, JSON.stringify({ before_at: new Date().toISOString(), before_source: 'deployed claim-sale (scan_qr/creditPoints) on staging', before: results }, null, 2));
} else {
  const saved = JSON.parse(readFileSync(OUT, 'utf8'));
  const cmp = {};
  let same = true;
  for (const id of Object.keys(results)) {
    const b = saved.before[id], a = results[id];
    const econ = (x) => ({ card: x.end, points: x.tx[0]?.points_earned, pairs: x.tx[0]?.pairs_in_order, amount: Number(x.tx[0]?.amount), channel: x.tx[0]?.channel, status: x.tx[0]?.status, currency: x.tx[0]?.currency, txs: x.tx.length });
    const eq = JSON.stringify(econ(b)) === JSON.stringify(econ(a));
    same = same && eq;
    cmp[id] = { economics_identical: eq, items_saved_before: b.tx[0]?.items_saved, items_saved_after: a.tx[0]?.items_saved, lines: SCEN.find((s) => s.id === id).lines.length };
    console.log(`${id}: economics ${eq ? 'IDENTICAL' : 'DIFFERENT'} · purchase_items saved before=${cmp[id].items_saved_before} after=${cmp[id].items_saved_after}`);
  }
  writeFileSync(OUT, JSON.stringify({ ...saved, after_at: new Date().toISOString(), after_source: 'public.loyalty_apply (S0.5)', after: results, comparison: cmp, all_economics_identical: same }, null, 2));
  console.log(same ? '\nECONOMICS IDENTICAL in every scenario' : '\nECONOMICS DIFFER — see file');
  process.exit(same ? 0 : 1);
}
