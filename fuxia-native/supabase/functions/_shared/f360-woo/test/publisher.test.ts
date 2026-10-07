// Publisher against the in-memory Woo. Run: node --test fuxia-native/supabase/functions/_shared/f360-woo/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { publish } from '../publisher.ts';
import { mockAdapter, mockStore, type MockStore } from '../mock.ts';
import { withFaults, type Fault } from '../faults.ts';
import { stockToPush, parentSku } from '../mapping.ts';
import { FakeDb, macarena } from './fakedb.ts';

const OPTS = { storageBase: 'https://staging.example.supabase.co' };
const run = (db: FakeDb, store: MockStore, faults: Fault[] = []) =>
  publish(db.claim(), withFaults(mockAdapter(store), new Set(faults)), db.recorder(), OPTS);

/** The exact end state required for Macarena (P2.2 acceptance), asserted against the store itself. */
function assertMacarena(store: MockStore, db: FakeDb) {
  const products = [...store.products.values()].filter((p) => p.sku === 'F360-MACARENA');
  assert.equal(products.length, 1, 'exactly 1 Woo product');
  const p = products[0];
  assert.equal(p.type, 'variable');
  assert.equal(p.status, 'draft', 'not public');
  assert.deepEqual(p.categories.map((c) => c.id), [17]);
  assert.deepEqual(p.attributes.find((a) => a.id === 1)?.options, ['Nude', 'Negro', 'Rojo']);
  assert.deepEqual(p.attributes.find((a) => a.id === 2)?.options, ['35', '36', '37', '38', '39', '40']);
  assert.equal(p.images.length, 6, '2 photos × 3 colors');
  assert.equal(store.media.size, 6, 'no duplicate uploads in the media library');
  const vars = [...store.variations.values()].filter((v) => v.parent_id === p.id);
  assert.equal(vars.length, 18, '18 variations, 0 duplicates');
  assert.equal(new Set(vars.map((v) => v.sku)).size, 18);
  for (const v of vars) {
    assert.match(v.sku, /^F360-MACARENA-(NUDE|NEGRO|ROJO)-(35|36|37|38|39|40)$/);
    assert.equal(v.regular_price, '2800');
    assert.equal(v.manage_stock, true);
    const color = v.sku.split('-')[2];
    const firstPhoto = p.images.find((i) => i.name === `f360-m-${color.toLowerCase()}-1`);
    assert.equal(v.image?.id, firstPhoto?.id, `${v.sku} shows its color's main photo`);
  }
  const stock = Object.fromEntries(vars.map((v) => [v.sku, v.stock_quantity]));
  assert.equal(stock['F360-MACARENA-NUDE-37'], 4);
  assert.equal(stock['F360-MACARENA-NUDE-35'], 4);
  assert.equal(stock['F360-MACARENA-NUDE-36'], 0);
  assert.equal(stock['F360-MACARENA-NEGRO-37'], 2);
  assert.equal(stock['F360-MACARENA-ROJO-37'], 0);
  // Fuxia 360 links hold every Woo id
  assert.equal(db.productLink, p.id);
  assert.equal(db.variantLinks.size, 18);
  assert.equal(db.mediaLinks.size, 6);
}

test('first publish: 1 draft product, 3 colors × 6 sizes = 18 variations, photos, price, category, Bodega stock', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.deepEqual(r.summary.mismatches, []);
  assert.equal(r.summary.created, 18);
  assertMacarena(store, db);
  // terms: Negro reused (exists in the store), Nude + Rojo created; sizes 35–40 reused
  const terms = db.steps.filter((s) => s.step === 'terms');
  assert.deepEqual(terms.filter((s) => s.action === 'create').map((s) => s.ref), ['pa_color:Nude', 'pa_color:Rojo']);
  assert.equal(terms.filter((s) => s.action === 'reuse').length, 7);
});

test('publish again: still 1 product, 18 variations, 0 creates, no photo re-upload, stock unchanged', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  const before = store.calls.length;
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.equal(r.summary.created, 0);
  assert.equal(r.summary.updated, 18);
  assert.equal(r.summary.stock_pushed, 0, 'no stock writes when nothing changed');
  assert.equal(store.calls.slice(before).filter((c) => c === 'createProduct').length, 0);
  assertMacarena(store, db);
});

