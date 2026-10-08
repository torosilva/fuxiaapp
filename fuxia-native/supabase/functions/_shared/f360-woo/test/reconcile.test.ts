// S-G0 Measurement Truth — D2 order reconciliation + D1 Woo history import (synthetic fixtures; no network, no database).
// Run: node --test fuxia-native/supabase/functions/_shared/f360-woo/test/reconcile.test.ts
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { commerceHistoryImport, commerceReconcile, type CommerceWoo } from '../commerce.ts';
import { handleSync } from '../../../f360-woo-sync/handler.ts';

type Obj = Record<string, unknown>;
const order = (id: number, mod: string, extra: Obj = {}): Obj => ({
  id, status: 'completed', created_via: 'store-api', currency: 'MXN', date_created_gmt: '2026-08-01T10:00:00', date_paid_gmt: '2026-08-01T10:05:00',
  date_modified_gmt: mod, discount_total: '0', discount_tax: '0', shipping_total: '0', shipping_tax: '0', cart_tax: '0', total: '2800', total_tax: '0',
  billing: { first_name: 'Ana', email: 'ana@example.com', phone: '5512345678', country: 'MX' }, customer_ip_address: '201.1.2.3',
  line_items: [{ id: id * 10, product_id: 1, variation_id: 2, sku: 'X', quantity: 1, subtotal: '2800', subtotal_tax: '0', total: '2800', total_tax: '0' }],
  refunds: [], meta_data: [], ...extra,
});

/** In-memory Woo (read-only) + in-memory Fuxia 360 with the SAME rules as the SQL (key = order id; older never overwrites). */
function world(wooOrders: Obj[], f360: Map<number, { mod: string; via: string }>, cutover: number | null = null) {
  const reads = { stubs: 0, full: 0, fullIds: [] as number[] };
  const woo: CommerceWoo = {
    listOrders: async () => { throw new Error('reconciliation must list stubs, not full orders'); },
    listRefunds: async () => [],
    listOrderStubs: async (_after, page) => { reads.stubs++; return page === 1 ? wooOrders.map((o) => ({ id: o.id, status: o.status, date_modified_gmt: o.date_modified_gmt })) : []; },
    listOrderStubsCreated: async (_after, page) => { reads.stubs++; return page === 1 ? wooOrders.map((o) => ({ id: o.id, status: o.status, date_modified_gmt: o.date_modified_gmt, date_created_gmt: o.date_created_gmt })) : []; },
    getOrder: async (id) => { reads.full++; reads.fullIds.push(id); return wooOrders.find((o) => o.id === id) ?? null; },
  };
  const calls: { fn: string; args: Obj }[] = [];
  let runs = 0;
  const rpc = async <T>(fn: string, args: Obj): Promise<T> => {
    calls.push({ fn, args });
    if (fn === 'f360_commerce_reconcile_begin') return { run_id: ++runs, modified_after: null, orders_since_id: cutover, mode: 'first_run' } as T;
    if (fn === 'f360_commerce_run_begin') return { run_id: ++runs, modified_after: null } as T;
    if (fn === 'f360_commerce_run_end') return { ok: true } as T;
    if (fn === 'f360_commerce_reconcile_diff') {
      const list = args.p_orders as { id: number; date_modified_gmt: string }[];
      const missing = list.filter((o) => !f360.has(o.id) && (cutover === null || o.id > cutover)).map((o) => o.id);
      const before = list.filter((o) => !f360.has(o.id) && cutover !== null && o.id <= cutover).map((o) => o.id);
      const outdated = list.filter((o) => f360.has(o.id) && o.date_modified_gmt > f360.get(o.id)!.mod).map((o) => o.id);
      return { missing, outdated, before_cutover_missing: before, current: list.length - missing.length - before.length - outdated.length, orders_since_id: cutover } as T;
    }
    if (fn === 'f360_capture_order_economics') {
      const p = args.p_order as { id: number; date_modified_gmt: string };
      const prev = f360.get(p.id);
      if (!prev) { f360.set(p.id, { mod: p.date_modified_gmt, via: String(args.p_via) }); return { result: 'inserted', refunds: 0 } as T; }
      if (p.date_modified_gmt < prev.mod) return { result: 'stale' } as T;
      if (p.date_modified_gmt === prev.mod) return { result: 'unchanged' } as T;
      f360.set(p.id, { mod: p.date_modified_gmt, via: prev.via }); return { result: 'updated' } as T;   // first source is kept
    }
    throw new Error(`unexpected rpc ${fn}`);
  };
  return { woo, rpc, calls, reads };
}

