-- Rollback of 20261109000300: the guard looks at legacy links of every store again (blocks Woo publishing of Shopify-linked models).
CREATE OR REPLACE FUNCTION f360.sync_job_legacy_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF f360.is_consolidated(NEW.target_id, NEW.product_id) THEN RETURN NEW; END IF;   -- approved merge (20261007001900)
  IF EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE v.product_id = NEW.product_id)
     OR EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id
                WHERE vl.origin = 'legacy_adopted' AND v.product_id = NEW.product_id) THEN
    RAISE EXCEPTION 'Este modelo viene del catálogo Woo anterior: ya existe en la tienda y no se publica como producto nuevo.';
  END IF;
  RETURN NEW;
END $$;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261109000300';
