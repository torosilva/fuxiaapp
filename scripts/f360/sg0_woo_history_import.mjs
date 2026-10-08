// S-G0 · D1 WOO ORDER HISTORY IMPORT — STAGING ONLY (staging DB + the staging4 test store). Never production: the staging lib
// refuses any production credential and this script refuses any Woo host other than staging4. Production uses a separate,
// reviewed run (docs/fuxia360/growth/S-G0_DELIVERY.md §Production plan), never this file.
// Reads Woo with GET only (ids first, full order only when Fuxia 360 lacks it or holds an older version) and captures through
// the ONE idempotent path (public.f360_capture_order_economics, p_via='backfill' → capture source woo_history_import).
// Never touches inventory or order_shipping. Prints counts only — no customer data.
// Run:  scripts/s00a/run.sh ../f360/sg0_woo_history_import.mjs --dry-run      (compare only, writes nothing)
//       scripts/s00a/run.sh ../f360/sg0_woo_history_import.mjs [--months=24]   (import; run twice: the 2nd must import 0)
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';
import { commerceHistoryImport, commerceWoo } from '../../fuxia-native/supabase/functions/_shared/f360-woo/commerce.ts';
import { serviceRpc } from '../../fuxia-native/supabase/functions/_shared/f360-woo/supabase.ts';

const env = loadEnv();
const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
const url = new URL(W.WOO_BASE_URL);
const prod = (W.PRODUCTION_WOO_HOSTS ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean);
if (url.protocol !== 'https:' || !prod.length || prod.includes(url.hostname) || url.hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not the approved staging store');
const dryRun = process.argv.includes('--dry-run');
const months = Number((process.argv.find((a) => a.startsWith('--months=')) ?? '--months=24').slice(9));

const rpc = serviceRpc({ SUPABASE_URL: env.api, SUPABASE_SERVICE_ROLE_KEY: env.service });
const counts = () => psql(`select count(*) from f360.commerce_woo_orders o join f360.sales_targets t on t.id = o.target_id where t.key = 'woo_staging4';
  select count(*) from f360.inventory_events; select count(*) from f360.woo_orders; select count(*) from f360.woo_order_lines;`, {}, { readOnly: true }).split('\n').map(Number);
const before = counts();
const run = await commerceHistoryImport(rpc, commerceWoo({ baseUrl: url.origin, user: W.WOO_USER, secret: W.WOO_SECRET }), 'woo_staging4', { months, dryRun });
const after = counts();
console.log(JSON.stringify({ dry_run: dryRun, months, created_after: run.created_after, run_id: run.run_id, ok: run.ok, stats: run.stats, error: run.error ?? null,
  facts_before: before[0], facts_after: after[0],
  inventory_untouched: before[1] === after[1] && before[2] === after[2] && before[3] === after[3] }));
process.exit(run.ok ? 0 : 1);
