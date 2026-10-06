-- Fuxia 360 · pase C3 — Mario (2026-10-06): "ya ponlos y quita los viejos". Carolina's homologation (what OLD store product is which
-- F360 model / colour / size) was decided on staging4, a copy of the real store. Verified read-only on 2026-10-06 against
-- fuxiaballerinas.com: the 109 old products exist with the SAME ids and names, and the 672 confirmed variations exist under them.
-- So the confirmed rows are copied to the real channel (woo_production) unchanged; the staging4 rows stay as they are (history).
-- Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
INSERT INTO f360.legacy_woo_map (target_id, woo_variation_id, woo_product_id, woo_product_name, woo_parent_sku, woo_category, woo_size, woo_color,
  woo_regular_price, sold_all, sold_90d, snapshot_at, proposed_model, proposed_product_id, proposed_color, proposed_size, proposed_status, confidence,
  proposal_reason, proposed_at, status, human_locked, confirmed_variant_id, decided_by, decided_by_name, decided_at, note)
SELECT p.id, m.woo_variation_id, m.woo_product_id, m.woo_product_name, m.woo_parent_sku, m.woo_category, m.woo_size, m.woo_color,
  m.woo_regular_price, m.sold_all, m.sold_90d, m.snapshot_at, m.proposed_model, m.proposed_product_id, m.proposed_color, m.proposed_size, m.proposed_status, m.confidence,
  m.proposal_reason, m.proposed_at, m.status, m.human_locked, m.confirmed_variant_id, m.decided_by, m.decided_by_name, m.decided_at,
  trim(coalesce(m.note, '') || ' [re-anclado a woo_production 2026-10-06: verificado 1:1 contra fuxiaballerinas.com]')
FROM f360.legacy_woo_map m
JOIN f360.sales_targets s ON s.id = m.target_id AND s.key = 'woo_staging4'
CROSS JOIN f360.sales_targets p
WHERE p.key = 'woo_production' AND m.status = 'confirmado'
ON CONFLICT (target_id, woo_variation_id) DO NOTHING;
DO $$ BEGIN
  IF (SELECT count(*) FROM f360.legacy_woo_map m JOIN f360.sales_targets p ON p.id = m.target_id WHERE p.key = 'woo_production' AND m.status = 'confirmado') <> 672 THEN
    RAISE EXCEPTION 'Se esperaban 672 variaciones confirmadas en woo_production.';
  END IF;
END $$;
COMMIT;
