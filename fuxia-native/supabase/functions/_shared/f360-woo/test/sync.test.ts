// Stock worker, reconciliation and webhook helpers against the in-memory Woo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { mockAdapter, mockStore } from '../mock.ts';
import { withFaults } from '../faults.ts';
import { pushStock, reconcile, type Rpc } from '../sync.ts';
import { minimizeOrder, verifyWooSignature, wooSignature } from '../orders.ts';

// A variable product with 2 variations in the mock store.
async function setup() {
  const store = mockStore(); const woo = mockAdapter(store);
  const p = await woo.createProduct({ name: 'X', type: 'variable', sku: 'F360-X', status: 'draft' });
  const r = await woo.batchVariations(p.id, { create: [{ sku: 'F360-X-NEGRO-37', manage_stock: true, stock_quantity: 2 }, { sku: 'F360-X-NEGRO-38', manage_stock: true, stock_quantity: 0 }] }, 'variations');
  const [v37, v38] = r.create as { id: number }[];
  return { store, woo, pid: p.id, v37: v37.id, v38: v38.id };
}
// Minimal stand-in for the three DB RPCs used by the worker.
function fakeDb(claims: Record<string, unknown>[]) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc: Rpc = async <T,>(fn: string, args: Record<string, unknown>) => {
    calls.push({ fn, args });
    if (fn === 'f360_sync_claim_stock' || fn === 'f360_reconcile_snapshot') return claims as T;
    if (fn === 'f360_sync_stock_result') { const rs = args.p_results as { ok: boolean }[]; return { ok: rs.filter((x) => x.ok).length, failed: rs.filter((x) => !x.ok).length } as T; }
    if (fn === 'f360_reconcile_finish') { const it = (args.p_run as { items: { state: string }[] }).items; return { checked: it.length, in_sync: it.filter((x) => x.state === 'in_sync').length, drifted: it.filter((x) => x.state === 'drift').length, missing: it.filter((x) => x.state === 'missing').length } as T; }
    throw new Error(fn);
  };
  return { rpc, calls };
}

test('push: Woo gets exactly the Bodega stock (no reserve)', async () => {
  const { store, woo, pid, v37 } = await setup();
  const db = fakeDb([{ variant_id: 'a', claimed_at: 't', sku: 'F360-X-NEGRO-37', woo_product_id: pid, woo_variation_id: v37, ats: 5, expected: 2 }]);
  const r = await pushStock(db.rpc, woo, 'woo_local');
  assert.deepEqual(r, { claimed: 1, ok: 1, failed: 0 });
  assert.equal(store.variations.get(v37)?.stock_quantity, 5);
});

test('push after an ingested Woo sale: Woo 1, Bodega 1, expected 1 → stays 1 (no double discount)', async () => {
  const { store, woo, pid, v37 } = await setup();
  store.variations.get(v37)!.stock_quantity = 1;     // Woo discounted the sale itself
  const db = fakeDb([{ variant_id: 'a', claimed_at: 't', sku: 's', woo_product_id: pid, woo_variation_id: v37, ats: 1, expected: 1 }]);
  await pushStock(db.rpc, woo, 'woo_local');
  assert.equal(store.variations.get(v37)?.stock_quantity, 1);
  assert.equal(store.calls.filter((c) => c === 'batchVariations').length, 1, 'no stock write needed (only the setup batch)');
});

test('push with a Woo sale NOT yet ingested: Woo 1, Bodega 2, expected 2 → pushes 1 (does not resell the pair)', async () => {
  const { store, woo, pid, v37 } = await setup();
  store.variations.get(v37)!.stock_quantity = 1;
  const db = fakeDb([{ variant_id: 'a', claimed_at: 't', sku: 's', woo_product_id: pid, woo_variation_id: v37, ats: 2, expected: 2 }]);
  await pushStock(db.rpc, woo, 'woo_local');
  assert.equal(store.variations.get(v37)?.stock_quantity, 1);
});

