-- Fuxia 360 · pase E13 — product page: delivery promise per size + Carolina's materials/care (same as migration 20261020000100).
-- READ-ONLY function for the Edge Function f360-storefront (action pdp). woo_production stays INACTIVE (no stock sync, no reservations).
-- Apply ONLY with scripts/f360/prod_sql.sh, BEFORE scripts/f360/deploy_prod_function.sh f360-storefront.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production' AND is_production) THEN
    RAISE EXCEPTION 'ABORT: this pase is for PRODUCTION only (woo_production target missing)';
  END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261020000100') OR to_regprocedure('public.f360_storefront_pdp(text,bigint,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'ABORT: already applied';
  END IF;
END $$;
-- ════════ 20261020000100_f360_storefront_pdp.sql ════════
CREATE FUNCTION public.f360_storefront_pdp(p_target_key text, p_woo_product_id bigint, p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; pid uuid;
BEGIN
  SELECT * INTO t FROM f360.sales_targets WHERE key = p_target_key;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Canal no válido.'; END IF;
  SELECT canonical_product_id INTO pid FROM f360.channel_variant_identity WHERE sales_channel_id = t.id AND woo_product_id = p_woo_product_id LIMIT 1;
  RETURN jsonb_build_object('market', f360.market_key(p_market),
    'variations', coalesce((SELECT jsonb_object_agg(ci.woo_variation_id::text, f360.delivery_promise(ci.canonical_variant_id, t.fulfillment_location_id, p_market))
                            FROM f360.channel_variant_identity ci WHERE ci.sales_channel_id = t.id AND ci.woo_product_id = p_woo_product_id), '{}'),
    'knowledge', CASE WHEN pid IS NOT NULL THEN f360.product_knowledge_public(pid) END);
END $$;
REVOKE ALL ON FUNCTION public.f360_storefront_pdp(text, bigint, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_storefront_pdp(text, bigint, text) TO service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261020000100', 'f360_storefront_pdp', '{}');
COMMIT;
