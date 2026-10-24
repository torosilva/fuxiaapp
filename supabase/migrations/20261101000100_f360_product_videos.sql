-- Fuxia 360 · Videos en el producto (Mario 2026-10-24: "hagamos que se puedan poner videos").
-- Carolina sube en la ficha de cada color hasta 2 videos cortos (mp4 / mov / webm, ≤ 50 MB). Se guardan en el mismo bucket
-- público product-images, en la carpeta del color (f360/{MODELO}/{COLOR}/…), igual que las fotos. El publicador los manda a
-- WooCommerce como metadato del producto (_fuxia360_videos: URL pública + color), y un mu-plugin los muestra en la ficha.
-- ADITIVA: no cambia f360.product_media ni nada que lea fotos (foto principal, galería, app, catálogo de la tienda).
--   · f360.product_videos              tabla nueva; al quitar un color se van sus videos (ON DELETE CASCADE, solo las filas).
--   · f360_add_video(product,color,path) operator+ → el archivo debe estar subido en la carpeta de ESE color, ser video y ≤ 50 MB.
--   · f360_remove_video(id)              operator+
--   · f360_product_videos(product)       viewer+  → videos por color (para el panel).
--   · f360_pub_claim                     el snapshot lleva 'videos' por color (las demás líneas, iguales a 20261012000200).
--   · f360.publish_hash                  agrega 'videos' SOLO si el producto tiene alguno: el hash de los productos sin video
--                                        no cambia, así que nada aparece "por republicar".
-- Rollback: supabase/rollbacks/20261101000100_f360_product_videos.down.sql

CREATE TABLE f360.product_videos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  color_id      uuid NOT NULL REFERENCES f360.product_colors(id) ON DELETE CASCADE,
  storage_path  text NOT NULL UNIQUE CHECK (storage_path ~ '^f360/[A-Za-z0-9._/-]+$'),
  mime_type     text NOT NULL CHECK (mime_type IN ('video/mp4', 'video/quicktime', 'video/webm')),
  bytes         bigint NOT NULL CHECK (bytes > 0 AND bytes <= 52428800),
  sort          integer NOT NULL DEFAULT 0,
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_videos_color_idx ON f360.product_videos (color_id, sort);
CREATE INDEX product_videos_product_idx ON f360.product_videos (product_id);
ALTER TABLE f360.product_videos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.product_videos FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.product_videos TO service_role;
COMMENT ON TABLE f360.product_videos IS 'Videos cortos por color (máx. 2), en product-images bajo la carpeta del color. Van a Woo como _fuxia360_videos.';

CREATE FUNCTION f360.product_videos_json(p_product_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'color_id', v.color_id, 'path', v.storage_path, 'mime', v.mime_type, 'bytes', v.bytes)
           ORDER BY c.sort, c.created_at, v.sort, v.created_at), '[]'::jsonb)
  FROM f360.product_videos v JOIN f360.product_colors c ON c.id = v.color_id WHERE v.product_id = p_product_id
$$;

