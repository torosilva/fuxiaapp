-- Fuxia 360 · pase E11 — foto de la app (bienvenida + portada del Home) elegida en Fuxia 360 (same as migration 20261018000100).
-- Apply ONLY with scripts/f360/prod_sql.sh. Additive: the published app already asks for it (OTA 2026-10-08) and falls back to
-- the store's Destacado / newest product until this exists. Deploy the admin (scripts/f360/deploy_prod_admin.sh) AFTER this.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production' AND is_production) THEN
    RAISE EXCEPTION 'ABORT: this pase is for PRODUCTION only (woo_production target missing)';
  END IF;
  IF EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261018000100') OR to_regclass('f360.app_welcome_photos') IS NOT NULL THEN
    RAISE EXCEPTION 'ABORT: already applied';
  END IF;
END $$;
-- ════════ 20261018000100_f360_app_welcome_photo.sql ════════
CREATE TABLE f360.app_welcome_photos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_path  text CHECK (storage_path IS NULL OR storage_path ~ '^f360/[A-Za-z0-9._/-]+$'),
  product_id    uuid REFERENCES f360.products(id),
  set_by        uuid NOT NULL,
  set_by_name   text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT clock_timestamp()   -- not now(): two changes in one transaction must still order
);
CREATE INDEX app_welcome_photos_created_idx ON f360.app_welcome_photos (created_at DESC);
ALTER TABLE f360.app_welcome_photos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.app_welcome_photos FROM PUBLIC, anon, authenticated;
CREATE TRIGGER app_welcome_photos_append_only BEFORE UPDATE OR DELETE ON f360.app_welcome_photos
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();
COMMENT ON TABLE f360.app_welcome_photos IS
  'Mobile app welcome photo, append-only. Current = latest row; storage_path NULL = use the store''s featured/newest product.';

-- Public, read-only: only the storage path of the current photo (the bucket is already public).
CREATE FUNCTION public.f360_app_welcome_photo() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('path',
    (SELECT w.storage_path FROM f360.app_welcome_photos w ORDER BY w.created_at DESC, w.id DESC LIMIT 1))
$$;

CREATE FUNCTION public.f360_app_welcome_admin() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN jsonb_build_object(
    'current', (SELECT jsonb_build_object('path', w.storage_path, 'product', p.name, 'by', w.set_by_name, 'at', w.created_at)
                FROM f360.app_welcome_photos w LEFT JOIN f360.products p ON p.id = w.product_id
                ORDER BY w.created_at DESC, w.id DESC LIMIT 1),
    'history', (SELECT coalesce(jsonb_agg(h ORDER BY h->>'at' DESC), '[]'::jsonb) FROM (
                  SELECT jsonb_build_object('path', w.storage_path, 'product', p.name, 'by', w.set_by_name, 'at', w.created_at) AS h
                  FROM f360.app_welcome_photos w LEFT JOIN f360.products p ON p.id = w.product_id
                  ORDER BY w.created_at DESC, w.id DESC LIMIT 10) x),
    -- newest models first; every photo of each, so a lifestyle shot can be picked over the packshot
    'catalog', (SELECT coalesce(jsonb_agg(jsonb_build_object('product_id', x.product_id, 'product', x.name, 'path', x.storage_path)
                                          ORDER BY x.created_at DESC, x.sort), '[]'::jsonb) FROM (
                  SELECT m.product_id, p.name, m.storage_path, p.created_at, m.sort
                  FROM f360.product_media m JOIN f360.products p ON p.id = m.product_id
                  WHERE p.status = 'active' AND p.id IN (
                    SELECT p2.id FROM f360.products p2 WHERE p2.status = 'active'
                      AND EXISTS (SELECT 1 FROM f360.product_media m2 WHERE m2.product_id = p2.id)
                    ORDER BY p2.created_at DESC LIMIT 12)
                  ORDER BY p.created_at DESC, m.sort LIMIT 60) x));
END $$;

-- p_path NULL = go back to the store's photo. p_product_id is only a label (which model the photo shows).
CREATE FUNCTION public.f360_set_app_welcome_photo(p_path text, p_product_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_path text := nullif(btrim(p_path), '');
BEGIN
  r := f360.require_role('operator');
  IF v_path IS NOT NULL THEN
    IF v_path !~ '^f360/[A-Za-z0-9._/-]+$' OR v_path LIKE '%..%' THEN RAISE EXCEPTION 'Esa foto no es válida.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM storage.objects o WHERE o.bucket_id = 'product-images' AND o.name = v_path) THEN
      RAISE EXCEPTION 'La foto no se subió correctamente. Intenta de nuevo.';
    END IF;
  END IF;
  IF p_product_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN
    RAISE EXCEPTION 'Producto no encontrado.';
  END IF;
  INSERT INTO f360.app_welcome_photos (storage_path, product_id, set_by, set_by_name)
  VALUES (v_path, CASE WHEN v_path IS NULL THEN NULL ELSE p_product_id END, r.auth_user_id, r.display_name);
  RETURN public.f360_app_welcome_admin();
END $$;

REVOKE ALL ON FUNCTION public.f360_app_welcome_photo(), public.f360_app_welcome_admin(), public.f360_set_app_welcome_photo(text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.f360_app_welcome_photo() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.f360_app_welcome_admin(), public.f360_set_app_welcome_photo(text, uuid) TO authenticated, service_role;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261018000100', 'f360_app_welcome_photo', '{}');
COMMIT;
