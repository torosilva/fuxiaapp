-- Rollback of 20261012000400: f360_pub_visibility_begin as in 20261012000300.
BEGIN;
CREATE OR REPLACE FUNCTION public.f360_pub_visibility_begin(p_product_id uuid, p_target_key text, p_status text, p_caller uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE t f360.sales_targets; l f360.woo_product_links;
BEGIN
  IF p_status NOT IN ('publish', 'draft') THEN RAISE EXCEPTION 'Estado no válido.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede mostrar u ocultar productos en la tienda.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  t := f360.catalog_target(p_target_key);
  SELECT * INTO l FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p_product_id;
  IF l.woo_product_id IS NULL THEN RAISE EXCEPTION 'Primero publícalo como borrador.'; END IF;
  RETURN jsonb_build_object('woo_product_id', l.woo_product_id, 'woo_status', l.woo_status, 'target', jsonb_build_object('key', t.key, 'base_url', t.base_url));
END $$;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261012000400';
COMMIT;