test('reconcile: detects Woo orders missing in Fuxia 360 and recovers them through the one capture path (p_via=poll)', async () => {
  const f360 = new Map([[5352, { mod: '2026-10-09T10:00:00', via: 'webhook' }]]);
  const w = world([order(5352, '2026-10-09T10:00:00'), order(5353, '2026-10-09T11:00:00'), order(5354, '2026-10-09T12:00:00')], f360);
  const out = await commerceReconcile(w.rpc, w.woo, 'woo_production');
  assert.equal(out.ok, true);
  assert.equal(out.stats.woo_seen, 3); assert.equal(out.stats.current, 1);
  assert.equal(out.stats.detected_missing, 2); assert.equal(out.stats.recovered, 2); assert.equal(out.stats.errors, 0);
  assert.deepEqual(w.reads.fullIds, [5353, 5354], 'full orders (with customer data) are read ONLY for the missing ones');
  assert.equal(f360.get(5353)!.via, 'poll'); assert.equal(f360.get(5352)!.via, 'webhook', 'a realtime order keeps its source');
  const end = w.calls.find((c) => c.fn === 'f360_commerce_run_end')!;
  assert.equal(end.args.p_ok, true); assert.equal(end.args.p_cursor, '2026-10-09T12:00:00Z');
  const cap = w.calls.filter((c) => c.fn === 'f360_capture_order_economics');
  assert.ok(cap.every((c) => c.args.p_via === 'poll'));
  assert.ok(!JSON.stringify(cap).includes('ana@example.com') && !JSON.stringify(cap).includes('201.1.2.3'), 'captured economics stay a whitelist');
});

test('TEST 9 · reconcile is idempotent: the second run detects and recovers nothing, and never duplicates', async () => {
  const f360 = new Map<number, { mod: string; via: string }>();
  const orders = [order(6001, '2026-10-09T10:00:00'), order(6002, '2026-10-09T11:00:00')];
  const w1 = world(orders, f360);
  const a = await commerceReconcile(w1.rpc, w1.woo, 'woo_staging4');
  const w2 = world(orders, f360);
  const b = await commerceReconcile(w2.rpc, w2.woo, 'woo_staging4');
  assert.equal(a.stats.recovered, 2);
  assert.equal(b.stats.detected_missing, 0); assert.equal(b.stats.recovered, 0); assert.equal(b.stats.current, 2);
  assert.equal(w2.reads.full, 0, 'no full order read on a clean second pass');
  assert.equal(f360.size, 2);
});

test('reconcile: an order Fuxia 360 holds in an older version is refreshed (status change), not re-created', async () => {
  const f360 = new Map([[7001, { mod: '2026-10-09T10:00:00', via: 'webhook' }]]);
  const w = world([order(7001, '2026-10-09T15:00:00', { status: 'cancelled' })], f360);
  const out = await commerceReconcile(w.rpc, w.woo, 'woo_staging4');
  assert.equal(out.stats.detected_outdated, 1); assert.equal(out.stats.refreshed, 1); assert.equal(out.stats.recovered, 0);
  assert.equal(f360.size, 1); assert.equal(f360.get(7001)!.mod, '2026-10-09T15:00:00'); assert.equal(f360.get(7001)!.via, 'webhook');
});

test('reconcile: orders at or before the cutover are counted for the history import, never recovered as realtime', async () => {
  const f360 = new Map<number, { mod: string; via: string }>();
  const w = world([order(5300, '2026-09-01T10:00:00'), order(5351, '2026-10-08T14:14:00'), order(5360, '2026-10-09T10:00:00')], f360, 5351);
  const out = await commerceReconcile(w.rpc, w.woo, 'woo_production');
  assert.equal(out.stats.before_cutover_missing, 2); assert.equal(out.stats.recovered, 1);
  assert.deepEqual([...f360.keys()], [5360]);
});

