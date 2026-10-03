import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildContent, pushContent, type ContentSnap } from '../content.ts';
import type { WooAdapter } from '../types.ts';

const snap = (over: Partial<ContentSnap> = {}): ContentSnap => ({
  woo_product_id: 145, base_url: 'https://staging4.fuxiaballerinas.com',
  product: { id: 'p1', name: 'Botas Largas', description: 'Botas de piel', short_description: null, regular_price: 4200, sale_price: null },
  prices: [{ woo_meta_key: '_price_cop', amount: 1200000 }],
  colors: [{ id: 'c1', name: 'Café', media: [{ id: 'm1', path: 'f360/BL/CAFE/a.jpg', alt: null, woo_media_id: 77 }, { id: 'm2', path: 'f360/BL/CAFE/b.jpg', alt: null, woo_media_id: null }] }],
  variations: [314, 315], ...over,
});

test('one colour → name "Modelo Color"; linked photos by id, new ones by URL; price + currency meta', () => {
  const { parent, variation } = buildContent(snap(), 'https://x.supabase.co');
  assert.equal(parent.name, 'Botas Largas Café');
  assert.deepEqual((parent.images as any[])[0], { id: 77 });
  assert.match((parent.images as any[])[1].src, /product-images\/f360\/BL\/CAFE\/b\.jpg$/);
  assert.equal(parent.description, 'Botas de piel');
  assert.ok(!('short_description' in parent) && !('sku' in parent) && !('status' in parent) && !('slug' in parent) && !('stock_quantity' in parent));
  assert.deepEqual(variation, { regular_price: '4200', sale_price: '', meta_data: [{ key: '_price_cop', value: '1200000' }] });
});
test('no photos / no price in Fuxia 360 → the store keeps its own', () => {
  const { parent, variation } = buildContent(snap({ colors: [{ id: 'c1', name: 'Café', media: [] }], product: { ...snap().product, regular_price: null } }), 'x');
  assert.ok(!('images' in parent)); assert.equal(variation, null);
});
test('push records the new photo ids and the result', async () => {
  const calls: any[] = [];
  const rpc = (async (fn: string, args: any) => { calls.push({ fn, args }); return fn === 'f360_legacy_content_snapshot' ? snap() : null; }) as any;
  const woo = { updateProduct: async (_id: number, b: any) => ({ id: 145, images: b.images.map((i: any, k: number) => ({ id: i.id ?? 900 + k })) }),
    batchVariations: async (_p: number, i: any) => ({ update: i.update }) } as unknown as WooAdapter;
  const r = await pushContent(rpc, woo, 'woo_staging4', 145, 'https://x.supabase.co', 'Mario');
  assert.equal(r.ok, true);
  const res = calls.find((c) => c.fn === 'f360_legacy_content_result').args;
  assert.deepEqual(res.p_media, [{ media_id: 'm2', woo_media_id: 901 }]);
  assert.equal(res.p_by, 'Mario');
});
test('store error → recorded as failed, nothing thrown', async () => {
  const calls: any[] = [];
  const rpc = (async (fn: string, args: any) => { calls.push({ fn, args }); return fn === 'f360_legacy_content_snapshot' ? snap() : null; }) as any;
  const woo = { updateProduct: async () => { throw new Error('woocommerce_product_image_upload_error'); } } as unknown as WooAdapter;
  const r = await pushContent(rpc, woo, 'woo_staging4', 145, 'x', 'Mario');
  assert.equal(r.ok, false);
  assert.equal(calls.at(-1).args.p_ok, false);
});
