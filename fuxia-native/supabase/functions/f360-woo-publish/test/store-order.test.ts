// "Aplicar orden a la tienda": the shop order decided in Fuxia 360 → Woo menu_order. Run: node --test fuxia-native/supabase/functions/f360-woo-publish/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../handler.ts';
import type { WooAdapter } from '../../_shared/f360-woo/types.ts';

const env = { SUPABASE_URL: 'https://p.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_production',
  WOO_BASE_URL: 'https://fuxiaballerinas.com', WOO_USER: 'ck_x', WOO_SECRET: 'cs_x', STORAGE_PUBLIC_BASE: '' } as const;

function setup(opts: { role?: string; items?: number; targetKey?: string; failId?: number; batch?: boolean } = {}) {
  const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const items = Array.from({ length: opts.items ?? 3 }, (_, i) => ({ woo_product_id: 1000 + i, position: i + 1 }));
  const menu: Record<number, number> = {}; const calls: number[] = [];
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    const u = String(url);
    if (u.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: 'user-1' }));
    const fn = u.split('/rpc/')[1];
    const args = init?.body ? JSON.parse(String(init.body)) : {};
    rpcs.push({ fn, args });
    if (fn === 'f360_me') return new Response(JSON.stringify({ role: opts.role ?? 'owner' }));
    if (fn === 'f360_pub_order_begin') return new Response(JSON.stringify({ target: { key: opts.targetKey ?? 'woo_production', base_url: 'https://fuxiaballerinas.com' }, items }));
    if (fn === 'f360_pub_order_finish') return new Response(JSON.stringify({ ok: args.p_ok, items: args.p_items }));
    return new Response('{}', { status: 404 });
  }) as typeof fetch;
  const adapter: Partial<WooAdapter> = {
    updateProduct: async (id: number, b: Record<string, unknown>) => { if (id === opts.failId) throw new Error('boom'); menu[id] = Number(b.menu_order); return { id } as never; },
  };
  if (opts.batch !== false) adapter.batchProducts = async (update) => {
    calls.push(update.length);
    return { update: update.map((x) => { if (x.id === opts.failId) return { id: x.id, error: { code: 'x', message: 'no' } }; menu[x.id] = Number(x.menu_order); return { id: x.id }; }) };
  };
  return { rpcs, menu, calls, opts: { wrapAdapter: () => adapter as WooAdapter, storeHome: async () => 'https://fuxiaballerinas.com' } };
}
const req = (body: unknown) => new Request('https://f/x', { method: 'POST', headers: { Authorization: 'Bearer t', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('owner → every store product gets its position as menu_order; audited', async () => {
  const { rpcs, menu, opts } = setup();
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true, done: 3 });
  assert.deepEqual(menu, { 1000: 1, 1001: 2, 1002: 3 });
  const begin = rpcs.find((x) => x.fn === 'f360_pub_order_begin')!;
  assert.equal(begin.args.p_caller, 'user-1'); assert.equal(begin.args.p_target_key, 'woo_production');
  const fin = rpcs.find((x) => x.fn === 'f360_pub_order_finish')!;
  assert.equal(fin.args.p_ok, true); assert.equal(fin.args.p_items, 3);
});
test('230 products → Woo batches of at most 100', async () => {
  const { calls, menu, opts } = setup({ items: 230 });
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 200);
  assert.deepEqual(calls, [100, 100, 30]);
  assert.equal(Object.keys(menu).length, 230);
});
test('a product the store refuses → reported and audited as not ok; the rest still ordered', async () => {
  const { rpcs, menu, opts } = setup({ failId: 1001 });
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 502);
  const b = await r.json() as { done: number; failed: number[] };
  assert.equal(b.done, 2); assert.deepEqual(b.failed, [1001]);
  assert.deepEqual(menu, { 1000: 1, 1002: 3 });
  assert.equal(rpcs.find((x) => x.fn === 'f360_pub_order_finish')!.args.p_ok, false);
});
test('adapter without batch → one update per product', async () => {
  const { menu, opts } = setup({ batch: false });
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 200);
  assert.deepEqual(menu, { 1000: 1, 1001: 2, 1002: 3 });
});
test('not an owner → 403, nothing touched', async () => {
  const { rpcs, menu, opts } = setup({ role: 'operator' });
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 403);
  assert.deepEqual(menu, {});
  assert.ok(!rpcs.some((x) => x.fn === 'f360_pub_order_begin'));
});
test('plan for another store → 409, nothing touched', async () => {
  const { menu, opts } = setup({ targetKey: 'woo_staging4' });
  const r = await handle(req({ action: 'store_order' }), env, opts);
  assert.equal(r.status, 409);
  assert.deepEqual(menu, {});
});
test('the store answering as ANOTHER site → 502, nothing touched', async () => {
  const { menu, opts } = setup();
  const r = await handle(req({ action: 'store_order' }), env, { ...opts, storeHome: async () => 'https://staging4.fuxiaballerinas.com' });
  assert.equal(r.status, 502);
  assert.deepEqual(menu, {});
});
