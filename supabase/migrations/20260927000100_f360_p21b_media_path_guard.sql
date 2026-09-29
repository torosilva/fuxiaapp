-- Fuxia 360 P2.1b — tighten f360_add_media (approved with P2.1, 2026-09-24).
-- An operator may only attach a photo that:
--   1. lives inside THIS product's and THIS color's folder: f360/{PRODUCT_CODE}/{COLOR_CODE}/{file}
--      (codes are immutable once published, so the folder is stable);
--   2. is a single safe file name (no sub-folders, no "..");
--   3. actually exists in storage bucket product-images (was really uploaded);
--   4. is not already attached to any product (no sharing another product's photo).
-- Additive: same signature, same grants; adds a unique index on product_media.storage_path.
-- Rollback: supabase/rollbacks/20260927000100_f360_p21b_media_path_guard.down.sql

CREATE UNIQUE INDEX product_media_storage_path_key ON f360.product_media (storage_path);

CREATE OR REPLACE FUNCTION public.f360_add_media(p_product_id uuid, p_color_id uuid, p_paths text[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_path text; v_sort int; v_prefix text; v_file text;
BEGIN
  r := f360.require_role('operator');
  SELECT 'f360/' || p.code || '/' || c.code || '/' INTO v_prefix
    FROM f360.product_colors c JOIN f360.products p ON p.id = c.product_id
    WHERE c.id = p_color_id AND c.product_id = p_product_id;
  IF v_prefix IS NULL THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  IF p_paths IS NULL OR cardinality(p_paths) = 0 THEN RAISE EXCEPTION 'No hay fotos.'; END IF;
  SELECT coalesce(max(sort), 0) INTO v_sort FROM f360.product_media WHERE color_id = p_color_id;
  FOREACH v_path IN ARRAY p_paths LOOP
    IF left(v_path, length(v_prefix)) IS DISTINCT FROM v_prefix THEN RAISE EXCEPTION 'Ruta de foto no válida.'; END IF;
    v_file := substr(v_path, length(v_prefix) + 1);
    IF v_file !~ '^[A-Za-z0-9][A-Za-z0-9_-]*(\.[A-Za-z0-9]+)?$' THEN RAISE EXCEPTION 'Ruta de foto no válida.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'product-images' AND o.name = v_path) THEN
      RAISE EXCEPTION 'La foto no se subió correctamente. Intenta de nuevo.';
    END IF;
    IF EXISTS (SELECT 1 FROM f360.product_media WHERE storage_path = v_path) THEN RAISE EXCEPTION 'Esa foto ya está agregada.'; END IF;
    v_sort := v_sort + 1;
    INSERT INTO f360.product_media (product_id, color_id, storage_path, sort, created_by) VALUES (p_product_id, p_color_id, v_path, v_sort, auth.uid());
  END LOOP;
  UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  RETURN public.f360_get_product(p_product_id);
END $$;
