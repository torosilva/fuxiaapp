// STAGING ONLY — G1 Commerce Facts backfill: reads every staging4 order (GET only) and captures its economics through
// the same idempotent path the webhook and the 15-minute poll use (public.f360_capture_order_economics, p_via=backfill).
// Never touches inventory (woo_orders / woo_order_lines / inventory_events). Run it twice: the second run must report
// the same facts (all "unchanged"). Prints counts only — no customer data.
// Run: scripts/s00a/run.sh ../f360/g1_commerce_backfill.mjs
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';
import { commercePoll, commerceWoo } from '../../fuxia-native/supabase/functions/_shared/f360-woo/commerce.ts';
import { serviceRpc } from '../../fuxia-native/supabase/functions/_shared/f360-woo/supabase.ts';

const env = loadEnv();
const W = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
const url = new URL(W.WOO_BASE_URL);
const prod = (W.PRODUCTION_WOO_HOSTS ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean);
if (url.protocol !== 'https:' || !prod.length || prod.includes(url.hostname) || url.hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not the approved staging store');

const rpc = serviceRpc({ SUPABASE_URL: env.api, SUPABASE_SERVICE_ROLE_KEY: env.service });
const counts = () => psql(`select count(*) from f360.commerce_woo_orders o join f360.sales_targets t on t.id = o.target_id where t.key = 'woo_staging4';
  select count(*) from f360.inventory_events; select count(*) from f360.woo_orders; select count(*) from f360.woo_order_lines;`, {}, { readOnly: true }).split('\n').map(Number);
const before = counts();
const run = await commercePoll(rpc, commerceWoo({ baseUrl: url.origin, user: W.WOO_USER, secret: W.WOO_SECRET }), 'woo_staging4', 'backfill');
const after = counts();
console.log(JSON.stringify({ run_id: run.run_id, ok: run.ok, stats: run.stats, error: run.error ?? null,
  facts_before: before[0], facts_after: after[0],
  inventory_untouched: before[1] === after[1] && before[2] === after[2] && before[3] === after[3] }));
process.exit(run.ok ? 0 : 1);
