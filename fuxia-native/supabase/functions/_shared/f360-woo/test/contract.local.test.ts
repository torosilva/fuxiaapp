// CONTRACT tests: the same publisher + REST adapter against a REAL WooCommerce (throwaway local Docker store).
// Refuses any non-localhost store. Run (from repo root):
//   set -a; . tools/woo-docker/.env.local; set +a; node --test fuxia-native/supabase/functions/_shared/f360-woo/test/contract.local.test.ts
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server } from 'node:http';
import { deflateSync } from 'node:zlib';
import { publish } from '../publisher.ts';
import { restAdapter } from '../rest.ts';
import { withFaults, type Fault } from '../faults.ts';
import type { WooAdapter } from '../types.ts';
import { FakeDb, macarena, type Base } from './fakedb.ts';

const BASE = process.env.WOO_BASE_URL ?? '';
if (!/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(BASE)) throw new Error('Contract tests only run against the local Docker store (WOO_BASE_URL=http://localhost:8080).');
const woo = restAdapter({ baseUrl: BASE, user: process.env.WOO_USER!, secret: process.env.WOO_SECRET! });
const PHOTO_PORT = 8099;
const STORAGE = `http://host.docker.internal:${PHOTO_PORT}`;   // what WordPress (inside Docker) downloads from

// ── tiny PNG generator (solid color) so no binary fixtures are needed ──
function crc32(buf: Buffer) { let c = ~0; for (const b of buf) { c ^= b; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xEDB88320 & -(c & 1)); } return ~c >>> 0; }
function png(r: number, g: number, b: number, w = 64, h = 80) {
  const chunk = (type: string, data: Buffer) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type), data]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, crc]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
  const row = Buffer.concat([Buffer.from([0]), Buffer.alloc(w * 3).map((_, i) => [r, g, b][i % 3])]);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(Buffer.concat(Array(h).fill(row)))), chunk('IEND', Buffer.alloc(0))]);
}
const RGB: Record<string, [number, number, number]> = { NUDE: [216, 185, 160], NEGRO: [28, 26, 23], ROJO: [158, 42, 43], CAMEL: [176, 122, 74] };
let server: Server;
let brokenPhotos = false;   // when true the photo server answers 404 (a REAL download failure inside Woo)
let ballerinas: { id: number; slug: string };

before(async () => {
  server = createServer((req, res) => {
    if (brokenPhotos) { res.writeHead(404); res.end(); return; }
    const color = Object.keys(RGB).find((k) => req.url?.includes(`/${k}/`)) ?? 'NUDE';
    res.writeHead(200, { 'Content-Type': 'image/png' }); res.end(png(...RGB[color]));
  });
  await new Promise<void>((ok) => server.listen(PHOTO_PORT, '0.0.0.0', ok));
  const r = await fetch(`${BASE}/wp-json/wc/v3/products/categories?slug=ballerinas`, { headers: { Authorization: 'Basic ' + btoa(`${process.env.WOO_USER}:${process.env.WOO_SECRET}`) } });
  const [cat] = await r.json() as { id: number; slug: string }[];
  ballerinas = { id: cat.id, slug: cat.slug };
});
after(() => server?.close());

/** Macarena with a unique code per test (the local store is shared across tests). */
function model(tag: string): Base {
  const b = macarena();
  const code = `CT${Date.now().toString(36).toUpperCase()}${tag}`;
  b.product = { ...b.product, id: `p-${code.toLowerCase()}`, code, name: `Macarena ${code}`, slug: `macarena-${code.toLowerCase()}`, woo_category: ballerinas };
  for (const c of b.colors) for (const m of c.media) { m.id = `${code.toLowerCase()}-${m.id}`; m.path = m.path.replace('/MACARENA/', `/${code}/`); }
  const stock: Record<string, number> = {};
  for (const v of b.variants) { const old = v.sku; v.sku = old.replace('F360-MACARENA-', `F360-${code}-`); v.id = `${code.toLowerCase()}-${v.id}`; if (b.stock[old]) stock[v.sku] = b.stock[old]; }
  b.stock = stock;
  return b;
}
const run = (db: FakeDb, faults: Fault[] = [], adapter: WooAdapter = woo) =>
  publish(db.claim(), withFaults(adapter, new Set(faults)), db.recorder(), { storageBase: STORAGE });

