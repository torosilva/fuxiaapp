// STAGING ONLY — publishes ONE product ("Macarena" by default) to the real WooCommerce staging (staging4) as a DRAFT,
// through the exact P2.2 publisher (f360_request_publish → f360-woo-publish handler), as Carolina (owner, DW8).
// Guards: the store must be staging4 over HTTPS and not a production host; the target must be "woo_staging4",
// not production; the handler itself refuses a job whose target does not match this store. Never prints credentials.
// Run: scripts/s00a/run.sh ../f360/publish_staging4.ts [ProductName]
import { readFileSync } from 'node:fs';
import { client, loadEnv, psql } from '../s00a/lib.mjs';
import { handle } from '../../fuxia-native/supabase/functions/f360-woo-publish/handler.ts';

const staging = loadEnv();
const E = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
const url = new URL(E.WOO_BASE_URL);
const prod = (E.PRODUCTION_WOO_HOSTS ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean);
if (url.protocol !== 'https:' || !prod.length || prod.includes(url.hostname) || url.hostname !== 'staging4.fuxiaballerinas.com') throw new Error('ABORT: not the approved staging store');
const target = psql(`select key || '|' || base_url || '|' || is_production || '|' || active from f360.sales_targets where key = 'woo_staging4';`, {}, { readOnly: true }).trim().split('\n').pop();
if (target !== `woo_staging4|${url.origin}|false|true`) throw new Error(`ABORT: target woo_staging4 not registered as expected (${target})`);

const name = process.argv[2] ?? 'Macarena';
const productId = psql(`select id from f360.products where name = '${name.replace(/'/g, '')}' and status = 'active';`, {}, { readOnly: true }).trim().split('\n').pop();
if (!productId) throw new Error(`product ${name} not found`);
const c = client(staging);
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const req = await c.rest('POST', 'rpc/f360_request_publish', { token: owner.token, body: { p_product_id: productId, p_idempotency_key: crypto.randomUUID(), p_target_key: 'woo_staging4' } });
if (!req.ok) throw new Error(`request_publish: ${req.json?.message}`);
console.log(`job ${req.json.id} (${req.json.status}) · ${name} → ${url.hostname}`);
const env = { SUPABASE_URL: staging.api, SUPABASE_ANON_KEY: staging.anon, SUPABASE_SERVICE_ROLE_KEY: staging.service,
  WOO_TARGET_KEY: 'woo_staging4', WOO_BASE_URL: url.origin, WOO_USER: E.WOO_USER, WOO_SECRET: E.WOO_SECRET, STORAGE_PUBLIC_BASE: staging.api };
const t0 = Date.now();
const res = await handle(new Request('http://local/f360-woo-publish', { method: 'POST', headers: { Authorization: `Bearer ${owner.token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ job_id: req.json.id }) }), env);
const out = await res.json();
console.log(`HTTP ${res.status} · ${((Date.now() - t0) / 1000).toFixed(1)} s`);
console.log(JSON.stringify(out.outcome ?? out, null, 2).replace(/(ck|cs)_[A-Za-z0-9]{20,}/g, '$1_[redacted]'));
const steps = psql(`select string_agg(s.step || ' · ' || coalesce(s.object_ref, '') || ' · ' || s.action || ' · ' || coalesce(s.woo_id::text, '') || ' · ' || case when s.ok then 'ok' else 'FAIL' end || coalesce(' · ' || s.message, ''), E'\\n' order by s.id)
  from f360.sync_job_steps s where s.job_id = '${req.json.id}';`, {}, { readOnly: true }).trim();
console.log(steps);
