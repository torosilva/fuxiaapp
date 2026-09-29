-- Fuxia 360 Admin V1 — STAGING ONLY demo reset: removes demo products and their inventory history so the
-- milestone can be demonstrated again from a clean start. Keeps locations and roles.
-- The append-only guard is lifted ONLY inside this transaction, ONLY on staging (run via scripts/f360/demo_reset.mjs,
-- which refuses any non-staging target). Never run against production.
-- P2.1: also clears product_media rows (uploaded demo files under product-images/f360/ stay in staging storage).
BEGIN;
ALTER TABLE f360.inventory_events DISABLE TRIGGER inventory_events_append_only;
-- P2.2: publishing audit + links for the demo products (append-only guard lifted only inside this transaction)
ALTER TABLE f360.sync_job_steps DISABLE TRIGGER sync_job_steps_append_only;
DELETE FROM f360.sync_job_steps;
DELETE FROM f360.sync_jobs;
DELETE FROM f360.woo_media_links;
DELETE FROM f360.woo_variant_links;
DELETE FROM f360.woo_product_links;
ALTER TABLE f360.sync_job_steps ENABLE TRIGGER sync_job_steps_append_only;
ALTER TABLE f360.inventory_movements DISABLE TRIGGER inventory_movements_append_only;
DELETE FROM f360.inventory_balances;
DELETE FROM f360.inventory_movements;
DELETE FROM f360.inventory_events;
DELETE FROM f360.product_media;
DELETE FROM f360.product_variants;
DELETE FROM f360.product_sizes;
DELETE FROM f360.product_colors;
DELETE FROM f360.products;
ALTER TABLE f360.inventory_events ENABLE TRIGGER inventory_events_append_only;
ALTER TABLE f360.inventory_movements ENABLE TRIGGER inventory_movements_append_only;
COMMIT;