for (const fault of ['photo', 'product_crash', 'variation', 'stock'] as Fault[]) {
  test(`failure "${fault}" mid-publish → honest failure, then retry converges with no duplicates`, async () => {
    const store = mockStore(); const db = new FakeDb(macarena());
    const r1 = await run(db, store, [fault]);
    assert.notEqual(r1.status, 'succeeded', `${fault} must not report success`);
    assert.ok(r1.error, 'an error message for Carolina');
    assert.ok(db.steps.some((s) => !s.ok), 'the failing step is recorded');
    const r2 = await run(db, store);
    assert.equal(r2.status, 'succeeded', r2.error ?? '');
    assertMacarena(store, db);
    const r3 = await run(db, store);   // and a further sync is a no-op
    assert.equal(r3.status, 'succeeded');
    assert.equal(r3.summary.created, 0);
    assertMacarena(store, db);
  });
}

test('all four failures in a row, then retries until success → same single product', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  for (const f of ['photo', 'product_crash', 'variation', 'stock'] as Fault[]) await run(db, store, [f]);
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assertMacarena(store, db);
});

test('crash after create AND the link was never stored → recovered by SKU + F360 meta, not duplicated', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store, ['product_crash']);
  db.productLink = null; db.mediaLinks.clear();   // worst case: nothing about the product reached Fuxia 360
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.ok(db.steps.some((s) => s.step === 'product' && s.action === 'relink'));
  assertMacarena(store, db);
});

test('all variation links lost → every variation re-linked by SKU, 0 new variations', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  db.variantLinks.clear();
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.equal(r.summary.created, 0);
  assert.equal(db.steps.filter((s) => s.job === db.jobs && s.step === 'variations' && s.action === 'relink').length, 18);
  assertMacarena(store, db);
});

test('a color added later → same product, 24 variations; the new color starts at 0 stock', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  const camel = { id: 'c-camel', code: 'CAMEL', name: 'Camel', hex: null, media: [{ id: 'm-camel-1', path: 'f360/MACARENA/CAMEL/1.png', alt: null, woo_media_id: null }] };
  db.base.colors.push(camel);
  for (const size of db.base.sizes) db.base.variants.push({ id: `v-camel-${size}`, color_id: 'c-camel', size, sku: `F360-MACARENA-CAMEL-${size}`, status: 'active', ats: 0, woo_variation_id: null, last_pushed_stock: null });
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.equal(store.products.size, 1);
  assert.equal([...store.variations.values()].length, 24);
  assert.equal(r.summary.created, 6);
});

test('stock follows Bodega CDMX exactly (no reserve): receive 1 more Nude 37 → Woo 5', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  db.base.stock['F360-MACARENA-NUDE-37'] = 5;
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded');
  assert.equal(r.summary.stock_pushed, 1);
  assert.equal([...store.variations.values()].find((v) => v.sku === 'F360-MACARENA-NUDE-37')?.stock_quantity, 5);
});

test('stock formula: Woo = ATS; only a Woo sale not yet in the ledger is not added back', () => {
  assert.equal(stockToPush(4, null, null), 4);    // first push
  assert.equal(stockToPush(4, 4, 4), 4);          // nothing pending → exactly ATS (no reserve)
  assert.equal(stockToPush(5, 4, 4), 5);
  assert.equal(stockToPush(4, 4, 3), 3);          // Woo sold 1 the ledger hasn't seen → don't resell it
  assert.equal(stockToPush(4, 4, 9), 4);          // manual increase in Woo is ignored (F360 is canonical)
  assert.equal(stockToPush(0, 2, 0), 0);          // never negative
});

test('an archived variant is hidden (private) in Woo, never deleted', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  db.base.variants.find((v) => v.sku === 'F360-MACARENA-ROJO-40')!.status = 'archived';
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.equal(r.summary.hidden, 1);
  assert.equal([...store.variations.values()].length, 18, 'nothing deleted');
  assert.equal([...store.variations.values()].find((v) => v.sku === 'F360-MACARENA-ROJO-40')?.status, 'private');
});

