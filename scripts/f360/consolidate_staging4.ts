// STAGING ONLY — runs "un producto por modelo" consolidations on staging4 end to end, server-side (no browser tab to die):
//   start (owner RPC) → publish job (the exact f360-woo-publish handler, run locally) → finish (owner RPC).
// Same guards as publish_staging4.ts: the store must be staging4 over HTTPS, not a production host; the target must be
// woo_staging4, not production. Acts with Carolina's owner session (the requester of the existing jobs). Never prints credentials.
// Run: scripts/s00a/run.sh ../f360/consolidate_staging4.ts <command> [args]
//   hide-orphan <wooId> <expectedSku>   set an orphan Woo product (e.g. Macarena 3621 / F360-MACARENA) to private
//   finish <ModelName>                  finish a consolidation whose publish job already succeeded
//   run <ModelName> [...]               start (or retry) → publish → finish, one model after another
//   publish-new <ModelName> [...]       publish a model with no Woo product (draft) and make it visible
//   rename-color "<Model>" <from> <to>  rename a colour (visible name only, logged)
//   fix-slug <ModelName>                free the model's slug from old products and give it to the new one
//   status                              consolidations and their jobs
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

const ro = (s: string) => psql(s, {}, { readOnly: true }).trim().split('\n').filter(Boolean);
const lit = (s: string) => `'${s.replace(/'/g, "''")}'`;
const c = client(staging);
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const rpc = async (fn: string, body: Record<string, unknown>) => {
  const r = await c.rest('POST', `rpc/${fn}`, { token: owner.token, body });
  if (!r.ok) throw new Error(`${fn}: ${r.json?.message ?? r.status}`);
  return r.json;
};
const woo = async (method: string, path: string, body?: unknown) => {
  const r = await fetch(`${url.origin}/wp-json/wc/v3/${path}`, { method, redirect: 'error',
    headers: { Authorization: 'Basic ' + Buffer.from(`${E.WOO_USER}:${E.WOO_SECRET}`).toString('base64'), 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`Woo ${method} ${path}: HTTP ${r.status} ${j?.code ?? ''}`);
  return j;
};
const productId = (name: string) => {
  const id = ro(`select id from f360.products where name = ${lit(name)} and status = 'active';`).pop();
  if (!id) throw new Error(`modelo "${name}" no encontrado`);
  return id;
};
const env = { SUPABASE_URL: staging.api, SUPABASE_ANON_KEY: staging.anon, SUPABASE_SERVICE_ROLE_KEY: staging.service,
  WOO_TARGET_KEY: 'woo_staging4', WOO_BASE_URL: url.origin, WOO_USER: E.WOO_USER, WOO_SECRET: E.WOO_SECRET, STORAGE_PUBLIC_BASE: staging.api };
const runJob = async (jobId: string) => {
  const t0 = Date.now();
  const res = await handle(new Request('http://local/f360-woo-publish', { method: 'POST',
    headers: { Authorization: `Bearer ${owner.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ job_id: jobId }) }), env);
  const out = await res.json();
  const status = ro(`select status from f360.sync_jobs where id = ${lit(jobId)};`).pop();
  console.log(`  job ${jobId.slice(0, 8)} → HTTP ${res.status} · ${status} · ${((Date.now() - t0) / 1000).toFixed(0)} s${out?.error ? ' · ' + String(out.error).slice(0, 160) : ''}`);
  return status;
};
const consolidation = (pid: string) => ro(`select c.status || '|' || coalesce(c.job_id::text, '') || '|' || coalesce(j.status, '')
  from f360.legacy_consolidations c left join f360.sync_jobs j on j.id = c.job_id
  where c.product_id = ${lit(pid)} and c.target_id = (select id from f360.sales_targets where key = 'woo_staging4');`).pop();

// Slugs: WordPress makes a slug unique only when a post becomes visible, and private old products keep theirs, so the new
// one-per-model product would go live as "…-2". Before finish, the old per-colour products that hold the model's slug get
// "<slug>-anterior" (they are about to be hidden; redirects point old URLs to the new one); after finish the new product
// gets the model's slug.
const modelSlug = (pid: string) => ro(`select slug from f360.products where id = ${lit(pid)};`).pop() ?? '';
const legacyIds = (pid: string) => ro(`select distinct m.woo_product_id from f360.legacy_woo_map m join f360.product_variants v on v.id = m.confirmed_variant_id
  where v.product_id = ${lit(pid)} and m.status = 'confirmado' and m.target_id = (select id from f360.sales_targets where key = 'woo_staging4');`).map(Number);
const freeSlug = async (pid: string) => {
  const slug = modelSlug(pid);
  for (const id of legacyIds(pid)) {
    const p = await woo('GET', `products/${id}`);
    if (p.slug === slug) { await woo('PUT', `products/${id}`, { slug: `${slug}-anterior` }); console.log(`  slug de ${id} → ${slug}-anterior`); }
  }
};
const ensureSlug = async (pid: string) => {
  const slug = modelSlug(pid);
  const id = Number(ro(`select woo_product_id from f360.woo_product_links where product_id = ${lit(pid)} and target_id = (select id from f360.sales_targets where key = 'woo_staging4');`).pop());
  if (!id || !slug) return;
  const p = await woo('GET', `products/${id}`);
  if (p.slug !== slug) { const r = await woo('PUT', `products/${id}`, { slug }); console.log(`  slug de ${id}: ${p.slug} → ${r.slug}`); }
};

const [cmd, ...args] = process.argv.slice(2);
if (cmd === 'hide-orphan') {
  const [id, sku] = args;
  const p = await woo('GET', `products/${Number(id)}`);
  if (p.sku !== sku) throw new Error(`ABORT: product ${id} has SKU ${p.sku}, expected ${sku}`);
  if (ro(`select 1 from f360.woo_product_links where woo_product_id = ${Number(id)} union all select 1 from f360.legacy_woo_map where woo_product_id = ${Number(id)};`).length)
    throw new Error('ABORT: product is linked in F360; use F360 visibility instead');
  const r = await woo('PUT', `products/${Number(id)}`, { status: 'private' });
  console.log(`Woo ${id} ${p.name}: ${p.status} → ${r.status}`);
} else if (cmd === 'finish') {
  const pid = productId(args.join(' '));
  await rpc('f360_consolidate_finish', { p_target_key: 'woo_staging4', p_product_id: pid });
  console.log(`${args.join(' ')}: ${consolidation(pid)}`);
} else if (cmd === 'run') {
  for (const name of args) {
    const pid = productId(name);
    console.log(`== ${name}`);
    let row = consolidation(pid);
    let [st, job, jst] = (row ?? '||').split('|');
    if (st === 'publicada') { console.log('  ya publicada'); continue; }
    if (!row || jst === 'failed' || jst === 'partial') {
      const r = await rpc('f360_consolidate_start', { p_target_key: 'woo_staging4', p_product_ids: [pid] });
      if (r?.skipped?.length) { console.log('  omitido:', JSON.stringify(r.skipped)); continue; }
      [st, job, jst] = (consolidation(pid) ?? '||').split('|');
    }
    if (jst !== 'succeeded') jst = await runJob(job);
    if (jst !== 'succeeded') { console.log('  publicación no terminó; reintentar en ≥5 min (SiteGround sigue subiendo fotos)'); continue; }
    await freeSlug(pid);
    await rpc('f360_consolidate_finish', { p_target_key: 'woo_staging4', p_product_id: pid });
    await ensureSlug(pid);
    console.log(`  → ${consolidation(pid)}`);
  }
} else if (cmd === 'publish-new') {   // models with no Woo product at all: publish (draft) → make visible
  for (const name of args) {
    const pid = productId(name);
    console.log(`== ${name}`);
    if (legacyIds(pid).length) { console.log('  tiene productos viejos: usar run (unión)'); continue; }
    const req = await rpc('f360_request_publish', { p_product_id: pid, p_idempotency_key: crypto.randomUUID(), p_target_key: 'woo_staging4' });
    const st = await runJob(req.id);
    if (st !== 'succeeded') { console.log('  publicación no terminó; reintentar'); continue; }
    const id = Number(ro(`select woo_product_id from f360.woo_product_links where product_id = ${lit(pid)} and target_id = (select id from f360.sales_targets where key = 'woo_staging4');`).pop());
    const r = await woo('PUT', `products/${id}`, { status: 'publish' });   // F360 has no "show" for non-legacy products yet
    console.log(`  Woo ${id}: ${r.status} · /producto/${r.slug}/`);
  }
} else if (cmd === 'rename-color') {   // rename-color "<Model>" <from> <to>  (name only; code and SKUs unchanged; logged)
  const [model, from, to] = args;
  const cid = ro(`select c.id from f360.product_colors c where c.product_id = ${lit(productId(model))} and c.name = ${lit(from)};`).pop();
  if (!cid) throw new Error(`color "${from}" no encontrado en ${model}`);
  await rpc('f360_rename_color', { p_color_id: cid, p_name: to });
  console.log(`${model}: color ${from} → ${to}`);
} else if (cmd === 'fix-slug') {
  const pid = productId(args.join(' '));
  await freeSlug(pid); await ensureSlug(pid);
} else if (cmd === 'status') {
  console.log(ro(`select p.name || ' | ' || c.status || ' | ' || coalesce(j.status, '-') || ' | woo ' || coalesce((select string_agg(l.woo_product_id::text, ',') from f360.woo_product_links l where l.product_id = p.id and l.target_id = c.target_id), '-')
    from f360.legacy_consolidations c join f360.products p on p.id = c.product_id left join f360.sync_jobs j on j.id = c.job_id order by c.status, p.name;`).join('\n'));
} else {
  throw new Error('comando: hide-orphan | finish | run | status');
}
