// P0D · f360-woo-sync action commerce_history: who may ask, simulation by default, Woo only read, one capture path.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handleSync } from '../../../f360-woo-sync/handler.ts';
import type { CommerceWoo } from '../commerce.ts';

const env = { SUPABASE_URL: 'http://sb', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_production',
  WOO_BASE_URL: 'http://woo', WOO_USER: 'u', WOO_SECRET: 's', F360_SYNC_SECRET: 'cron-secret' };
const order = (id: number) => ({ id, status: 'completed', currency: 'MXN', total: '2800.00', date_created_gmt: '2026-08-01T10:00:00',
  date_modified_gmt: '2026-08-01T10:00:00', line_items: [], refunds: [], billing: { country: 'MX' } });
function harness(role: string, ordersMode: string | null = 'on') {
  const calls: string[] = []; const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
    const u = String(url); const fn = u.split('/rpc/')[1];
    if (u.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: 'uid' }));
    if (fn === 'f360_me') return new Response(JSON.stringify({ role, display_name: 'X' }));
    if (fn === 'f360_channel_mode') return new Response(JSON.stringify({ stock_sync_mode: 'off', orders_mode: ordersMode }));
    if (fn) rpcs.push({ fn, args: JSON.parse(String(init?.body ?? '{}')) });
    if (fn === 'f360_commerce_reconcile_diff') return new Response(JSON.stringify({ current: 0, missing: [], outdated: [], before_cutover_missing: [2082, 3151], orders_since_id: 5351 }));
    if (fn === 'f360_commerce_run_begin') return new Response('{"run_id":9}');
    if (fn === 'f360_capture_order_economics') return new Response('{"result":"inserted"}');
    if (fn === 'f360_commerce_run_end') return new Response('null');
    return new Response('{}', { status: 500 });
  }) as typeof fetch;
  const woo: CommerceWoo = {
    listOrders: async () => { calls.push('woo listOrders'); return []; }, listRefunds: async () => [],
    listOrderStubsCreated: async (_after, page) => { calls.push(`woo GET stubs ${page}`); return page === 1 ? [2082, 3151, 5400].map((id) => ({ id, date_modified_gmt: '2026-08-01T10:00:00' })) : []; },
    getOrder: async (id) => { calls.push(`woo GET order ${id}`); return order(id); },
  };
  return { calls, rpcs, woo, restore: () => { globalThis.fetch = realFetch; } };
}
const req = (token: string, body: unknown) => new Request('http://x', { method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) });

test('commerce_history simulates by default: Woo listed only, nothing captured, no run opened', async () => {
  const h = harness('owner');
  try {
    const res = await handleSync(req('user-jwt', { action: 'commerce_history' }), env, { commerceWoo: h.woo });
    const j = await res.json() as { ok: boolean; stats: { dry_run: boolean; detected_missing: number; after_cutover_skipped: number; imported: number } };
    assert.equal(res.status, 200); assert.equal(j.ok, true);
    assert.equal(j.stats.dry_run, true); assert.equal(j.stats.detected_missing, 2); assert.equal(j.stats.after_cutover_skipped, 1); assert.equal(j.stats.imported, 0);
    assert.deepEqual(h.calls, ['woo GET stubs 1']);
    assert.deepEqual(h.rpcs.map((r) => r.fn), ['f360_commerce_reconcile_diff']);
  } finally { h.restore(); }
});

test('commerce_history apply: only pre-cutover orders, through the one capture path as backfill', async () => {
  const h = harness('system');
  try {
    const res = await handleSync(req('cron-secret', { action: 'commerce_history', apply: true, months: 5 }), env, { commerceWoo: h.woo });
    const j = await res.json() as { ok: boolean; stats: { imported: number } };
    assert.equal(res.status, 200); assert.equal(j.ok, true); assert.equal(j.stats.imported, 2);
    assert.ok(!h.calls.includes('woo GET order 5400'));
    const caps = h.rpcs.filter((r) => r.fn === 'f360_capture_order_economics');
    assert.deepEqual(caps.map((c) => c.args.p_via), ['backfill', 'backfill']);
    assert.ok(caps.every((c) => c.args.p_target_key === 'woo_production'));
    assert.deepEqual(h.rpcs.map((r) => r.fn).filter((f) => f.startsWith('f360_commerce_run')), ['f360_commerce_run_begin', 'f360_commerce_run_end']);
  } finally { h.restore(); }
});

test('commerce_history: operators and sellers are refused before Woo is read; orders off = skipped', async () => {
  for (const role of ['operator', 'seller']) {
    const h = harness(role);
    try {
      const res = await handleSync(req('user-jwt', { action: 'commerce_history', apply: true }), env, { commerceWoo: h.woo });
      assert.ok(res.status === 403, role); assert.equal(h.calls.length, 0); assert.equal(h.rpcs.filter((r) => r.fn !== 'f360_channel_mode').length, 0);
    } finally { h.restore(); }
  }
  const h = harness('owner', 'off');
  try {
    const res = await handleSync(req('user-jwt', { action: 'commerce_history', apply: true }), env, { commerceWoo: h.woo });
    assert.ok('skipped' in (await res.json() as object)); assert.equal(h.calls.length, 0);
  } finally { h.restore(); }
});
