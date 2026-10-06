#!/usr/bin/env node
// Pase a producción · opción B · G8 + G9 (docs/fuxia360/ops/PASE_F1_MIGRATIONS_AUDIT.md §5-§6).
// Loads what Carolina captured (the F0 daily backup of faltx…) into a database that already has every F360 migration,
// WITH THE SAME IDS, in one transaction:
//   · catalog (models, colours, sizes, variants, photos rows, prices, knowledge), locations, categories, currencies;
//   · Carolina's change history; growth plans; historical sales (real);
//   · Q4 option: Woo homologation kept as history of the staging4 channel (inactive, is_test);
//   · Q7 option (--with-inventory): her inventory (events, movements, balances, transfers, opening counts).
// Never copied (§6): user roles / sellers / PII viewers (recreated by e-mail), Woo links of staging4, orders, customers, PII.
// Users: every staging auth id is remapped BY E-MAIL to the target's auth.users (team only); anything else → NULL.
// Then G8: user_roles + customer_pii_viewers by e-mail, and the real channel woo_production (INACTIVE until F5).
// THIS VERSION ONLY WRITES TO A LOCAL REHEARSAL DATABASE (127.0.0.1). Production needs Mario's approval of F4.
// Usage: PASE_TARGET_DB_URL=postgresql://…@127.0.0.1:54322/postgres node scripts/f360/pase_copy_master.mjs \
//          --backup ~/fuxia360-respaldos/2026-10-05 --auth staging_auth.json [--with-inventory] [--dry-run]
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const PROD_REF = 'tgzgiwfzddsghnxgkcqd', F360_REF = 'faltxpkaicwpnlqaxrdu';
const PSQL = ['/opt/homebrew/opt/libpq/bin/psql', '/opt/homebrew/bin/psql', '/usr/local/bin/psql'].find(existsSync);
const arg = (k) => { const i = process.argv.indexOf(k); return i > 0 ? process.argv[i + 1] : undefined; };
const BACKUP = arg('--backup'), AUTH = arg('--auth'), WITH_INV = process.argv.includes('--with-inventory'), DRY = process.argv.includes('--dry-run');
// --emit-sql <file> --team-map <json>: write the SQL (BEGIN … COMMIT) instead of executing it. Used for PRODUCTION, where the
// file is committed and applied ONLY through scripts/f360/prod_sql.sh (dry-run first). No database is touched in this mode.
const EMIT = arg('--emit-sql'), TEAM_MAP = arg('--team-map');
const ONLY_INV = process.argv.includes('--only-inventory');   // catalog already loaded: emit ONLY Carolina's inventory
const TARGET = process.env.PASE_TARGET_DB_URL || '';
if (!BACKUP || !AUTH || (!TARGET && !EMIT)) throw new Error('uso: PASE_TARGET_DB_URL=… --backup <dir> --auth <json>  |  --emit-sql <file> --team-map <json>');
if (EMIT && !TEAM_MAP) throw new Error('--emit-sql requiere --team-map (cuentas del equipo en el destino, por persona)');
if (!EMIT) {
  if (TARGET.includes(F360_REF)) throw new Error('ABORT: el destino es el ambiente actual (faltx…)');
  if (TARGET.includes(PROD_REF) || !/@(127\.0\.0\.1|localhost):/.test(TARGET)) throw new Error('ABORT: ejecución directa solo en el ensayo local; producción va por --emit-sql + prod_sql.sh');
}

// FK order. [table, filter?] — the filter drops rows that must never travel.
const CATALOG = ['f360.categories', 'f360.currencies', 'f360.price_suggestions', 'f360.locations', 'f360.products', 'f360.product_colors',
  'f360.product_sizes', 'f360.product_variants', 'f360.product_media', 'f360.product_prices', 'f360.price_changes', 'f360.product_status_changes',
  'f360.catalog_changes', 'f360.product_knowledge', 'f360.product_knowledge_history', 'f360.historical_sales', 'f360.historical_sales_log',
  'f360.growth_plans', 'f360.growth_plan_changes', 'f360.growth_scenarios', 'f360.reported_figures'];
const HOMOLOGATION = ['f360.legacy_woo_map', 'f360.legacy_woo_map_log'];
const INVENTORY = ['f360.inventory_events', 'f360.inventory_movements', 'f360.inventory_balances', 'f360.transfers', 'f360.transfer_lines',
  'f360.transfer_changes', 'f360.opening_counts', 'f360.opening_count_lines', 'f360.opening_count_changes', 'f360.opening_count_unlisted'];
