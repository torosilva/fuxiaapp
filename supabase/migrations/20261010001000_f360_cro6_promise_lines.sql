-- Fuxia 360 · CRO-6 — promise for cart / order LINES (checkout + "Pedido recibido") from the SAME rule. STAGING.
-- Mario 2026-10-05: checkout and the thank-you page must consume f360.delivery_promise, not their own texts.
-- Lines are identified by their Woo variation id (channel id) → f360.channel_variant_identity → f360.delivery_promise.
-- Rollback: supabase/rollbacks/20261010001000_f360_cro6_promise_lines.down.sql
CREATE FUNCTION public.f360_storefront_promise_lines(p_target_key text, p_woo_variation_ids bigint[], p_market text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets := f360.storefront_target(p_target_key);
BEGIN
  IF p_woo_variation_ids IS NULL OR cardinality(p_woo_variation_ids) > 50 THEN RAISE EXCEPTION 'Líneas no válidas.'; END IF;
  RETURN jsonb_build_object('market', f360.market_key(p_market),
    'lines', coalesce((SELECT jsonb_object_agg(x.id::text, f360.delivery_promise(ci.canonical_variant_id, t.fulfillment_location_id, p_market))
                       FROM unnest(p_woo_variation_ids) x(id)
                       LEFT JOIN f360.channel_variant_identity ci ON ci.sales_channel_id = t.id AND ci.woo_variation_id = x.id), '{}'));
END $$;
REVOKE ALL ON FUNCTION public.f360_storefront_promise_lines(text, bigint[], text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_storefront_promise_lines(text, bigint[], text) TO service_role;
