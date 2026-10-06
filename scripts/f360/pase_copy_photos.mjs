#!/usr/bin/env node
// Pase a producción · opción B · G9 (fotos). Uploads the catalog photos saved by the F0 backup
// (~/fuxia360-respaldos/fotos/<storage path>) to the target's public bucket product-images, never overwriting,
// and then checks that EVERY storage path referenced by the copied catalog exists in the target.
// THIS VERSION ONLY WRITES TO A LOCAL REHEARSAL STACK (127.0.0.1). Production needs Mario's approval of F4.
// Usage: PASE_TARGET_API_URL=http://127.0.0.1:54321 PASE_TARGET_SERVICE_KEY=… PASE_TARGET_DB_URL=… node scripts/f360/pase_copy_photos.mjs
import { spawnSync } from 'node:child_process';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { homedir } from 'node:os';
import { extname, join, relative } from 'node:path';

const API = (process.env.PASE_TARGET_API_URL || '').replace(/\/+$/, ''), KEY = process.env.PASE_TARGET_SERVICE_KEY || '', DB = process.env.PASE_TARGET_DB_URL || '';
const ROOT = join(homedir(), 'fuxia360-respaldos', 'fotos'), BUCKET = 'product-images';
const PSQL = ['/opt/homebrew/opt/libpq/bin/psql', '/opt/homebrew/bin/psql', '/usr/local/bin/psql'].find(existsSync);
if (!API || !KEY || !DB) throw new Error('faltan PASE_TARGET_API_URL / PASE_TARGET_SERVICE_KEY / PASE_TARGET_DB_URL');
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(API) || !/@(127\.0\.0\.1|localhost):/.test(DB)) throw new Error('ABORT: esta versión solo escribe en el ensayo local');
const TYPES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif' };
const H = { apikey: KEY, Authorization: `Bearer ${KEY}` };

function walk(dir) { return readdirSync(dir).flatMap((n) => { const p = join(dir, n); return statSync(p).isDirectory() ? walk(p) : [p]; }); }

const b = await fetch(`${API}/storage/v1/bucket/${BUCKET}`, { headers: H });
if (b.status !== 200) {
  const c = await fetch(`${API}/storage/v1/bucket`, { method: 'POST', headers: { ...H, 'Content-Type': 'application/json' }, body: JSON.stringify({ id: BUCKET, name: BUCKET, public: true }) });
  if (!c.ok) throw new Error(`no pude crear el bucket: ${c.status} ${await c.text()}`);
}
let uploaded = 0, existed = 0; const failed = [];
for (const file of walk(ROOT)) {
  const path = relative(ROOT, file).split('\\').join('/');
  const r = await fetch(`${API}/storage/v1/object/${BUCKET}/${path}`, { method: 'POST',
    headers: { ...H, 'Content-Type': TYPES[extname(file).toLowerCase()] || 'application/octet-stream', 'x-upsert': 'false' }, body: readFileSync(file) });
  if (r.ok) uploaded++; else if (r.status === 409 || (await r.text()).includes('already exists')) existed++; else failed.push(path);
}
const q = spawnSync(PSQL, [DB, '-X', '-At', '-c', `SELECT coalesce(json_agg(DISTINCT p), '[]') FROM (SELECT storage_path p FROM f360.product_media WHERE storage_path IS NOT NULL
  UNION SELECT image_path FROM f360.product_colors WHERE image_path IS NOT NULL UNION SELECT image_path FROM f360.products WHERE image_path IS NOT NULL) z WHERE p !~ '^https?://';`], { encoding: 'utf8' });
if (q.status !== 0) throw new Error('psql falló');
const referenced = JSON.parse(q.stdout.trim()); const missing = [];
for (const p of referenced) {
  const r = await fetch(`${API}/storage/v1/object/public/${BUCKET}/${p}`, { method: 'HEAD' });
  if (!r.ok) missing.push(p);
}
console.log(JSON.stringify({ files_in_backup: uploaded + existed + failed.length, uploaded, already_there: existed, failed: failed.length,
  referenced_by_catalog: referenced.length, missing_in_target: missing.length, missing_sample: missing.slice(0, 5) }, null, 1));
process.exit(failed.length || missing.length ? 1 : 0);
