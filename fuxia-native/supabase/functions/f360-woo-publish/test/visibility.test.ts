// "Publicar en vivo" / "Ocultar de la tienda" through the publisher. Run: node --test fuxia-native/supabase/functions/f360-woo-publish/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { handle } from '../handler.ts';
import type { WooAdapter } from '../../_shared/f360-woo/types.ts';

const env = { SUPABASE_URL: 'https://p.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'svc', WOO_TARGET_KEY: 'woo_production',
  WOO_BASE_URL: 'https://fuxiaballerinas.com', WOO_USER: 'ck_x', WOO_SECRET: 'cs_x', STORAGE_PUBLIC_BASE: '' } as const;
const PID = '11111111-2222-3333-4444-555555555555';

function setup(role = 'owner') {
  const rpcs: { fn: string; args: Record<string, unknown> }[] = [];
  const store = { status: 'draft', updates: 0, legacy: {} as Record<number, string>, redirect: {} as Record<number, string> };
  globalThis.fetch = (async (url: string, init?: RequestInit) => {
    const u = String(url);
    if (u.endsWith('/auth/v1/user')) return new Response(JSON.stringify({ id: 'user-1' }));
    const fn = u.split('/rpc/')[1];
    const args = init?.body ? JSON.parse(String(init.body)) : {};
    rpcs.push({ fn, args });
    if (fn === 'f360_me') return new Response(JSON.stringify({ role }));
    if (fn === 'f360_pub_visibility_begin') return new Response(JSON.stringify({ woo_product_id: 3674, woo_status: 'draft', legacy_woo_product_ids: [145, 146], target: { key: 'woo_production', base_url: 'https://fuxiaballerinas.com' } }));
    if (fn === 'f360_pub_visibility_finish') return new Response(JSON.stringify({ ok: args.p_ok, woo_status: args.p_woo_status }));
    return new Response('{}', { status: 404 });
  }) as typeof fetch;
  const adapter = {
    updateProduct: async (id: number, b: Record<string, unknown>) => { store.updates++; if (id === 3674) store.status = String(b.status); else { store.legacy[id] = String(b.catalog_visibility); store.redirect[id] = String((b.meta_data as { value: string }[])[0].value); } return { id, status: store.status } },
    getProduct: async () => ({ id: 3674, status: store.status }),
  } as unknown as WooAdapter;
  return { rpcs, store, opts: { wrapAdapter: () => adapter, storeHome: async () => 'https://fuxiaballerinas.com' } };
}
const req = (body: unknown) => new Request('https://f/x', { method: 'POST', headers: { Authorization: 'Bearer t', 'Content-Type': 'application/json' }, body: JSON.stringify(body) });

test('owner → live: the store product becomes publish, read back, audited', async () => {
  const { rpcs, store, opts } = setup();
  const r = await handle(req({ action: 'visibility', product_id: PID, status: 'publish' }), env, opts);
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { ok: true, woo_status: 'publish', legacy_changed: 2, legacy_failed: [] });
  assert.equal(store.status, 'publish');
  assert.deepEqual(store.legacy, { 145: 'hidden', 146: 'hidden' }, 'old products leave the catalog (URL still works)');
  assert.deepEqual(store.redirect, { 145: '3674', 146: '3674' }, 'old URLs point to the new product');
  const fin = rpcs.find((x) => x.fn === 'f360_pub_visibility_finish')!;
  assert.equal(fin.args.p_ok, true); assert.equal(fin.args.p_caller, 'user-1'); assert.equal(fin.args.p_target_key, 'woo_production');
});
test('the store answering as ANOTHER site → nothing is changed', async () => {
  const { store, opts } = setup();
  const r = await handle(req({ action: 'visibility', product_id: PID, status: 'publish' }), env, { ...opts, storeHome: async () => 'https://staging4.fuxiaballerinas.com' });
  assert.equal(r.status, 502);
  assert.equal(store.updates, 0);
});
test('a non-owner cannot change visibility (refused before the store is touched)', async () => {
  const { store, opts } = setup('operator');
  const r = await handle(req({ action: 'visibility', product_id: PID, status: 'publish' }), env, opts);
  assert.equal(r.status, 403);
  assert.equal(store.updates, 0);
});
test('only publish / draft are accepted', async () => {
  const { opts } = setup();
  const r = await handle(req({ action: 'visibility', product_id: PID, status: 'trash' }), env, opts);
  assert.equal(r.status, 400);
});

test('hide again → the new product back to draft and the old products back in the catalog', async () => {
  const { store, opts } = setup();
  const r = await handle(req({ action: 'visibility', product_id: PID, status: 'draft' }), env, opts);
  assert.equal(r.status, 200);
  assert.equal(store.status, 'draft');
  assert.deepEqual(store.legacy, { 145: 'visible', 146: 'visible' });
  assert.deepEqual(store.redirect, { 145: '', 146: '' }, 'redirect removed');
});
