-- Fuxia 360 · product page on phones (Mario 2026-10-09: "lo quiero igualito que la propuesta" + "sí instala lo de entrega inmediata").
-- One READ-ONLY call for the store's product page: the delivery promise of every size (the existing rule: f360.delivery_promise →
-- f360.online_ats = Bodega + selling stores − Gold holds; texts from f360.delivery_promise_rules) and Carolina's VALIDATED product
-- knowledge (materials, care, fit — f360.product_knowledge_public).
-- Unlike f360_storefront_promise it does NOT require the channel to be active: woo_production stays inactive (stock sync, reservations
-- and make-to-order pushes stay off) — this only READS. Additive; service_role only (called by the Edge Function f360-storefront).
-- Rollback: supabase/rollbacks/20261020000100_f360_storefront_pdp.down.sql
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
