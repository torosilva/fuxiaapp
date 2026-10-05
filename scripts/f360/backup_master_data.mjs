#!/usr/bin/env node
// F0 · Respaldo diario de lo que Carolina captura en Fuxia 360 (plan docs/fuxia360/ops/PASE_A_PRODUCCION_OPCION_B.md).
// READ-ONLY against the current F360 database (faltx…); refuses production. No personal data: customer cases, consent,
// access logs, e-mails, PINs, webhook payloads and order data are NOT exported.
// Self-contained on purpose (no repo imports): launchd copies it to ~/fuxia360-respaldos/bin/ and runs it daily.
// Output: ~/fuxia360-respaldos/<YYYY-MM-DD>/<schema>.<table>.json + manifest.json; photos (incremental, shared) in
// ~/fuxia360-respaldos/fotos/<storage path>. Keeps the last 30 daily folders.
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';

const PROD_REF = 'tgzgiwfzddsghnxgkcqd';
const F360_REF = 'faltxpkaicwpnlqaxrdu';
const PSQL = ['/opt/homebrew/opt/libpq/bin/psql', '/opt/homebrew/bin/psql', '/usr/local/bin/psql'].find(existsSync);
const ROOT = join(homedir(), 'fuxia360-respaldos');
const KEEP_DAYS = 30;

// Master + operational data only (same ids are what option B copies). Personal data stays out.
const TABLES = [
  'f360.categories', 'f360.currencies', 'f360.catalog_changes',
  'f360.products', 'f360.product_colors', 'f360.product_sizes', 'f360.product_variants', 'f360.product_media',
  'f360.product_prices', 'f360.price_changes', 'f360.price_suggestions', 'f360.product_status_changes',
  'f360.product_knowledge', 'f360.product_knowledge_history',
  'f360.locations', 'f360.location_assignments', 'f360.user_roles', 'f360.customer_pii_viewers', 'f360.sales_targets',
  'f360.legacy_woo_map', 'f360.legacy_woo_map_log', 'f360.legacy_consolidations', 'f360.legacy_content_pushes', 'f360.legacy_inventory_map',
  'f360.retired_woo_links', 'f360.woo_product_links', 'f360.woo_variant_links', 'f360.woo_media_links', 'f360.woo_category_links',
  'f360.woo_visibility_requests',
  'f360.inventory_events', 'f360.inventory_movements', 'f360.inventory_balances',
  'f360.transfers', 'f360.transfer_lines', 'f360.transfer_changes',
  'f360.opening_counts', 'f360.opening_count_lines', 'f360.opening_count_changes', 'f360.opening_count_unlisted',
  'f360.historical_sales', 'f360.historical_sales_log',
  'f360.growth_plans', 'f360.growth_plan_changes', 'f360.growth_scenarios', 'f360.reported_figures',
  'public.product_image_overrides',
];

function loadEnvFile() {
  const f = join(homedir(), '.fuxia-staging.env');
  if (!existsSync(f)) throw new Error(`falta ${f}`);
  for (const line of readFileSync(f, 'utf8').split('\n')) {
    const m = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '');
  }
  const db = process.env.STAGING_DB_URL || '', api = (process.env.STAGING_API_URL || '').replace(/\/+$/, '');
  if (!db.includes(F360_REF) || db.includes(PROD_REF) || !api.includes(F360_REF)) throw new Error('ABORT: el destino no es la base actual de Fuxia 360');
  return { db, api };
}

function sql(db, text) {
  if (!PSQL) throw new Error('no encuentro psql (brew install libpq)');
  const r = spawnSync('sh', ['-c', `"${PSQL}" "$F360_DB_URL" -X -q -At -v ON_ERROR_STOP=1 -f -`],
    { input: `BEGIN READ ONLY;\n${text}\nROLLBACK;\n`, encoding: 'utf8', env: { ...process.env, F360_DB_URL: db }, maxBuffer: 512 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`psql: ${(r.stderr || '').replace(/postgres(ql)?:\/\/\S+/g, '<URL>').slice(0, 500)}`);
  return r.stdout.trim();
}

async function main() {
  const { db, api } = loadEnvFile();
  const day = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
  const dir = join(ROOT, day);
  mkdirSync(dir, { recursive: true });
  const manifest = { day, started_at: new Date().toISOString(), source: F360_REF, tables: {}, photos: {} };

  for (const t of TABLES) {
    const [s, n] = t.split('.');
    const exists = sql(db, `SELECT to_regclass('${s}.${n}') IS NOT NULL;`) === 't';
    if (!exists) { manifest.tables[t] = 'no existe'; continue; }
    const json = sql(db, `SELECT coalesce(json_agg(x), '[]') FROM ${s}.${n} x;`);
    writeFileSync(join(dir, `${t}.json`), json);
    manifest.tables[t] = JSON.parse(json).length;
  }

  // Photos: every storage path referenced by the catalog (bucket product-images, public), downloaded once.
  const paths = JSON.parse(sql(db, `SELECT coalesce(json_agg(DISTINCT p), '[]') FROM (
      SELECT storage_path p FROM f360.product_media WHERE storage_path IS NOT NULL
      UNION SELECT image_path FROM f360.product_colors WHERE image_path IS NOT NULL
      UNION SELECT image_path FROM f360.products WHERE image_path IS NOT NULL) z WHERE p !~ '^https?://';`));
  let got = 0, had = 0; const missing = [];
  for (const p of paths) {
    const dest = join(ROOT, 'fotos', p);
    if (existsSync(dest)) { had++; continue; }
    const res = await fetch(`${api}/storage/v1/object/public/product-images/${p.split('/').map(encodeURIComponent).join('/')}`);
    if (!res.ok) { missing.push(p); continue; }
    mkdirSync(dirname(dest), { recursive: true });
    writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
    got++;
  }
  manifest.photos = { referenced: paths.length, already_saved: had, downloaded: got, missing: missing.length, missing_paths: missing.slice(0, 50) };
  manifest.finished_at = new Date().toISOString();
  writeFileSync(join(dir, 'manifest.json'), JSON.stringify(manifest, null, 2));

  // Retention: keep the last KEEP_DAYS daily folders (photos are shared and never deleted here).
  const days = readdirSync(ROOT).filter((d) => /^\d{4}-\d{2}-\d{2}$/.test(d)).sort();
  for (const d of days.slice(0, Math.max(0, days.length - KEEP_DAYS))) rmSync(join(ROOT, d), { recursive: true, force: true });

  const tables = Object.values(manifest.tables).filter((v) => typeof v === 'number').length;
  console.log(`Respaldo ${day}: ${tables} tablas · fotos ${had + got}/${paths.length} (${missing.length} faltan) → ${dir}`);
}

main().catch((e) => { console.error(`Respaldo FALLÓ: ${e.message}`); process.exit(1); });
