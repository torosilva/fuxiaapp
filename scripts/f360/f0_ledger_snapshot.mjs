#!/usr/bin/env node
// F0 · Snapshot + huella del inventario capturado por ubicación (ledger), docs/fuxia360/ops/PRODUCTION_INVENTORY_CUTOVER.md §2.
// Carolina loads each store's stock with "Recibir mercancía" (RECEIPT) and corrects with "Ajustar" (ADJUSTMENT); the
// candidate opening balance is therefore the ledger per location, not only f360.opening_counts.
// READ-ONLY against the current F360 database (faltx…); the s00a lib refuses production. Writes nothing to the DB.
// Run:  scripts/s00a/run.sh ../f360/f0_ledger_snapshot.mjs
// Output: ~/fuxia360-respaldos/ledger/<UTC stamp>.json (+ .sha256)
//   per location: balance_sha256 = (variant_id, sku, on_hand) of non-zero balances; ledger_sha256 = every event+movement
//   touching the location (id, type, actor, created_at, variant, from, to, qty). Same ledger => same hashes.
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const data = JSON.parse(psql(`
SELECT json_build_object('taken_at', clock_timestamp(), 'locations', (SELECT json_agg(json_build_object(
  'id', l.id, 'name', l.name, 'type', l.type, 'ledger_authority', l.ledger_authority,
  'balances', (SELECT coalesce(json_agg(json_build_object('variant_id', b.variant_id, 'sku', v.sku, 'on_hand', b.on_hand) ORDER BY b.variant_id), '[]')
     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id WHERE b.location_id = l.id AND b.on_hand <> 0),
  'movements', (SELECT coalesce(json_agg(json_build_object('event_id', e.id, 'type', e.event_type, 'actor', e.actor_name, 'created_at', e.created_at,
        'occurred_at', e.occurred_at, 'ref', e.business_reference_type || ':' || e.business_reference_id, 'note', e.note,
        'variant_id', m.variant_id, 'sku', v.sku, 'from', m.from_location_id, 'to', m.to_location_id, 'qty', m.quantity) ORDER BY e.created_at, e.id, m.id), '[]')
     FROM f360.inventory_movements m JOIN f360.inventory_events e ON e.id = m.event_id JOIN f360.product_variants v ON v.id = m.variant_id
     WHERE l.id IN (m.from_location_id, m.to_location_id))) ORDER BY l.sort, l.name) FROM f360.locations l));`, {}, { readOnly: true }));

const sha = (o) => createHash('sha256').update(JSON.stringify(o)).digest('hex');
const summary = data.locations.map((l) => {
  const ev = l.movements;
  const byType = {};
  for (const m of ev) { const k = `${m.type}${m.to === l.id ? ' +' : ' −'}`; byType[k] = (byType[k] || 0) + m.qty; }
  return { location: l.name, ledger_authority: l.ledger_authority, variants_with_stock: l.balances.length,
    pairs: l.balances.reduce((a, b) => a + b.on_hand, 0), movements: ev.length, pairs_by_type: byType,
    first_movement_at: ev[0]?.created_at || null, last_movement_at: ev.at(-1)?.created_at || null,
    actors: [...new Set(ev.map((m) => m.actor))],
    balance_sha256: sha(l.balances.map((b) => [b.variant_id, b.sku, b.on_hand])),
    ledger_sha256: sha(ev.map((m) => [m.event_id, m.type, m.actor, m.created_at, m.variant_id, m.from, m.to, m.qty])) };
}).filter((s) => s.movements > 0 || s.pairs !== 0);

const stamp = data.taken_at.replace(/[:.]/g, '-');
const dir = join(homedir(), 'fuxia360-respaldos', 'ledger');
mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, `${stamp}.json`), JSON.stringify({ summary, data }, null, 1));
writeFileSync(join(dir, `${stamp}.sha256`), summary.map((s) => `${s.balance_sha256}  balance  ${s.location}\n${s.ledger_sha256}  ledger   ${s.location}`).join('\n') + '\n');
console.log(JSON.stringify(summary, null, 2));
console.log(`→ ${join(dir, stamp)}.json`);
