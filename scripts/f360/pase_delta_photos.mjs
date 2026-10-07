#!/usr/bin/env node
// Pase D1 (2026-10-07) · copies the photos Carolina uploaded in the STAGING admin after the production copy, from the staging
// public bucket product-images (faltx…) to the production bucket (tgzg…). Only ADDS files under f360/ (x-upsert false: never
// overwrites, never deletes), then checks every path exists in production. The list is the storage_path of the product_media rows
// that supabase/pase/20261007_d1_delta_carolina_staging.sql inserts.
// Usage: node scripts/f360/pase_delta_photos.mjs supabase/pase/20261007_d1_delta_carolina_staging.sql
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { extname } from 'node:path';

const SQL = process.argv[2];
if (!SQL) throw new Error('uso: node scripts/f360/pase_delta_photos.mjs <archivo D1 .sql>');
const PROD_REF = 'tgzgiwfzddsghnxgkcqd', STG = 'https://faltxpkaicwpnlqaxrdu.supabase.co', BUCKET = 'product-images';
const line = readFileSync(SQL, 'utf8').split('\n').find((l) => l.startsWith('INSERT INTO f360.product_media'));
const paths = [...line.matchAll(/"storage_path": "([^"]+)"/g)].map((m) => m[1]);
if (!paths.length || paths.some((p) => !p.startsWith('f360/'))) throw new Error('no encontré rutas f360/ en el archivo');

let t = spawnSync('security', ['find-generic-password', '-s', 'Supabase CLI', '-a', 'supabase', '-w'], { encoding: 'utf8' }).stdout.trim();
if (t.startsWith('go-keyring-base64:')) t = Buffer.from(t.slice(18), 'base64').toString('utf8');
if (!t) throw new Error('no hay sesión de la CLI de Supabase');
const keys = await (await fetch(`https://api.supabase.com/v1/projects/${PROD_REF}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${t}` } })).json();
const KEY = (keys.find((k) => k.name === 'service_role') || {}).api_key;
if (!KEY) throw new Error('no encontré la llave de servicio de producción');
const API = `https://${PROD_REF}.supabase.co`, H = { apikey: KEY, Authorization: `Bearer ${KEY}` };
const TYPES = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif' };

let uploaded = 0, existed = 0; const failed = [];
for (const path of paths) {
  const src = await fetch(`${STG}/storage/v1/object/public/${BUCKET}/${path}`, { signal: AbortSignal.timeout(60_000) });
  if (!src.ok) { failed.push(`${path} (staging ${src.status})`); continue; }
  const r = await fetch(`${API}/storage/v1/object/${BUCKET}/${path}`, { method: 'POST', signal: AbortSignal.timeout(60_000),
    headers: { ...H, 'Content-Type': TYPES[extname(path).toLowerCase()] || 'application/octet-stream', 'x-upsert': 'false' },
    body: Buffer.from(await src.arrayBuffer()) });
  if (r.ok) uploaded++; else if (r.status === 409 || (await r.text()).includes('already exists')) existed++; else failed.push(`${path} (${r.status})`);
}
let missing = 0;
for (const path of paths) if ((await fetch(`${API}/storage/v1/object/public/${BUCKET}/${path}`, { method: 'HEAD' })).status !== 200) missing++;
console.log(JSON.stringify({ fotos: paths.length, subidas: uploaded, ya_estaban: existed, fallaron: failed, faltan_en_produccion: missing }, null, 1));
if (failed.length || missing) process.exit(1);
