-- Fuxia 360 · pase C4 — go-live takes the old products out of the catalog (same as migration 20261012000400). Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · "Publicar en vivo" also takes the model's OLD store products out of the catalog (Mario 2026-10-06: "ya ponlos y
-- quita los viejos"). f360_pub_visibility_begin now also returns the old products of the model in that store (Carolina's
-- confirmed homologation for the same channel). The publisher sets them catalog_visibility = hidden on go-live (their URL keeps
-- working: no 404, Google and links still land) and back to visible when the new product is hidden again. Fully reversible.
-- Rollback: supabase/rollbacks/20261012000400_f360_go_live_hides_legacy.down.sql
CREATE OR REPLACE FUNCTION public.f360_pub_visibility_begin(p_product_id uuid, p_target_key text, p_status text, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; l f360.woo_product_links; legacy jsonb;
BEGIN
  IF p_status NOT IN ('publish', 'draft') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede mostrar u ocultar productos en la tienda.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  t := f360.catalog_target(p_target_key);
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  IF l.woo_product_id IS NULL THEN RAISE EXCEPTION 'Primero publícalo como borrador.'; END IF;
  SELECT coalesce(jsonb_agg(DISTINCT m.woo_product_id), '[]') INTO legacy
  FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id
  WHERE m.target_id = t.id AND m.status = 'confirmado' AND v.product_id = p_product_id AND m.woo_product_id <> l.woo_product_id;
  RETURN jsonb_build_object('woo_product_id', l.woo_product_id, 'woo_status', l.woo_status, 'legacy_woo_product_ids', legacy,
    'target', jsonb_build_object('key', t.key, 'base_url', t.base_url));
END $$;
REVOKE ALL ON FUNCTION public.f360_pub_visibility_begin(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_pub_visibility_begin(uuid, text, text, uuid) TO service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261012000400', 'f360_go_live_hides_legacy', '{}');
COMMIT;
