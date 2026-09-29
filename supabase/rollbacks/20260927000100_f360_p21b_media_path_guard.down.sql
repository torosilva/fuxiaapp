-- Rollback of P2.1b: restores the P2.1 f360_add_media and drops the unique index. STAGING/approved targets only.
BEGIN;
DROP INDEX IF EXISTS f360.product_media_storage_path_key;
CREATE OR REPLACE FUNCTION public.f360_add_media(p_product_id uuid, p_color_id uuid, p_paths text[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_path text; v_sort int;
BEGIN
  r := f360.require_role('operator');
  IF NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE id = p_color_id AND product_id = p_product_id) THEN
    RAISE EXCEPTION 'Color no encontrado.';
  END IF;
  IF p_paths IS NULL OR cardinality(p_paths) = 0 THEN RAISE EXCEPTION 'No hay fotos.'; END IF;
  SELECT coalesce(max(sort), 0) INTO v_sort FROM f360.product_media WHERE color_id = p_color_id;
  FOREACH v_path IN ARRAY p_paths LOOP
    IF v_path !~ '^f360/[A-Za-z0-9._/-]+$' THEN RAISE EXCEPTION 'Ruta de foto no válida.'; END IF;
    v_sort := v_sort + 1;
    INSERT INTO f360.product_media (product_id, color_id, storage_path, sort, created_by) VALUES (p_product_id, p_color_id, v_path, v_sort, auth.uid());
  END LOOP;
  UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  RETURN public.f360_get_product(p_product_id);
END $$;

COMMIT;
