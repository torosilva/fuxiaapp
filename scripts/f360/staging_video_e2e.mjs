// STAGING ONLY — videos en el producto (20261101000100), end to end as Carolina (demo owner): upload a real mp4 into the colour's
// folder (same storage policy the admin uses), attach it with f360_add_video, and check every refusal of the database.
// Run: scripts/s00a/run.sh ../f360/staging_video_e2e.mjs <archivo.mp4> [Producto] [CODIGO_COLOR]
// Leaves the video attached (so the product can then be published to staging4 with publish_staging4.ts).
import { readFileSync } from 'node:fs';
import { client, loadEnv, psql } from '../s00a/lib.mjs';

const env = loadEnv();
const [file, name = 'Cucarron', colorCode = 'AZUL-MARINO'] = process.argv.slice(2);
if (!file) throw new Error('uso: staging_video_e2e.mjs <archivo.mp4> [Producto] [CODIGO_COLOR]');
const row = psql(`select p.id || '|' || p.code || '|' || c.id from f360.products p join f360.product_colors c on c.product_id = p.id
  where p.name = '${name.replace(/'/g, '')}' and c.code = '${colorCode.replace(/'/g, '')}';`, {}, { readOnly: true }).trim().split('\n').pop();
if (!row) throw new Error(`no encontré ${name} / ${colorCode}`);
const [productId, productCode, colorId] = row.split('|');
const c = client(env);
const owner = await c.signIn('carolina.demo@staging.invalid', process.env.STAGING_DEMO_CAROLINA_PASSWORD);
const up = (path, bytes, type) => fetch(`${env.api}/storage/v1/object/product-images/${path}`, { method: 'POST',
  headers: { apikey: env.anon, Authorization: `Bearer ${owner.token}`, 'Content-Type': type }, body: bytes });
const add = (path) => c.rest('POST', 'rpc/f360_add_video', { token: owner.token, body: { p_product_id: productId, p_color_id: colorId, p_path: path } });
const folder = `f360/${productCode}/${colorCode}/`;
const results = [];
const expect = (label, ok, detail = '') => { results.push(ok); console.log(`${ok ? 'OK ' : 'FAIL'} ${label}${detail ? ` — ${detail}` : ''}`); };

// 1 · the real video
const path = `${folder}video-${crypto.randomUUID()}.mp4`;
const u = await up(path, readFileSync(file), 'video/mp4');
expect('subida al bucket como Carolina', u.ok, `http ${u.status}`);
const a = await add(path);
expect('f360_add_video acepta el mp4', a.ok, a.ok ? `${a.json.length} video(s) en el producto` : a.json?.message);

// 2 · refusals
const r1 = await add(`f360/${productCode}/OTRO-COLOR/video-x.mp4`);
expect('rechaza un video de otra carpeta', !r1.ok, r1.json?.message);
const fake = `${folder}video-${crypto.randomUUID()}.mp4`;
await up(fake, Buffer.from('no soy un video'), 'image/jpeg');
const r2 = await add(fake);
expect('rechaza un archivo que no es video', !r2.ok, r2.json?.message);
const r3 = await add(path);
expect('rechaza el mismo video dos veces', !r3.ok, r3.json?.message);
const anon = await c.rest('POST', 'rpc/f360_add_video', { body: { p_product_id: productId, p_color_id: colorId, p_path: path } });
expect('rechaza sin sesión', !anon.ok, `http ${anon.status}`);
const list = await c.rest('POST', 'rpc/f360_product_videos', { token: owner.token, body: { p_product_id: productId } });
expect('f360_product_videos lo lista', list.ok && list.json.some((v) => v.path === path));
const pub = await fetch(`${env.api}/storage/v1/object/public/product-images/${path}`, { method: 'HEAD' });
expect('URL pública sirve video/mp4', pub.ok && /video\/mp4/.test(pub.headers.get('content-type') ?? ''), pub.headers.get('content-type') ?? '');
console.log(`video: ${path}`);
if (results.some((x) => !x)) process.exit(1);
