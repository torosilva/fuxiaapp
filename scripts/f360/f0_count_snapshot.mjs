#!/usr/bin/env node
// F0 · Snapshot + huella del conteo de apertura (docs/fuxia360/ops/PRODUCTION_INVENTORY_CUTOVER.md §2).
// READ-ONLY against the current F360 database (faltx…); the s00a lib refuses production. Writes nothing to the DB.
// Run:  scripts/s00a/run.sh ../f360/f0_count_snapshot.mjs [count_id]      (default: the open count, else the latest)
// Output: ~/fuxia360-respaldos/conteos/<count_id>/<UTC stamp>.json  +  the same name with .sha256
// Two fingerprints:
//   qty_sha256  = what would become the opening balance: (variant_id, canonical sku, final_qty, status) per in-scope line
//   full_sha256 = everything in the snapshot (adds timestamps, who counted, unlisted pairs and the change log)
// No customer data exists in these tables; "who counted" is staff display names only.
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const arg = process.argv[2];
if (arg && !/^[0-9a-f-]{36}$/.test(arg)) throw new Error('count_id no válido');
const pick = arg ? `c.id = '${arg}'` : `true ORDER BY (c.status IN ('preliminar','congelado')) DESC, c.started_at DESC LIMIT 1`;

const snap = JSON.parse(psql(`
WITH c AS (SELECT c.* FROM f360.opening_counts c WHERE ${pick})
SELECT json_build_object(
  'count', (SELECT json_build_object('id', c.id, 'status', c.status, 'mode', c.mode, 'location_id', c.location_id,
      'location', l.name, 'target_key', t.key, 'target_is_production', t.is_production,
      'started_by', c.started_by_name, 'started_at', c.started_at, 'frozen_at', c.frozen_at, 'reconciled_at', c.reconciled_at,
      'approved_by', c.approved_by_name, 'approved_at', c.approved_at, 'loaded_at', c.loaded_at, 'load_event_id', c.load_event_id,
      'cancelled_at', c.cancelled_at)
    FROM c JOIN f360.locations l ON l.id = c.location_id JOIN f360.sales_targets t ON t.id = c.target_id),
  'lines', (SELECT coalesce(json_agg(json_build_object('variant_id', ln.variant_id, 'sku', v.sku, 'product', p.name, 'color', co.name, 'size', v.size_label,
      'in_scope', ln.in_scope, 'status', ln.status, 'final_qty', ln.final_qty, 'count1', ln.count1, 'recount', ln.recount,
      'counted_at', coalesce(ln.recount_at, ln.count1_at), 'final_at', ln.final_at, 'counted_by', coalesce(ln.recount_by_name, ln.count1_by_name),
      'affected', ln.affected, 'woo_stock_reference', ln.woo_stock) ORDER BY ln.variant_id), '[]')
    FROM c JOIN f360.opening_count_lines ln ON ln.count_id = c.id JOIN f360.product_variants v ON v.id = ln.variant_id
    JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors co ON co.id = v.color_id),
  'unlisted', (SELECT coalesce(json_agg(json_build_object('id', u.id, 'description', u.description, 'size', u.size_label, 'quantity', u.quantity,
      'status', u.status, 'found_by', u.found_by_name, 'found_at', u.found_at, 'resolution', u.resolution) ORDER BY u.found_at), '[]')
    FROM c JOIN f360.opening_count_unlisted u ON u.count_id = c.id),
  'changes', (SELECT coalesce(json_agg(json_build_object('id', x.id, 'action', x.action, 'actor', x.actor_name, 'at', x.at, 'detail', x.detail) ORDER BY x.id), '[]')
    FROM c JOIN f360.opening_count_changes x ON x.count_id = c.id),
  'taken_at', clock_timestamp());`, {}, { readOnly: true }));

if (!snap.count) throw new Error('No hay conteo');
const sha = (o) => createHash('sha256').update(JSON.stringify(o)).digest('hex');
const inScope = snap.lines.filter((l) => l.in_scope);
const qtyBasis = { count_id: snap.count.id, location_id: snap.count.location_id,
  lines: inScope.map((l) => [l.variant_id, l.sku, l.final_qty, l.status]) };
const summary = {
  count_id: snap.count.id, location: snap.count.location, target: snap.count.target_key, status: snap.count.status, mode: snap.count.mode,
  lines_in_scope: inScope.length,
  counted: inScope.filter((l) => l.final_qty !== null && l.status !== 'recontar').length,
  pending: inScope.filter((l) => l.status === 'pendiente').length,
  recount: inScope.filter((l) => l.status === 'recontar').length,
  pairs_counted: inScope.reduce((a, l) => a + (l.status !== 'recontar' && l.final_qty ? l.final_qty : 0), 0),
  first_counted_at: inScope.map((l) => l.counted_at).filter(Boolean).sort()[0] || null,
  last_counted_at: inScope.map((l) => l.counted_at).filter(Boolean).sort().at(-1) || null,
  counted_by: [...new Set(inScope.map((l) => l.counted_by).filter(Boolean))],
  unlisted_open: snap.unlisted.filter((u) => u.status === 'abierto').length,
  changes: snap.changes.length,
  load_event_id: snap.count.load_event_id,
  qty_sha256: sha(qtyBasis),
};
summary.full_sha256 = sha({ ...snap, taken_at: undefined }); // stable across runs if nothing changed

const stamp = snap.taken_at.replace(/[:.]/g, '-');
const dir = join(homedir(), 'fuxia360-respaldos', 'conteos', snap.count.id);
mkdirSync(dir, { recursive: true });
writeFileSync(join(dir, `${stamp}.json`), JSON.stringify({ summary, snapshot: snap }, null, 1));
writeFileSync(join(dir, `${stamp}.sha256`), `${summary.qty_sha256}  qty\n${summary.full_sha256}  full\n`);
console.log(JSON.stringify(summary, null, 2));
console.log(`→ ${join(dir, stamp)}.json`);