const SEEDED = new Set(['f360.categories', 'f360.currencies', 'f360.price_suggestions']);   // migrations already insert these: upsert-skip

function psql(sql, { readOnly = false } = {}) {
  const r = spawnSync(PSQL, [TARGET, '-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-f', '-'], { input: readOnly ? `BEGIN READ ONLY;\n${sql}\nROLLBACK;\n` : sql,
    encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
  if (r.status !== 0) throw new Error(`psql: ${(r.stderr || '').replace(/postgres(ql)?:\/\/\S+/g, '<URL>').slice(0, 1500)}`);
  return r.stdout.trim();
}
const load = (t) => { const f = join(BACKUP, `${t}.json`); return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : []; };

const auth = JSON.parse(readFileSync(AUTH, 'utf8'));
const stagingIds = new Set(auth.all_ids);
const remap = new Map();
if (EMIT) {
  // team map decided by Mario: staging account → the person's production app account (by phone); missing → NULL
  for (const [from, to] of Object.entries(JSON.parse(readFileSync(TEAM_MAP, 'utf8')).map || {})) if (to) remap.set(from, to);
} else {
  const targetUsers = JSON.parse(psql(`SELECT coalesce(json_object_agg(lower(email), id), '{}') FROM auth.users WHERE email IS NOT NULL;`, { readOnly: true }) || '{}');
  for (const m of auth.team) { const t = targetUsers[(m.email || '').toLowerCase()]; if (t) remap.set(m.id, t); }
}
const missingTeam = auth.team.filter((m) => !remap.has(m.id)).map((m) => m.name);

const stagingTargets = load('f360.sales_targets');
const s4 = stagingTargets.find((t) => t.key === 'woo_staging4');
const stats = {};
let sql = EMIT ? `-- Fuxia 360 · pase B4/G8 — generated by scripts/f360/pase_copy_master.mjs from ${BACKUP.split('/').pop()} (no personal data).\n-- Apply ONLY with scripts/f360/prod_sql.sh (dry-run first).\nBEGIN;\n` : `\\set ON_ERROR_STOP on\nBEGIN;\n`;
const add = (t, rows) => {
  const fixed = rows.map((r) => Object.fromEntries(Object.entries(r).map(([k, v]) =>
    [k, typeof v === 'string' && stagingIds.has(v) ? (remap.get(v) ?? null) : v])));
  stats[t] = fixed.length;
  if (!fixed.length) return;
  const json = JSON.stringify(fixed).replaceAll('$f360copy$', '');
  sql += `INSERT INTO ${t} OVERRIDING SYSTEM VALUE SELECT * FROM jsonb_populate_recordset(NULL::${t}, $f360copy$${json}$f360copy$::jsonb)${SEEDED.has(t) ? ' ON CONFLICT DO NOTHING' : t === 'f360.locations' ? ' ON CONFLICT (id) DO NOTHING' : ''};\n`;
};

if (!ONLY_INV) for (const t of CATALOG) {
  let rows = load(t);
  if (t === 'f360.locations') {
    // §5.8: the migrations already create "En camino" (transit) with their own id → align it to Carolina's id (nothing references it yet)
    const transit = rows.find((r) => r.type === 'transit');
    if (transit) sql += `UPDATE f360.locations SET id = '${transit.id}' WHERE type = 'transit' AND id <> '${transit.id}';\n`;
    rows = rows.map((r) => ({ ...r, legacy_channel_id: null }));   // Q6 default: no legacy channel link (transit: inserted only if missing)
  }
  if (t === 'f360.historical_sales' || t === 'f360.historical_sales_log') rows = rows.filter((r) => !/^ZZ/i.test(JSON.stringify(r.label ?? r.notes ?? '')));
  add(t, rows);
}
// Q4 (option "history"): the staging4 channel travels as an inactive test channel, so the 666 confirmed homologations keep their FK.
if (s4 && !ONLY_INV) {
  sql += `INSERT INTO f360.sales_targets SELECT * FROM jsonb_populate_recordset(NULL::f360.sales_targets, $f360copy$${JSON.stringify([{ ...s4, active: false, is_test: true, is_production: false }])}$f360copy$::jsonb);\n`;
  for (const t of HOMOLOGATION) add(t, load(t));
}
// --exclude-events id,id: test events that must not travel (e.g. a SALE from a staging4 test order). Their movements go too,
// and the balances are RECOMPUTED from the remaining movements (never copied raw), so balance = Σ movements by construction.
const EXCLUDE = new Set((arg('--exclude-events') || '').split(',').map((x) => x.trim()).filter(Boolean));
if (WITH_INV || ONLY_INV) {
  const keep = (rows, key) => rows.filter((r) => !EXCLUDE.has(r[key]));
  for (const t of INVENTORY) {
    if (t === 'f360.inventory_events') add(t, keep(load(t), 'id'));
    else if (t === 'f360.inventory_movements') add(t, keep(load(t), 'event_id'));
    else if (t === 'f360.inventory_balances') {
      stats[t] = 'recomputed';
      sql += `INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at)
  SELECT variant_id, location_id, sum(q)::int, (array_agg(event_id ORDER BY occurred_at DESC))[1], max(occurred_at) FROM (
    SELECT m.variant_id, m.to_location_id AS location_id, m.quantity AS q, m.event_id, e.occurred_at FROM f360.inventory_movements m JOIN f360.inventory_events e ON e.id = m.event_id WHERE m.to_location_id IS NOT NULL
    UNION ALL
    SELECT m.variant_id, m.from_location_id, -m.quantity, m.event_id, e.occurred_at FROM f360.inventory_movements m JOIN f360.inventory_events e ON e.id = m.event_id WHERE m.from_location_id IS NOT NULL) x
  GROUP BY variant_id, location_id HAVING sum(q) <> 0;\n`;
    } else add(t, load(t));
  }
}

if (!ONLY_INV) {
// G8 · people by e-mail and the real channel (inactive until F5, Q3 default)
for (const m of auth.team) {
  const t = remap.get(m.id);
  if (t) sql += `INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES ('${t}', '${m.role}', ${`'${m.name.replaceAll("'", "''")}'`}, 'pase G8') ON CONFLICT (auth_user_id) DO NOTHING;\n`;
}
for (const id of auth.pii_viewers || []) {
  const t = remap.get(id);
  if (t) sql += `INSERT INTO f360.customer_pii_viewers (auth_user_id, granted_by) VALUES ('${t}', 'pase G8 (decisión Mario 2026-10-05)') ON CONFLICT DO NOTHING;\n`;
}
sql += `INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active, is_production, is_test)
  SELECT 'woo_production', 'Tienda en línea', 'https://fuxiaballerinas.com', id, false, true, false FROM f360.locations WHERE name = 'Bodega CDMX' AND type = 'warehouse';\n`;
// §5.9 / Q2 (decided 2026-10-06): the published app 1.0.2 still sells WITHOUT login (anon) and A2 stays out of the pase,
// so the legacy-store freeze check (offline_sales_client_guard) must be callable by anon. Definer; returns only
// 'migrada' / 'en_corte' / NULL. Revoked when A2 is applied with a new app version.
sql += `GRANT EXECUTE ON FUNCTION public.f360_legacy_channel_frozen(uuid) TO anon;\n`;
}
// bigserial history tables: move each sequence past the copied ids
sql += `DO $s$ DECLARE r record; m bigint; BEGIN
  FOR r IN SELECT n.nspname || '.' || c.relname AS t, a.attname AS col, pg_get_serial_sequence(n.nspname || '.' || c.relname, a.attname) AS seq
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0
    WHERE n.nspname = 'f360' AND c.relkind = 'r' AND pg_get_serial_sequence(n.nspname || '.' || c.relname, a.attname) IS NOT NULL LOOP
    EXECUTE format('SELECT max(%I) FROM %s', r.col, r.t) INTO m;
    IF m IS NOT NULL THEN PERFORM setval(r.seq, m); END IF;
  END LOOP; END $s$;\n`;
sql += DRY ? 'ROLLBACK;\n' : 'COMMIT;\n';

if (EMIT) {
  writeFileSync(EMIT, sql);
  console.log(JSON.stringify({ mode: 'emitted (not executed)', file: EMIT, bytes: sql.length, with_inventory: WITH_INV, team_mapped: remap.size, rows: stats }, null, 1));
  process.exit(0);
}
psql(sql);
console.log(JSON.stringify({ mode: DRY ? 'dry-run (rolled back)' : 'committed', with_inventory: WITH_INV, homologation: s4 ? 'history (woo_staging4 inactive)' : 'none',
  team_mapped: remap.size, team_missing: missingTeam, rows: stats }, null, 1));
