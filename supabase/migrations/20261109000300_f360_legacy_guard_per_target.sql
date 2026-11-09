-- Fuxia 360 · the publish guard looks only at links of the store being published to (Mario 2026-11-09: "Subir a la tienda"
-- on Mini Paula failed with "Este modelo viene del catálogo Woo anterior…").
-- Cause: 20261109000100 links every Shopify México size with origin 'legacy_adopted'. f360.sync_job_legacy_guard looked for
-- ANY 'legacy_adopted' link of the product, of any store, so after the Shopify link (1,278 sizes, all 79 models) no model
-- could be published to the Woo store any more. Before Shopify there was only one production store, so filtering the link
-- check by the job's own store keeps the old behaviour exactly; the legacy_woo_map check is unchanged.
-- Rollback: supabase/rollbacks/20261109000300_f360_legacy_guard_per_target.down.sql
CREATE OR REPLACE FUNCTION f360.sync_job_legacy_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF f360.is_consolidated(NEW.target_id, NEW.product_id) THEN RETURN NEW; END IF;   -- approved merge (20261007001900)
  IF EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE v.product_id = NEW.product_id)
     OR EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                WHERE vl.target_id = NEW.target_id AND vl.origin = 'legacy_adopted' AND v.product_id = NEW.product_id) THEN
    RAISE EXCEPTION 'Este modelo viene del catálogo Woo anterior: ya existe en la tienda y no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;
