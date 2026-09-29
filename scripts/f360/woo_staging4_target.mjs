// STAGING ONLY: registers the real WooCommerce STAGING store (staging4, SiteGround; DW2) as the active sales target
// "woo_staging4" and links the 4 F360 categories to that store's category IDs (looked up by slug ONCE, read-only).
// The local Docker target "woo_local" is DEACTIVATED (kept, with its links; reactivable) so only one test store is
// active. Refuses production hosts. Never prints credentials.
// Run: scripts/s00a/run.sh ../f360/woo_staging4_target.mjs
import { readFileSync } from 'node:fs';
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const E = Object.fromEntries(readFileSync('tools/siteground-staging.env', 'utf8').split('\n').filter((l) => /^[A-Z0-9_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]));
const url = new URL(E.WOO_BASE_URL);
const prod = (E.PRODUCTION_WOO_HOSTS ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean);
if (url.protocol !== 'https:' || !prod.length || prod.includes(url.hostname) || url.hostname !== 'staging4.fuxiaballerinas.com' || url.hostname !== E.STAGING_WOO_HOST) {
  throw new Error('ABORT: not the approved staging store');
}
const base = `${url.origin}`;
const auth = 'Basic ' + Buffer.from(`${E.WOO_USER}:${E.WOO_SECRET}`).toString('base64');
const r = await fetch(`${base}/wp-json/wc/v3/products/categories?per_page=100`, { headers: { Authorization: auth } });
if (!r.ok) throw new Error(`categories: HTTP ${r.status}`);
const cats = await r.json();
const rows = ['ballerinas', 'sandalia-plana', 'sandalia-alta', 'botas'].map((slug) => {
  const c = cats.find((x) => x.slug === slug);
  if (!c) throw new Error(`staging4 has no category ${slug}`);
  return `('${slug}', ${Number(c.id)}, '${slug}')`;
});
psql(`
BEGIN;
UPDATE f360.sales_targets SET active = false WHERE key = 'woo_local';
INSERT INTO f360.sales_targets (key, name, base_url, is_production, fulfillment_location_id, active)
  SELECT 'woo_staging4', 'Tienda en línea de pruebas (staging4)', '${base}', false, id, true FROM f360.locations WHERE name = 'Bodega CDMX'
  ON CONFLICT (key) DO UPDATE SET base_url = EXCLUDED.base_url, active = true, is_production = false;
INSERT INTO f360.woo_category_links (target_id, category_key, woo_term_id, woo_slug, verified_at)
  SELECT t.id, v.key, v.term, v.slug, now() FROM f360.sales_targets t, (VALUES ${rows.join(', ')}) v(key, term, slug) WHERE t.key = 'woo_staging4'
  ON CONFLICT (target_id, category_key) DO UPDATE SET woo_term_id = EXCLUDED.woo_term_id, woo_slug = EXCLUDED.woo_slug, verified_at = now();
COMMIT;`);
console.log(psql(`select json_build_object(
  'targets', (select json_agg(json_build_object('key', key, 'base_url', base_url, 'active', active, 'is_production', is_production) order by key) from f360.sales_targets),
  'staging4_categories', (select json_object_agg(c.category_key, c.woo_term_id) from f360.woo_category_links c join f360.sales_targets t on t.id = c.target_id where t.key = 'woo_staging4'),
  'online_location', (f360.online_location()).name);`, {}, { readOnly: true }).trim());
