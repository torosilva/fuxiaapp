-- Rollback of P2.2 (WooCommerce publishing infrastructure). Drops ONLY P2.2 objects; the ledger and P2.1 are untouched.
-- NOTE: products.codes_locked_at values set by publishing are intentionally KEPT (codes that reached Woo stay frozen).
-- STAGING / approved targets only.
BEGIN;
DROP FUNCTION IF EXISTS public.f360_pub_finish(uuid, text, text, jsonb);
DROP FUNCTION IF EXISTS public.f360_pub_link(uuid, text, uuid, integer, jsonb);
DROP FUNCTION IF EXISTS public.f360_pub_step(uuid, text, text, text, integer, boolean, text, jsonb);
DROP FUNCTION IF EXISTS public.f360_pub_claim(uuid, uuid);
DROP FUNCTION IF EXISTS public.f360_publication_status(uuid, text);
DROP FUNCTION IF EXISTS public.f360_request_publish(uuid, uuid, text);
DROP FUNCTION IF EXISTS f360.running_job(uuid);
DROP FUNCTION IF EXISTS f360.job_json(uuid, boolean);
DROP FUNCTION IF EXISTS f360.expire_stale_jobs(uuid);
DROP FUNCTION IF EXISTS f360.resolve_target(text);
DROP FUNCTION IF EXISTS f360.online_ats(uuid, uuid);
DROP FUNCTION IF EXISTS f360.publish_hash(uuid);
DROP TABLE IF EXISTS f360.sync_job_steps;
DROP FUNCTION IF EXISTS f360.reject_audit_change();
DROP TABLE IF EXISTS f360.sync_jobs;
DROP TABLE IF EXISTS f360.woo_media_links;
DROP TABLE IF EXISTS f360.woo_variant_links;
DROP TABLE IF EXISTS f360.woo_product_links;
DROP TABLE IF EXISTS f360.woo_category_links;
DROP TABLE IF EXISTS f360.sales_targets;
COMMIT;