CREATE FUNCTION public.f360_product_videos(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN f360.product_videos_json(p_product_id);
END $$;

CREATE FUNCTION public.f360_add_video(p_product_id uuid, p_color_id uuid, p_path text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_prefix text; v_file text; o storage.objects; v_mime text; v_bytes bigint; v_sort int;
BEGIN
  r := f360.require_role('operator');
  SELECT 'f360/' || p.code || '/' || c.code || '/' INTO v_prefix
    FROM f360.product_colors c JOIN f360.products p ON p.id = c.product_id
    WHERE c.id = p_color_id AND c.product_id = p_product_id;
  IF v_prefix IS NULL THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  IF left(coalesce(p_path, ''), length(v_prefix)) IS DISTINCT FROM v_prefix THEN RAISE EXCEPTION 'Ruta de video no válida.'; END IF;
  v_file := substr(p_path, length(v_prefix) + 1);
  IF v_file !~ '^[A-Za-z0-9][A-Za-z0-9_-]*\.(mp4|mov|webm)$' THEN RAISE EXCEPTION 'Ruta de video no válida.'; END IF;
  SELECT * INTO o FROM storage.objects WHERE bucket_id = 'product-images' AND name = p_path;
  IF o.id IS NULL THEN RAISE EXCEPTION 'El video no se subió correctamente. Intenta de nuevo.'; END IF;
  v_mime := lower(coalesce(o.metadata->>'mimetype', ''));
  v_bytes := coalesce((o.metadata->>'size')::bigint, 0);
  IF v_mime NOT IN ('video/mp4', 'video/quicktime', 'video/webm') THEN RAISE EXCEPTION 'Ese archivo no es un video (mp4, mov o webm).'; END IF;
  IF v_bytes <= 0 OR v_bytes > 52428800 THEN RAISE EXCEPTION 'El video pesa más de 50 MB. Súbelo más corto.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.product_videos WHERE storage_path = p_path) THEN RAISE EXCEPTION 'Ese video ya está agregado.'; END IF;
  IF (SELECT count(*) FROM f360.product_videos WHERE color_id = p_color_id) >= 2 THEN RAISE EXCEPTION 'Cada color lleva máximo 2 videos.'; END IF;
  SELECT coalesce(max(sort), 0) + 1 INTO v_sort FROM f360.product_videos WHERE color_id = p_color_id;
  INSERT INTO f360.product_videos (product_id, color_id, storage_path, mime_type, bytes, sort, created_by)
    VALUES (p_product_id, p_color_id, p_path, v_mime, v_bytes, v_sort, auth.uid());
  UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  RETURN f360.product_videos_json(p_product_id);
END $$;

CREATE FUNCTION public.f360_remove_video(p_video_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_product uuid;
BEGIN
  r := f360.require_role('operator');
  DELETE FROM f360.product_videos WHERE id = p_video_id RETURNING product_id INTO v_product;
  IF v_product IS NULL THEN RAISE EXCEPTION 'Video no encontrado.'; END IF;
  UPDATE f360.products SET updated_at = now() WHERE id = v_product;
  RETURN f360.product_videos_json(v_product);
END $$;

REVOKE ALL ON FUNCTION f360.product_videos_json(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_product_videos(uuid), public.f360_add_video(uuid, uuid, text), public.f360_remove_video(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_product_videos(uuid), public.f360_add_video(uuid, uuid, text), public.f360_remove_video(uuid) TO authenticated, service_role;

-- Hash de publicación: igual que 20261005000100, más 'videos' solo cuando el producto tiene videos.
CREATE OR REPLACE FUNCTION f360.publish_hash(p_product_id uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT md5((jsonb_build_object(
    'name', p.name, 'code', p.code, 'description', p.description, 'short', p.short_description,
    'regular', p.regular_price, 'sale', p.sale_price, 'category', p.category_key,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name,
                 'media', (SELECT coalesce(jsonb_agg(m.storage_path ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(v.sku || ':' || v.status ORDER BY v.sku), '[]') FROM f360.product_variants v WHERE v.product_id = p.id)
  ) || coalesce((SELECT jsonb_build_object('prices', jsonb_object_agg(pp.currency_code || ':' || c.woo_meta_key, pp.amount))
                 FROM f360.product_prices pp JOIN f360.currencies c ON c.code = pp.currency_code AND c.active
                 WHERE pp.product_id = p.id HAVING count(*) > 0), '{}'::jsonb)
    || coalesce((SELECT jsonb_build_object('videos', jsonb_agg(v.storage_path ORDER BY v.color_id, v.sort, v.created_at))
                 FROM f360.product_videos v WHERE v.product_id = p.id HAVING count(*) > 0), '{}'::jsonb))::text)
  FROM f360.products p WHERE p.id = p_product_id
$$;

-- Snapshot del publicador: igual que 20261012000200, más 'videos' por color.
CREATE OR REPLACE FUNCTION public.f360_pub_claim(p_job_id uuid, p_caller uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE j f360.sync_jobs; t f360.sales_targets; p f360.products; cat f360.woo_category_links;
BEGIN
  SELECT * INTO j FROM f360.sync_jobs WHERE id = p_job_id FOR UPDATE;
  IF j.id IS NULL THEN RAISE EXCEPTION 'Publicación no encontrada.'; END IF;
  IF j.requested_by IS DISTINCT FROM p_caller THEN RAISE EXCEPTION 'Esta publicación la pidió otra persona.' USING ERRCODE = 'insufficient_privilege'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = p_caller AND role = 'owner') THEN
    RAISE EXCEPTION 'Solo una dueña puede publicar.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF j.status = 'running' AND coalesce(j.heartbeat_at, j.started_at) >= now() - interval '10 minutes' THEN
    RAISE EXCEPTION 'Esta publicación ya está en curso.';
  END IF;
  IF j.status NOT IN ('queued', 'running') THEN RAISE EXCEPTION 'Esta publicación ya terminó.'; END IF;
  IF NOT (f360.product_readiness(j.product_id)->>'ready')::boolean THEN RAISE EXCEPTION 'El producto todavía no está listo para publicar.'; END IF;

  UPDATE f360.products SET codes_locked_at = now() WHERE id = j.product_id AND codes_locked_at IS NULL;
  UPDATE f360.sync_jobs SET status = 'running', started_at = coalesce(started_at, now()), heartbeat_at = now(),
    attempt = attempt + 1, content_hash = f360.publish_hash(j.product_id) WHERE id = j.id RETURNING * INTO j;
  SELECT * INTO t FROM f360.sales_targets WHERE id = j.target_id;
  SELECT * INTO p FROM f360.products WHERE id = j.product_id;
  SELECT * INTO cat FROM f360.woo_category_links WHERE target_id = t.id AND category_key = p.category_key;

  RETURN jsonb_build_object(
    'job', jsonb_build_object('id', j.id, 'attempt', j.attempt, 'requested_by_name', j.requested_by_name, 'content_hash', j.content_hash),
    'target', jsonb_build_object('id', t.id, 'key', t.key, 'base_url', t.base_url, 'is_production', t.is_production,
               'fulfillment_location_id', t.fulfillment_location_id,
               'catalog_mode', t.catalog_mode, 'stock_sync_mode', t.stock_sync_mode, 'stock_policy', t.stock_policy),
    'product', jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name, 'slug', p.slug, 'description', p.description,
               'short_description', p.short_description, 'regular_price', p.regular_price, 'sale_price', p.sale_price,
               'category_key', p.category_key,
               'woo_category', CASE WHEN cat.woo_term_id IS NULL THEN NULL ELSE jsonb_build_object('id', cat.woo_term_id, 'slug', cat.woo_slug) END,
               'woo_product_id', (SELECT woo_product_id FROM f360.woo_product_links WHERE target_id = t.id AND product_id = p.id),
               'prices', f360.snapshot_prices(p.id)),
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]') FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'code', c.code, 'name', c.name, 'hex', c.hex,
                 'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path, 'alt', m.alt,
                             'woo_media_id', (SELECT woo_media_id FROM f360.woo_media_links ml WHERE ml.target_id = t.id AND ml.media_id = m.id))
                           ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id),
                 'videos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'path', v.storage_path, 'mime', v.mime_type)
                           ORDER BY v.sort, v.created_at), '[]') FROM f360.product_videos v WHERE v.color_id = c.id))
               ORDER BY c.sort, c.created_at), '[]') FROM f360.product_colors c WHERE c.product_id = p.id),
    'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'color_id', v.color_id, 'size', v.size_label, 'sku', v.sku,
                   'status', v.status, 'ats', f360.online_ats(v.id, t.fulfillment_location_id),
                   'woo_variation_id', vl.woo_variation_id, 'last_pushed_stock', vl.last_pushed_stock)
                 ORDER BY c.sort, c.created_at, s.sort), '[]')
                 FROM f360.product_variants v JOIN f360.product_colors c ON c.id = v.color_id
                 JOIN f360.product_sizes s ON s.product_id = v.product_id AND s.label = v.size_label
                 LEFT JOIN f360.woo_variant_links vl ON vl.target_id = t.id AND vl.variant_id = v.id
                 WHERE v.product_id = p.id));
END $function$;