test('SKU already used by a NON-F360 product → refuses and never modifies it', async () => {
  const store = mockStore(); const adapter = mockAdapter(store);
  const legacy = await adapter.createProduct({ name: 'Macarena vieja', type: 'variable', sku: parentSku('MACARENA'), status: 'publish' });
  const db = new FakeDb(macarena());
  const r = await publish(db.claim(), adapter, db.recorder(), OPTS);
  assert.equal(r.status, 'failed');
  assert.match(r.error!, /no es de Fuxia 360/);
  assert.equal(store.products.size, 1);
  assert.equal(store.products.get(legacy.id)?.name, 'Macarena vieja');
  assert.equal(store.variations.size, 0);
});

test('category: unknown Woo id or changed slug → fails before touching anything; categories are never created', async () => {
  for (const cat of [{ id: 999, slug: 'ballerinas' }, { id: 18, slug: 'ballerinas' }]) {
    const store = mockStore(); const db = new FakeDb(macarena());
    db.base.product.woo_category = cat;
    const r = await run(db, store);
    assert.equal(r.status, 'failed');
    assert.equal(store.products.size, 0);
    assert.equal(store.categories.length, 4);
  }
});

test('production target is refused in P2.2', async () => {
  const store = mockStore(); const db = new FakeDb(macarena()); db.isProduction = true;
  const r = await run(db, store);
  assert.equal(r.status, 'failed');
  assert.equal(store.calls.length, 0, 'not a single call to the store');
});

test('a product the owner already made public is left public (visibility never changed by a sync)', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  await run(db, store);
  store.products.get(db.productLink!)!.status = 'publish';
  const r = await run(db, store);
  assert.equal(store.products.get(db.productLink!)?.status, 'publish');
  assert.equal(r.status, 'succeeded', 'a live product re-synced (prices, photos…) is a success: visibility is the owner\'s decision, not a mismatch');
});

test('currency prices: COP / USD go to the store meta keys on the parent and every variation; a price change is re-sent', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  db.base.product.prices = [{ code: 'COP', woo_meta_key: '_price_cop', amount: 420000 }, { code: 'USD', woo_meta_key: '_price_usd', amount: 170 }];
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.summary.mismatches.join('; '));
  const parent = [...store.products.values()].find((p) => p.sku === 'F360-MACARENA')!;
  const meta = (m: { key: string; value: unknown }[], k: string) => m.find((x) => x.key === k)?.value;
  assert.equal(meta(parent.meta_data, '_price_cop'), '420000');
  assert.equal(meta(parent.meta_data, '_price_usd'), '170');
  const vars = [...store.variations.values()];
  assert.equal(vars.length, 18);
  assert.ok(vars.every((v) => meta(v.meta_data, '_price_cop') === '420000' && meta(v.meta_data, '_price_usd') === '170'), 'every variation carries both prices');
  db.base.product.prices = [{ code: 'COP', woo_meta_key: '_price_cop', amount: 400000 }, { code: 'USD', woo_meta_key: '_price_usd', amount: 170 }];
  const r2 = await run(db, store);
  assert.equal(r2.status, 'succeeded', r2.summary.mismatches.join('; '));
  assert.ok([...store.variations.values()].every((v) => meta(v.meta_data, '_price_cop') === '400000'), 'price change re-sent to every variation');
});

test('currency prices: a store value that differs from Fuxia 360 is reported by the verification', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  db.base.product.prices = [{ code: 'COP', woo_meta_key: '_price_cop', amount: 420000 }];
  await run(db, store);
  const v = [...store.variations.values()][0];
  v.meta_data.find((x) => x.key === '_price_cop')!.value = '370000';          // someone edits it in Woo
  const s = db.claim();
  const { verify } = await import('../mapping.ts');
  const out = verify(s, [...store.products.values()][0], [...store.variations.values()], { colorAttr: 1, sizeAttr: 2 }, new Map());
  assert.ok(out.some((m) => m.includes('_price_cop 370000')), out.join('; '));
});

