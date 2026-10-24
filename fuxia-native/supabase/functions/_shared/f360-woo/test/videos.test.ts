// Videos (20261101000100): they travel as the product meta _fuxia360_videos, never as gallery images.
// Run: node --test fuxia-native/supabase/functions/_shared/f360-woo/test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { publish } from '../publisher.ts';
import { mockAdapter, mockStore } from '../mock.ts';
import { META_VIDEOS, metaValue } from '../mapping.ts';
import { FakeDb, macarena } from './fakedb.ts';

const OPTS = { storageBase: 'https://staging.example.supabase.co' };
const withVideos = (videos: Record<string, { id: string; path: string; mime: string }[]>) => {
  const b = macarena();
  b.colors = b.colors.map((c) => ({ ...c, videos: videos[c.code] ?? [] }));
  return b;
};
const productOf = (store: ReturnType<typeof mockStore>) => [...store.products.values()].find((p) => p.sku === 'F360-MACARENA')!;

test('first publish with a Nude video: meta carries URL + colour, gallery keeps only the 6 photos, verify passes', async () => {
  const db = new FakeDb(withVideos({ NUDE: [{ id: 'vd-1', path: 'f360/MACARENA/NUDE/clip-1.mp4', mime: 'video/mp4' }] }));
  const store = mockStore();
  const out = await publish(db.claim(), mockAdapter(store), db.recorder(), OPTS);
  assert.equal(out.status, 'succeeded', out.error ?? '');
  const p = productOf(store);
  assert.equal(p.images.length, 6, 'videos are not gallery images');
  assert.deepEqual(JSON.parse(String(metaValue(p.meta_data, META_VIDEOS))), [
    { url: 'https://staging.example.supabase.co/storage/v1/object/public/product-images/f360/MACARENA/NUDE/clip-1.mp4', mime: 'video/mp4', color: 'Nude' }]);
});

test('republish is stable, and removing the video clears the meta', async () => {
  const db = new FakeDb(withVideos({ NEGRO: [{ id: 'vd-2', path: 'f360/MACARENA/NEGRO/clip-2.mov', mime: 'video/quicktime' }] }));
  const store = mockStore();
  assert.equal((await publish(db.claim(), mockAdapter(store), db.recorder(), OPTS)).status, 'succeeded');
  assert.equal((await publish(db.claim(), mockAdapter(store), db.recorder(), OPTS)).status, 'succeeded');
  assert.equal(productOf(store).meta_data.filter((m) => m.key === META_VIDEOS).length, 1, 'one meta, not duplicated');
  db.base.colors = db.base.colors.map((c) => ({ ...c, videos: [] }));
  assert.equal((await publish(db.claim(), mockAdapter(store), db.recorder(), OPTS)).status, 'succeeded');
  assert.equal(metaValue(productOf(store).meta_data, META_VIDEOS), '[]');
});

test('an old snapshot (no videos field) never writes or checks the video meta', async () => {
  const db = new FakeDb(macarena());
  const store = mockStore();
  assert.equal((await publish(db.claim(), mockAdapter(store), db.recorder(), OPTS)).status, 'succeeded');
  assert.equal(metaValue(productOf(store).meta_data, META_VIDEOS), undefined);
});
