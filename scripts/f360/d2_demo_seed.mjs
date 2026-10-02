// STAGING ONLY — Track D2 practice channel "demo_d2" for Carolina's walkthrough / e2e screenshots.
// Copies the snapshot + system proposal of a few Woo products from woo_staging4 into a separate channel, so practising
// never creates human decisions in the real woo_staging4 homologation. Idempotent. No inventory, no links, no Woo.
// Models created while practising must be named "Demo · …" (the real proposal ignores them).
// Run: scripts/s00a/run.sh ../f360/d2_demo_seed.mjs
import { loadEnv, psql } from '../s00a/lib.mjs';

loadEnv();
const NAMES = ['Cucarron nude', 'Cucarron negro', 'Cucarron vino', 'Mules Colectiva', 'Croc', 'Sandalia flor CH'];
console.log(psql(`
INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active)
  SELECT 'demo_d2', 'Demo · homologación (práctica, copia de staging4)', 'https://demo-d2.invalid', fulfillment_location_id, true
  FROM f360.sales_targets WHERE key = 'woo_staging4'
  ON CONFLICT (key) DO NOTHING;
INSERT INTO f360.legacy_woo_map (target_id, woo_variation_id, woo_product_id, woo_product_name, woo_parent_sku, woo_category, woo_size, woo_color,
    woo_regular_price, sold_all, sold_90d, snapshot_at, proposed_model, proposed_product_id, proposed_color, proposed_size, proposed_status,
    confidence, proposal_reason, proposed_at, status)
  SELECT (SELECT id FROM f360.sales_targets WHERE key = 'demo_d2'), m.woo_variation_id, m.woo_product_id, m.woo_product_name, m.woo_parent_sku,
    m.woo_category, m.woo_size, m.woo_color, m.woo_regular_price, m.sold_all, m.sold_90d, m.snapshot_at, m.proposed_model, NULL, m.proposed_color,
    m.proposed_size, m.proposed_status, m.confidence, m.proposal_reason, m.proposed_at, m.proposed_status
  FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id AND t.key = 'woo_staging4'
  WHERE m.woo_product_name IN (${NAMES.map((n) => `'${n}'`).join(', ')})
  ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
SELECT f360.legacy_refresh_status((SELECT id FROM f360.sales_targets WHERE key = 'demo_d2'));
SELECT f360.legacy_summary((SELECT id FROM f360.sales_targets WHERE key = 'demo_d2'))::text;`).split('\n').pop());
