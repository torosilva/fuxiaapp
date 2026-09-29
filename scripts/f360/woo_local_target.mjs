// STAGING ONLY: registers the throwaway local Docker Woo as the sales target "woo_local" and links the 4 F360
// categories to that store's category IDs (looked up by slug ONCE here; the publisher then uses only the ID).
// Also clears this target's Woo links (the local store is recreated between demos, so old ids are meaningless).
// Run: scripts/s00a/run.sh ../f360/woo_local_target.mjs      (lib refuses any production target)
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const woo = Object.fromEntries(readFileSync('tools/woo-docker/.env.local', 'utf8').split('\n').filter((l) => l.includes('=')).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
if (!/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(woo.WOO_BASE_URL)) throw new Error('ABORT: not the local Docker store');
const auth = 'Basic ' + Buffer.from(`${woo.WOO_USER}:${woo.WOO_SECRET}`).toString('base64');
const cats = await (await fetch(`${woo.WOO_BASE_URL}/wp-json/wc/v3/products/categories?per_page=100`, { headers: { Authorization: auth } })).json();
const want = { ballerinas: 'ballerinas', 'sandalia-plana': 'sandalia-plana', 'sandalia-alta': 'sandalia-alta', botas: 'botas' };
const rows = Object.entries(want).map(([key, slug]) => {
  const c = cats.find((x) => x.slug === slug);
  if (!c) throw new Error(`local store has no category ${slug}`);
  return `('${key}', ${Number(c.id)}, '${slug}')`;
});
psql(`
BEGIN;
INSERT INTO f360.sales_targets (key, name, base_url, is_production, fulfillment_location_id, active)
  SELECT 'woo_local', 'Tienda local de pruebas', '${woo.WOO_BASE_URL}', false, id, true FROM f360.locations WHERE name = 'Bodega CDMX'
  ON CONFLICT (key) DO UPDATE SET base_url = EXCLUDED.base_url, active = true, is_production = false;
DELETE FROM f360.woo_media_links WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_local');
DELETE FROM f360.woo_variant_links WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_local');
DELETE FROM f360.woo_product_links WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_local');
DELETE FROM f360.woo_category_links WHERE target_id = (SELECT id FROM f360.sales_targets WHERE key = 'woo_local');
INSERT INTO f360.woo_category_links (target_id, category_key, woo_term_id, woo_slug, verified_at)
  SELECT t.id, v.key, v.term, v.slug, now() FROM f360.sales_targets t, (VALUES ${rows.join(', ')}) v(key, term, slug) WHERE t.key = 'woo_local';
COMMIT;`);
console.log(psql(`select json_build_object('target', (select key || ' → ' || base_url || ' (bodega: ' || l.name || ')' from f360.sales_targets t join f360.locations l on l.id = t.fulfillment_location_id where key = 'woo_local'),
  'categories', (select json_object_agg(category_key, woo_term_id) from f360.woo_category_links));`, {}, { readOnly: true }));
