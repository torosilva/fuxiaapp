-- Rollback of 20261101000100_f360_product_videos: restores f360_pub_claim (20261012000200) and f360.publish_hash
-- (20261005000100) exactly, then drops the video functions and table. The video FILES stay in storage (product-images);
-- the store keeps the _fuxia360_videos meta until the next publish (the mu-plugin can be deleted to hide them).
-- Then: DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261101000100';
BEGIN;
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
                           ORDER BY m.sort, m.created_at), '[]') FROM f360.product_media m WHERE m.color_id = c.id))
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
                 WHERE pp.product_id = p.id HAVING count(*) > 0), '{}'::jsonb))::text) FROM f360.products p WHERE p.id = p_product_id
$$;

DROP FUNCTION public.f360_remove_video(uuid);
DROP FUNCTION public.f360_add_video(uuid, uuid, text);
DROP FUNCTION public.f360_product_videos(uuid);
DROP FUNCTION f360.product_videos_json(uuid);
DROP TABLE f360.product_videos;
COMMIT;