/** Reads the REAL store back and checks the full Macarena contract. */
async function assertInStore(db: FakeDb) {
  const code = db.base.product.code;
  const found = await fetch(`${BASE}/wp-json/wc/v3/products?search=${encodeURIComponent(code)}&status=any&per_page=100`,
    { headers: { Authorization: 'Basic ' + btoa(`${process.env.WOO_USER}:${process.env.WOO_SECRET}`) } }).then((r) => r.json()) as { id: number; sku: string }[];
  assert.equal(found.filter((p) => p.sku === `F360-${code}`).length, 1, 'exactly 1 Woo product (no duplicates)');
  const p = (await woo.getProduct(db.productLink!))!;
  assert.equal(p.sku, `F360-${code}`);
  assert.equal(p.type, 'variable');
  assert.equal(p.status, 'draft', 'not public');
  assert.deepEqual(p.categories.map((c) => c.id), [ballerinas.id]);
  // REAL-Woo finding: options of a GLOBAL attribute come back in the attribute's term order (here alphabetical),
  // not in the order sent. The storefront color order is therefore a pa_color setting (validate on SiteGround).
  assert.deepEqual([...(p.attributes.find((a) => a.name === 'Color')?.options ?? [])].sort(), ['Negro', 'Nude', 'Rojo']);
  assert.deepEqual(p.attributes.find((a) => a.name === 'Medida')?.options, ['35', '36', '37', '38', '39', '40']);
  assert.equal(p.images.length, 6);
  const vars = await woo.listVariations(p.id);
  assert.equal(vars.length, 18, '18 variations');
  assert.equal(new Set(vars.map((v) => v.sku)).size, 18, '0 duplicate SKUs');
  const bySku = Object.fromEntries(vars.map((v) => [v.sku, v]));
  const nude37 = bySku[`F360-${code}-NUDE-37`];
  assert.equal(nude37.regular_price, '2800');
  assert.equal(nude37.manage_stock, true);
  assert.equal(nude37.stock_quantity, 4);
  assert.equal(bySku[`F360-${code}-NEGRO-37`].stock_quantity, 2);
  assert.equal(bySku[`F360-${code}-ROJO-37`].stock_quantity, 0);
  assert.equal(bySku[`F360-${code}-NUDE-36`].stock_quantity, 0);
  const nudeMain = p.images.find((i) => i.name === `f360-${code.toLowerCase()}-m-nude-1`)!;
  assert.equal(nude37.image?.id, nudeMain.id, 'variation shows its color main photo');
  assert.equal(db.variantLinks.size, 18);
  assert.equal(db.mediaLinks.size, 6);
  return { p, vars };
}

test('REAL Woo: publish Macarena → 1 draft product, 18 variations; publish again → still 1 / 18, 0 duplicates', async () => {
  const db = new FakeDb(model('A'));
  const r1 = await run(db);
  assert.equal(r1.status, 'succeeded', r1.error ?? JSON.stringify(r1.summary.mismatches));
  const first = await assertInStore(db);
  const r2 = await run(db);
  assert.equal(r2.status, 'succeeded', r2.error ?? '');
  assert.equal(r2.summary.created, 0);
  assert.equal(r2.summary.stock_pushed, 0);
  const second = await assertInStore(db);
  assert.equal(second.p.id, first.p.id);
  assert.deepEqual(second.p.images.map((i) => i.id), first.p.images.map((i) => i.id), 'photos not re-uploaded');
});

for (const fault of ['photo', 'product_crash', 'variation', 'stock'] as Fault[]) {
  test(`REAL Woo: failure "${fault}" → retry converges to 1 product / 18 variations`, async () => {
    const db = new FakeDb(model(fault.slice(0, 2).toUpperCase()));
    const r1 = await run(db, [fault]);
    assert.notEqual(r1.status, 'succeeded');
    const r2 = await run(db);
    assert.equal(r2.status, 'succeeded', r2.error ?? JSON.stringify(r2.summary.mismatches));
    await assertInStore(db);
  });
}

test('REAL Woo: links lost after a crash → recovered by SKU (no duplicate product or variations)', async () => {
  const db = new FakeDb(model('L'));
  await run(db, ['product_crash']);
  db.productLink = null; db.mediaLinks.clear(); db.variantLinks.clear();
  const r = await run(db);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  await assertInStore(db);
});

test('REAL Woo: sale price on the model reaches every variation (one price per model)', async () => {
  const db = new FakeDb(model('S'));
  db.base.product.sale_price = 2400;
  const r = await run(db);
  assert.equal(r.status, 'succeeded', r.error ?? JSON.stringify(r.summary.mismatches));
  const vars = await woo.listVariations(db.productLink!);
  assert.ok(vars.every((v) => v.regular_price === '2800' && v.sale_price === '2400'));
});

test('REAL Woo: a photo that Woo cannot download (real 404) → failed, nothing half-created; fixed → converges', async () => {
  const db = new FakeDb(model('P'));
  brokenPhotos = true;
  const r1 = await run(db);
  brokenPhotos = false;
  assert.equal(r1.status, 'failed');
  assert.match(r1.error!, /Error de la tienda/);
  const r2 = await run(db);
  assert.equal(r2.status, 'succeeded', r2.error ?? JSON.stringify(r2.summary.mismatches));
  await assertInStore(db);
  console.log(`   real Woo error text: ${r1.error}`);
});
