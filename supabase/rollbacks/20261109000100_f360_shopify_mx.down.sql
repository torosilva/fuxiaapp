-- Rollback of 20261109000100_f360_shopify_mx. Pause the Shopify webhooks first (f360-shopify). Shopify orders already
-- recorded stay as facts (their target row is kept: commerce/woo order tables reference it).
DROP FUNCTION IF EXISTS f360.shopify_link_variants(text, text);
DROP FUNCTION IF EXISTS f360.shopify_norm(text);
DROP FUNCTION IF EXISTS public.f360_shopify_localize(text, jsonb);
DROP TABLE IF EXISTS f360.shopify_variants;
DROP TABLE IF EXISTS f360.shopify_products;
DELETE FROM f360.woo_variant_links l USING f360.sales_targets t WHERE t.id = l.target_id AND t.kind = 'shopify';
UPDATE f360.sales_targets SET orders_mode = 'off', active = false WHERE kind = 'shopify';
CREATE OR REPLACE FUNCTION f360.commerce_payment_category(p_method text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN coalesce(p_method, '') = '' THEN 'unknown'
              WHEN p_method LIKE 'woo-mercado-pago%' OR p_method IN ('epayco', 'ppcp-card-button-gateway', 'stripe', 'ppcp-credit-card-gateway') THEN 'card'
              WHEN p_method LIKE 'ppcp%' OR p_method LIKE 'paypal%' THEN 'paypal'
              WHEN p_method = 'bacs' THEN 'transfer'
              WHEN p_method = 'cod' THEN 'cash'
              WHEN p_method LIKE '%prueba%' OR p_method LIKE '%test%' THEN 'test'
              ELSE 'other' END $$;
-- kind check stays widened while a Shopify target row exists (orders reference it).
-- Link guard back to 20261007001900 (after the Shopify links are deleted above).
CREATE OR REPLACE FUNCTION f360.woo_variant_link_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.origin = 'legacy_adopted' AND NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map m
       WHERE m.target_id = NEW.target_id AND m.woo_variation_id = NEW.woo_variation_id AND m.woo_product_id = NEW.woo_product_id
         AND m.status = 'confirmado' AND m.confirmed_variant_id = NEW.variant_id) THEN
    RAISE EXCEPTION 'Un vínculo legacy solo se crea desde una homologación confirmada por una persona (variación Woo %).', NEW.woo_variation_id;
  END IF;
  IF NEW.origin = 'legacy_adopted' AND f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Este modelo ya se unió en un solo producto de la tienda: ya no se liga a los productos anteriores.';
  END IF;
  IF NEW.origin = 'f360_published' AND EXISTS (SELECT 1 FROM f360.legacy_woo_map m WHERE m.confirmed_variant_id = NEW.variant_id)
     AND NOT f360.is_consolidated(NEW.target_id, (SELECT product_id FROM f360.product_variants WHERE id = NEW.variant_id)) THEN
    RAISE EXCEPTION 'Esta variante viene del catálogo Woo anterior: no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;