test('reconcile: a capture failure closes the run as failed with the order id, without moving the cursor', async () => {
  const f360 = new Map<number, { mod: string; via: string }>();
  const w = world([order(8001, '2026-10-09T10:00:00')], f360);
  const rpc = async <T>(fn: string, args: Obj): Promise<T> => {
    if (fn === 'f360_capture_order_economics') throw new Error('boom');
    return w.rpc<T>(fn, args);
  };
  const out = await commerceReconcile(rpc, w.woo, 'woo_staging4');
  assert.equal(out.ok, false); assert.deepEqual(out.stats.error_order_ids, [8001]); assert.equal(out.stats.detected_missing, 1);
  const end = w.calls.find((c) => c.fn === 'f360_commerce_run_end')!;
  assert.equal(end.args.p_ok, false); assert.equal(end.args.p_cursor, null);
});

test('reconcile: Woo unreachable → run closed as failed (source turns STALE, never silently fresh)', async () => {
  const w = world([], new Map());
  w.woo.listOrderStubs = async () => { throw new Error('Woo HTTP 503'); };
  const out = await commerceReconcile(w.rpc, w.woo, 'woo_staging4');
  assert.equal(out.ok, false); assert.match(String(out.error), /503/);
});

test('TEST 10 · history import is idempotent, respects the cutover, writes p_via=backfill, and dry run writes nothing', async () => {
  const f360 = new Map([[5351, { mod: '2026-10-08T14:20:00', via: 'webhook' }]]);
  const orders = [order(2082, '2026-06-12T19:10:00'), order(3000, '2026-07-01T10:00:00'), order(5351, '2026-10-08T14:20:00'), order(5400, '2026-10-10T10:00:00')];
  const dry = world(orders, f360, 5351);
  const d = await commerceHistoryImport(dry.rpc, dry.woo, 'woo_production', { dryRun: true, now: new Date('2026-10-10T00:00:00Z') });
  assert.equal(d.stats.detected_missing, 2); assert.equal(d.stats.imported, 0); assert.equal(f360.size, 1);
  assert.ok(!dry.calls.some((c) => c.fn === 'f360_capture_order_economics' || c.fn === 'f360_commerce_run_begin'), 'dry run: no write, no run');
  const w1 = world(orders, f360, 5351);
  const a = await commerceHistoryImport(w1.rpc, w1.woo, 'woo_production', { now: new Date('2026-10-10T00:00:00Z') });
  assert.equal(a.ok, true); assert.equal(a.stats.imported, 2); assert.equal(a.stats.after_cutover_skipped, 1); assert.equal(a.stats.already_current, 1);
  assert.equal(f360.get(2082)!.via, 'backfill'); assert.equal(f360.get(5351)!.via, 'webhook', 'a realtime order is never relabelled as history');
  assert.ok(!f360.has(5400), 'after the cutover = realtime domain (reconciliation), not history');
  const end = w1.calls.find((c) => c.fn === 'f360_commerce_run_end')!;
  assert.equal(end.args.p_cursor, null, 'history import never moves the reconciliation cursor');
  assert.equal((end.args.p_stats as Obj).source, 'woo_history_import');
  const w2 = world(orders, f360, 5351);
  const b = await commerceHistoryImport(w2.rpc, w2.woo, 'woo_production', { now: new Date('2026-10-10T00:00:00Z') });
  assert.equal(b.stats.imported, 0); assert.equal(b.stats.detected_missing, 0); assert.equal(w2.reads.full, 0);
  assert.equal(f360.size, 3);
});