test('push: temporary Woo failure → reported as failed (queue retries later), nothing lost', async () => {
  const { store, woo, pid, v37 } = await setup();
  const db = fakeDb([{ variant_id: 'a', claimed_at: 't', sku: 's', woo_product_id: pid, woo_variation_id: v37, ats: 7, expected: 2 }]);
  const r1 = await pushStock(db.rpc, withFaults(woo, new Set(['stock'])), 'woo_local');
  assert.deepEqual(r1, { claimed: 1, ok: 0, failed: 1 });
  assert.equal(store.variations.get(v37)?.stock_quantity, 2);
  const res = db.calls.find((c) => c.fn === 'f360_sync_stock_result')!.args.p_results as { error: string }[];
  assert.match(res[0].error, /Tienda no disponible/);
  const r2 = await pushStock(db.rpc, woo, 'woo_local');
  assert.deepEqual(r2, { claimed: 1, ok: 1, failed: 0 });
  assert.equal(store.variations.get(v37)?.stock_quantity, 7);
});

test('push: variation deleted in Woo → failed with a clear message', async () => {
  const { woo, pid } = await setup();
  const db = fakeDb([{ variant_id: 'a', claimed_at: 't', sku: 's', woo_product_id: pid, woo_variation_id: 999999, ats: 1, expected: 1 }]);
  const r = await pushStock(db.rpc, woo, 'woo_local');
  assert.equal(r.failed, 1);
});

test('reconcile: in sync / drift / missing', async () => {
  const { woo, pid, v37, v38 } = await setup();
  const db = fakeDb([
    { variant_id: 'a', sku: 'a', label: 'a', woo_product_id: pid, woo_variation_id: v37, ats: 2, expected: 2 },
    { variant_id: 'b', sku: 'b', label: 'b', woo_product_id: pid, woo_variation_id: v38, ats: 3, expected: 3 },
    { variant_id: 'c', sku: 'c', label: 'c', woo_product_id: pid, woo_variation_id: 123456, ats: 0, expected: 0 },
  ]);
  const r = await reconcile(db.rpc, woo, 'woo_local', 'Carolina');
  assert.deepEqual({ ...r }, { checked: 3, in_sync: 1, drifted: 1, missing: 1 });
});

test('webhook signature: Woo format (base64 HMAC-SHA256 of the raw body); tampering rejected', async () => {
  const body = JSON.stringify({ id: 1, status: 'processing' });
  const expected = createHmac('sha256', 's3cret').update(body).digest('base64');
  assert.equal(await wooSignature(body, 's3cret'), expected);
  assert.equal(await verifyWooSignature(body, expected, 's3cret'), true);
  assert.equal(await verifyWooSignature(body + ' ', expected, 's3cret'), false);
  assert.equal(await verifyWooSignature(body, expected, 'otro'), false);
  assert.equal(await verifyWooSignature(body, null, 's3cret'), false);
});

test('order minimization drops every customer field', () => {
  const m = minimizeOrder({ id: 9, status: 'processing', date_modified_gmt: '2026-09-26T10:00:00', currency: 'MXN',
    billing: { first_name: 'Ana', email: 'ana@x.com', phone: '555' }, shipping: { address_1: 'Calle' }, customer_note: 'hola', customer_id: 4,
    line_items: [{ id: 1, product_id: 5, variation_id: 6, sku: 'F360-X', quantity: 1, name: 'X', meta_data: [{ key: 'k', value: 'v' }] }], refunds: [] });
  const s = JSON.stringify(m);
  for (const bad of ['Ana', 'ana@x.com', '555', 'Calle', 'hola', 'billing', 'shipping', 'customer']) assert.ok(!s.includes(bad), bad);
  assert.deepEqual(m.line_items[0], { id: 1, product_id: 5, variation_id: 6, sku: 'F360-X', quantity: 1 });
});
