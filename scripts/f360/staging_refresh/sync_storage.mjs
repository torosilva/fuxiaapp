// Fuxia 360 · Copia PROD → STAGING · fotos de producto. Lo llama refresh.sh.
// Copia a staging los archivos del bucket product-images que falten o hayan cambiado en prod (mismo nombre,
// tamaño y eTag = sin cambio). No borra nada en staging. Prod solo se LEE.
// No se copian `avatars` ni `tryon-temp`: son fotos de clientas.
// Credenciales: SB_TOKEN (sesión de la CLI de Supabase) → claves service_role de cada proyecto, solo en memoria.
//   node sync_storage.mjs --dry-run | --apply
const PROD_REF = 'tgzgiwfzddsghnxgkcqd';
const STAGING_REF = 'faltxpkaicwpnlqaxrdu';
const BUCKETS = ['product-images'];
const CONCURRENCY = 6;

const mode = process.argv[2];
if (!['--dry-run', '--apply'].includes(mode)) { console.error('uso: node sync_storage.mjs --dry-run | --apply'); process.exit(2); }
const token = process.env.SB_TOKEN;
if (!token) { console.error('ABORT: falta SB_TOKEN'); process.exit(2); }

async function serviceKey(ref) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys?reveal=true`, { headers: { Authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`api-keys ${ref}: http ${r.status}`);
  const k = (await r.json()).find((x) => x.name === 'service_role');
  if (!k?.api_key) throw new Error(`sin service_role para ${ref}`);
  return k.api_key;
}

function project(ref, key) {
  const base = `https://${ref}.supabase.co/storage/v1`;
  const h = { apikey: key, Authorization: `Bearer ${key}` };
  const enc = (p) => p.split('/').map(encodeURIComponent).join('/');
  return {
    ref,
    async bucket(id) {
      const r = await fetch(`${base}/bucket/${id}`, { headers: h });
      return r.ok ? r.json() : null;
    },
    async putBucket(b, exists) {
      const body = { id: b.id, name: b.name, public: b.public, file_size_limit: b.file_size_limit, allowed_mime_types: b.allowed_mime_types };
      const r = await fetch(exists ? `${base}/bucket/${b.id}` : `${base}/bucket`, {
        method: exists ? 'PUT' : 'POST', headers: { ...h, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
      });
      if (!r.ok) throw new Error(`bucket ${b.id} en ${ref}: http ${r.status}`);
    },
    async list(bucket, prefix = '') {             // recursivo: { ruta: {size, eTag, mimetype, cacheControl} }
      const out = {};
      for (let offset = 0; ; offset += 1000) {
        const r = await fetch(`${base}/object/list/${bucket}`, {
          method: 'POST', headers: { ...h, 'Content-Type': 'application/json' },
          body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }),
        });
        if (!r.ok) throw new Error(`list ${bucket}/${prefix} en ${ref}: http ${r.status}`);
        const items = await r.json();
        for (const it of items) {
          const path = prefix ? `${prefix}/${it.name}` : it.name;
          if (it.id === null) Object.assign(out, await this.list(bucket, path));
          else out[path] = it.metadata || {};
        }
        if (items.length < 1000) break;
      }
      return out;
    },
    async get(bucket, path) {
      const r = await fetch(`${base}/object/authenticated/${bucket}/${enc(path)}`, { headers: h });
      if (!r.ok) throw new Error(`descarga ${bucket}/${path}: http ${r.status}`);
      return Buffer.from(await r.arrayBuffer());
    },
    async put(bucket, path, bytes, meta) {
      const r = await fetch(`${base}/object/${bucket}/${enc(path)}`, {
        method: 'POST',
        headers: { ...h, 'x-upsert': 'true', 'Content-Type': meta.mimetype || 'application/octet-stream',
                   'Cache-Control': meta.cacheControl || 'max-age=3600' },
        body: bytes,
      });
      if (!r.ok) throw new Error(`subida ${bucket}/${path}: http ${r.status} ${(await r.text()).slice(0, 200)}`);
    },
  };
}

const prod = project(PROD_REF, await serviceKey(PROD_REF));
const stg = project(STAGING_REF, await serviceKey(STAGING_REF));
let failed = 0;

for (const bucket of BUCKETS) {
  const pb = await prod.bucket(bucket);
  if (!pb) { console.log(`   ${bucket}: no existe en prod, se omite`); continue; }
  const sb = await stg.bucket(bucket);
  if (mode === '--apply' && (!sb || sb.public !== pb.public)) await stg.putBucket(pb, !!sb);

  const src = await prod.list(bucket);
  const dst = sb ? await stg.list(bucket) : {};
  const todo = Object.keys(src).filter((p) => !dst[p] || dst[p].size !== src[p].size || dst[p].eTag !== src[p].eTag);
  const extra = Object.keys(dst).filter((p) => !src[p]).length;
  console.log(`   ${bucket}: prod ${Object.keys(src).length} · staging ${Object.keys(dst).length} · por copiar ${todo.length} · solo en staging ${extra} (se conservan)`);
  if (mode !== '--apply' || !todo.length) continue;

  let done = 0;
  const queue = [...todo];
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    for (let p = queue.shift(); p !== undefined; p = queue.shift()) {
      try { await stg.put(bucket, p, await prod.get(bucket, p), src[p]); done++; }
      catch (e) { failed++; console.log(`   ✗ ${e.message}`); }
    }
  }));
  console.log(`   ${bucket}: copiados ${done}/${todo.length}`);
}
if (failed) { console.log(`   ${failed} archivo(s) fallaron`); process.exit(1); }