test('TEST 11 · a duplicate Woo order cannot be created: the same order through webhook, reconciliation and history = one fact', async () => {
  const f360 = new Map<number, { mod: string; via: string }>();
  const orders = [order(9001, '2026-10-09T10:00:00')];
  f360.set(9001, { mod: '2026-10-09T10:00:00', via: 'webhook' });                   // webhook got it first
  const r = world(orders, f360); await commerceReconcile(r.rpc, r.woo, 'woo_staging4');
  const h = world(orders, f360); await commerceHistoryImport(h.rpc, h.woo, 'woo_staging4', { now: new Date('2026-10-10T00:00:00Z') });
  assert.equal(f360.size, 1); assert.equal(f360.get(9001)!.via, 'webhook');
  assert.equal(r.reads.full + h.reads.full, 0);
});

// ── handler gate: reconciliation follows the ORDER path, not the stock push ──
function handlerEnv(mode: Obj) {
  const calls: string[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    const fn = String(url).split('/rpc/')[1]; calls.push(fn);
    const body = fn === 'f360_channel_mode' ? mode
      : fn === 'f360_commerce_reconcile_begin' ? { run_id: 1, modified_after: null, orders_since_id: 5351, mode: 'first_run' }
      : fn === 'f360_commerce_reconcile_diff' ? { missing: [], outdated: [], before_cutover_missing: [], current: 0 } : { ok: true };
    void init; return new Response(JSON.stringify(body), { status: 200 });
  }) as typeof fetch;
  const env = { SUPABASE_URL: 'http://x', SUPABASE_SERVICE_ROLE_KEY: 'k', WOO_TARGET_KEY: 'woo_production', WOO_BASE_URL: 'https://shop.invalid', WOO_USER: 'u', WOO_SECRET: 's', F360_SYNC_SECRET: 'cron-secret' };
  const cw: CommerceWoo = { listOrders: async () => [], listRefunds: async () => [], listOrderStubs: async () => [], getOrder: async () => null };
  const send = (body: Obj) => handleSync(new Request('http://x', { method: 'POST', headers: { Authorization: 'Bearer cron-secret' }, body: JSON.stringify(body) }), env, { commerceWoo: cw });
  return { calls, send, restore: () => { globalThis.fetch = realFetch; } };
}

test('handler: production with stock OFF and orders ON runs the reconciliation on the cron tick (commerce_poll)', async (t) => {
  const h = handlerEnv({ stock_sync_mode: 'off', catalog_mode: 'on', orders_mode: 'on' }); t.after(h.restore);
  const res = await h.send({ action: 'commerce_poll' });
  const out = await res.json();
  assert.equal(res.status, 200); assert.equal(out.ok, true); assert.equal(out.stats.mode, 'first_run');
  assert.ok(h.calls.includes('f360_commerce_reconcile_begin') && h.calls.includes('f360_commerce_run_end'));
});

test('handler: orders OFF → reconciliation skipped (no Woo read, no run)', async (t) => {
  const h = handlerEnv({ stock_sync_mode: 'on', catalog_mode: 'on', orders_mode: 'off' }); t.after(h.restore);
  const out = await (await h.send({ action: 'commerce_poll' })).json();
  assert.match(String(out.skipped), /pedidos apagados/); assert.ok(!h.calls.includes('f360_commerce_reconcile_begin'));
});

test('handler: a channel without orders_mode (older database) keeps the previous rule: runs when stock is on', async (t) => {
  const h = handlerEnv({ stock_sync_mode: 'on', catalog_mode: 'on', orders_mode: null }); t.after(h.restore);
  const out = await (await h.send({ action: 'commerce_poll' })).json();
  assert.equal(out.ok, true);
});

test('handler: the scheduler cannot widen the window (lookback_hours is for an owner/operator only)', async (t) => {
  const h = handlerEnv({ stock_sync_mode: 'off', catalog_mode: 'on', orders_mode: 'on' }); t.after(h.restore);
  let seen: unknown = 'unset';
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string, init: RequestInit) => {
    if (String(url).endsWith('/f360_commerce_reconcile_begin')) seen = JSON.parse(String(init.body)).p_lookback_hours;
    return realFetch(url, init);
  }) as typeof fetch;
  t.after(() => { globalThis.fetch = realFetch; });
  await h.send({ action: 'commerce_reconcile', lookback_hours: 9999 });
  assert.equal(seen, null);
});
