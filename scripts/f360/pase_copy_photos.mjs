#!/usr/bin/env node
// Pase a producción · opción B · G9 (fotos). Uploads the catalog photos saved by the F0 backup
// (~/fuxia360-respaldos/fotos/<storage path>) to the target's public bucket product-images, never overwriting,
// and then checks that EVERY storage path referenced by the copied catalog exists in the target.
// Rehearsal: PASE_TARGET_API_URL=http://127.0.0.1:54321 PASE_TARGET_SERVICE_KEY=… PASE_TARGET_DB_URL=… node scripts/f360/pase_copy_photos.mjs
// Production (pase B4, approved by Mario as a permission rule): node scripts/f360/pase_copy_photos.mjs --production
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { extname, join, relative } from 'node:path';

// --production: target = the production project (tgzg…). Keys come from the Supabase CLI login (macOS keychain) through the
// Management API; nothing secret is printed or stored. Only ADDS files under f360/ (never overwrites, never deletes).
const PRODUCTION = process.argv.includes('--production'), PROD_REF = 'tgzgiwfzddsghnxgkcqd';
let API = (process.env.PASE_TARGET_API_URL || '').replace(/\/+$/, ''), KEY = process.env.PASE_TARGET_SERVICE_KEY || '', DB = process.env.PASE_TARGET_DB_URL || '';
let mgmt = null;
if (PRODUCTION) {
  let t = spawnSync('security', ['find-generic-password', '-s', 'Supabase CLI', '-a', 'supabase', '-w'], { encoding: 'utf8' }).stdout.trim();
  if (t.startsWith('go-keyring-base64:')) t = Buffer.from(t.slice(18), 'base64').toString('utf8');
  if (!t) throw new Error('no hay sesión de la CLI de Supabase');
  mgmt = async (path, init = {}) => {
    const r = await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}${path}`, { ...init, headers: { Authorization: `Bearer ${t}`, 'Content-Type': 'application/json', ...(init.headers || {}) } });
    if (!r.ok) throw new Error(`Management API ${path}: ${r.status}`);
    return r.json();
  };
  const keys = await mgmt('/api-keys?reveal=true');
  KEY = (keys.find((k) => k.name === 'service_role') || {}).api_key || '';
  API = `https://${PROD_REF}.supabase.co`;
  DB = 'management-api';
  if (!KEY) throw new Error('no encontré la llave de servicio de producción');
}
const ROOT = join(homedir(), 'fuxia360-respaldos', 'fotos'), BUCKET = 'product-images';
const PSQL = ['/opt/homebrew/opt/libpq/bin/psql', '/opt/homebrew/bin/psql', '/usr/local/bin/psql'].find(existsSync);
if (!API || !KEY || !DB) throw new Error('faltan PASE_TARGET_API_URL / PASE_TARGET_SERVICE_KEY / PASE_TARGET_DB_URL');
if (!PRODUCTION && (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(API) || !/@(127\.0\.0\.1|localhost):/.test(DB))) throw new Error('ABORT: sin --production solo se escribe en el ensayo local');
const TYPES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif' };
const H = { apikey: KEY, Authorization: `Bearer ${KEY}` };

function walk(dir) { return readdirSync(dir).flatMap((n) => { const p = join(dir, n); return statSync(p).isDirectory() ? walk(p) : [p]; }); }

const b = await fetch(`${API}/storage/v1/bucket/${BUCKET}`, { headers: H });
if (b.status !== 200 && PRODUCTION) throw new Error(`el bucket ${BUCKET} no existe en producción (no se crea desde aquí)`);
if (b.status !== 200) {
  const c = await fetch(`${API}/storage/v1/bucket`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ id: BUCKET, name: BUCKET, public: true }) });
  if (!c.ok) throw new Error(`no pude crear el bucket: ${c.status} ${await c.text()}`);
}
let uploaded = 0, existed = 0; const failed = [];
for (const file of walk(ROOT)) {
  const path = relative(ROOT, file).split('\\').join('/');
  if (!path.startsWith('f360/')) continue;                       // only Fuxia 360 catalog photos, never the app's own files
  let r = null;
  for (let attempt = 1; attempt <= 3 && !r; attempt++) {           // a dropped connection must not stop the run (60 s per photo)
    try {
      r = await fetch(`${API}/storage/v1/object/${BUCKET}/${path}`, { method: 'POST', signal: AbortSignal.timeout(60_000),
        headers: { ...H, 'Content-Type': TYPES[extname(file).toLowerCase()] || 'application/octet-stream', 'x-upsert': 'false' }, body: readFileSync(file) });
    } catch { await new Promise((ok) => setTimeout(ok, 3000 * attempt)); }
  }
  if (!r) failed.push(path);
  else if (r.ok) uploaded++; else if (r.status === 409 || (await r.text()).includes('already exists')) existed++; else failed.push(path);
}
const REFS = `SELECT coalesce(json_agg(DISTINCT p), '[]') AS j FROM (SELECT storage_path p FROM f360.product_media WHERE storage_path IS NOT NULL
  UNION SELECT image_path FROM f360.product_colors WHERE image_path IS NOT NULL UNION SELECT image_path FROM f360.products WHERE image_path IS NOT NULL) z WHERE p !~ '^https?://'`;
let referenced;
if (PRODUCTION) {
  referenced = (await mgmt('/database/query', { method: 'POST', body: JSON.stringify({ query: REFS, read_only: true }) }))[0].j;
} else {
  const q = spawnSync(PSQL, [DB, '-X', '-At', '-c', REFS + ';'], { encoding: 'utf8' });
  if (q.status !== 0) throw new Error('psql falló');
  referenced = JSON.parse(q.stdout.trim());
}
const missing = [];
for (const p of referenced) {
  const r = await fetch(`${API}/storage/v1/object/public/${BUCKET}/${p}`, { method: 'HEAD', signal: AbortSignal.timeout(30_000) }).catch(() => null);
  if (!r || !r.ok) missing.push(p);
}
console.log(JSON.stringify({ files_in_backup: uploaded + existed + failed.length, uploaded, already_there: existed, failed: failed.length,
  referenced_by_catalog: referenced.length, missing_in_target: missing.length, missing_sample: missing.slice(0, 5) }, null, 1));
process.exit(failed.length || missing.length ? 1 : 0);