// ── U2 · channel capabilities ──
test('production with its catalog ON publishes, but never touches the store stock (stock sync off)', async () => {
  const store = mockStore(); const db = new FakeDb(macarena()); db.isProduction = true; db.capabilities = { catalog_mode: 'on', stock_sync_mode: 'off', stock_policy: 'woo_owned' };
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', JSON.stringify(r.summary.mismatches));
  const p = [...store.products.values()].find((x) => x.sku === 'F360-MACARENA')!;
  assert.equal(p.status, 'draft', 'still created non-public');
  const vars = [...store.variations.values()].filter((v) => v.parent_id === p.id);
  assert.equal(vars.length, 18);
  for (const v of vars) {
    assert.equal(v.manage_stock, false, `${v.sku} without stock control`);
    assert.equal((v as { stock_status?: string }).stock_status, 'instock', `${v.sku} sellable (no stock → made to order)`);
    assert.notEqual(v.stock_quantity, 0, `${v.sku} never created at 0`);
  }
  assert.equal(r.summary.stock_pushed, 0, 'no stock push');
  assert.ok(!store.calls.some((c) => c.includes('stock')), 'no stock call to the store');
});
test('production with catalog ON but no explicit stock mode → stock still untouched (production never defaults to managing stock)', async () => {
  const store = mockStore(); const db = new FakeDb(macarena()); db.isProduction = true; db.capabilities = { catalog_mode: 'on' };
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded');
  assert.ok([...store.variations.values()].every((v) => v.manage_stock === false));
});
test('production with catalog OFF is still refused before any store call', async () => {
  const store = mockStore(); const db = new FakeDb(macarena()); db.isProduction = true; db.capabilities = { catalog_mode: 'off', stock_sync_mode: 'off' };
  const r = await run(db, store);
  assert.equal(r.status, 'failed');
  assert.equal(store.calls.length, 0);
});
test('a test channel with stock sync ON keeps today\'s behaviour exactly (Bodega stock pushed)', async () => {
  const store = mockStore(); const db = new FakeDb(macarena()); db.capabilities = { catalog_mode: 'on', stock_sync_mode: 'on', stock_policy: 'f360_owned' };
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded');
  assertMacarena(store, db);
});

test('a colour written in another case than the store term ("negro" vs existing "Negro") still verifies (Mafalda chocolate, 2026-10-06)', async () => {
  const base = macarena();
  base.colors[1].name = 'negro';
  const store = mockStore(); const db = new FakeDb(base);
  const r = await run(db, store);
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.deepEqual(r.summary.mismatches, []);
});

test('photos go a few per store call (Cucarron 2026-10-07): same single product, all 6 photos, none uploaded twice', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  const calls: number[] = [];
  const adapter = mockAdapter(store);
  const counting = { ...adapter,
    createProduct: (b: Record<string, unknown>) => { calls.push((b.images as { src?: string }[]).filter((i) => i.src).length); return adapter.createProduct(b); },
    updateProduct: (id: number, b: Record<string, unknown>) => { if (b.images) calls.push((b.images as { src?: string }[]).filter((i) => i.src).length); return adapter.updateProduct(id, b); } };
  const r = await publish(db.claim(), counting, db.recorder(), { ...OPTS, photosPerCall: 2 });
  assert.equal(r.status, 'succeeded', r.error ?? '');
  assert.ok(calls.every((n) => n <= 2), `never more than 2 new photos per call: ${calls}`);
  assert.equal(calls.reduce((a, b) => a + b, 0), 6, 'each photo sent exactly once');
  assertMacarena(store, db);
});

test('out of time → "yield" (not a failure); the next run continues and ends with the same single product', async () => {
  const store = mockStore(); const db = new FakeDb(macarena());
  const first = await publish(db.claim(), mockAdapter(store), db.recorder(), { ...OPTS, deadline: Date.now() - 1 });
  assert.equal(first.status, 'yield');
  assert.equal(db.steps.at(-1)?.action, 'yield');
  const second = await run(db, store);
  assert.equal(second.status, 'succeeded', second.error ?? '');
  assertMacarena(store, db);
});
