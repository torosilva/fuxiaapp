-- Archive / reactivate a product — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
-- Test fixture (this transaction only): "ZZ Publicado", an F360 model already published to channel p_target
-- (Nude 37, 2800 MXN, ready, linked to Woo product 990001 / variation 990011, published hash current), p_pairs in Bodega CDMX.
CREATE FUNCTION pg_temp.zz_published(p_target text, p_pairs int DEFAULT 0) RETURNS uuid LANGUAGE plpgsql AS $fx$
DECLARE pid uuid; cid uuid; vid uuid; t uuid := (SELECT id FROM f360.sales_targets WHERE key = p_target);
BEGIN
  INSERT INTO f360.products (name, slug, code, category_key, regular_price, description)
    VALUES ('ZZ Publicado', 'zz-publicado', 'ZZ-PUBLICADO', 'ballerinas', 2800, 'Fixture de prueba') RETURNING id INTO pid;
  INSERT INTO f360.product_sizes (product_id, label, sort) VALUES (pid, '37', 1);
  INSERT INTO f360.product_colors (product_id, name, code, sort) VALUES (pid, 'Nude', 'NUDE', 1) RETURNING id INTO cid;
  INSERT INTO f360.product_variants (product_id, color_id, size_label) VALUES (pid, cid, '37') RETURNING id INTO vid;
  PERFORM f360.refresh_skus(pid);
  INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', 'f360/ZZ-PUBLICADO/NUDE/a.png');
  INSERT INTO f360.product_media (product_id, color_id, storage_path, sort) VALUES (pid, cid, 'f360/ZZ-PUBLICADO/NUDE/a.png', 1);
  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id, woo_status, published_hash, last_success_at)
    VALUES (t, pid, 990001, 'publish', f360.publish_hash(pid), now());
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id) VALUES (t, vid, 990011);
  IF p_pairs > 0 THEN
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) SELECT vid, id, p_pairs FROM f360.locations WHERE name = 'Bodega CDMX';
  END IF;
  RETURN pid;
END $fx$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
-- a seller for permission checks: lab user 15550100011 gets the role inside this transaction only
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'seller', 'ZZ Vendedora', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'seller' RETURNING auth_user_id AS seller \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.seller', :'seller', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; sel uuid := current_setting('t.seller')::uuid;
  bodega uuid := (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX');
  mac uuid;
  r jsonb; pid uuid; lp uuid; dp uuid; err text;
BEGIN
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_arch_pub', 'ZZ publicado', 'https://zz.invalid', bodega, true);
  mac := pg_temp.zz_published('zz_arch_pub', 2);
  r := pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Archivo', ARRAY['36','37'], '[{"name":"Negro"}]'::jsonb)$q$);
  pid := (r->>'id')::uuid;
  r := pg_temp.as(car, format($q$SELECT public.f360_product_archive_state(%L)$q$, pid));
  PERFORM pg_temp.ok(r->>'status' = 'active' AND jsonb_array_length(r->'blockers') = 0, 'new product with 0 pairs: active, nothing blocks archiving', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, true, ' ')$q$, pid));
  PERFORM pg_temp.ok(r->>'error' = 'Escribe el motivo.', 'archiving requires a reason', r::text);
  r := pg_temp.as(sel, format($q$SELECT public.f360_set_product_archived(%L, true, 'x')$q$, pid));
  PERFORM pg_temp.ok(r ? 'error' AND (SELECT status FROM f360.products WHERE id = pid) = 'active', 'a seller cannot archive', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, true, 'Ya no se vende')$q$, pid));
  PERFORM pg_temp.ok(r->>'status' = 'archived' AND r->'last_change'->>'by' = 'Carolina' AND r->'last_change'->>'reason' = 'Ya no se vende',
    'Carolina archives it; who / why recorded', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_list_products('ZZ Archivo')$q$);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'an archived product leaves the product list', r::text);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.products WHERE id = pid) AND (SELECT count(*) FROM f360.product_variants WHERE product_id = pid) = 2,
    'nothing is deleted (product and variants stay)', '');
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, false, 'Regresa a temporada')$q$, pid));
  PERFORM pg_temp.ok(r->>'status' = 'active' AND jsonb_array_length(pg_temp.as(car, $q$SELECT public.f360_list_products('ZZ Archivo')$q$)) = 1,
    'reactivated: back in the list', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.product_status_changes WHERE product_id = pid) = 2, 'both changes logged', '');
  BEGIN UPDATE f360.product_status_changes SET reason = 'x' WHERE product_id = pid; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%', 'archive history is append-only', err);

  -- blockers
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, true, 'prueba')$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%pares en inventario%' AND r->>'error' LIKE '%publicado en la tienda%' AND (SELECT status FROM f360.products WHERE id = mac) = 'active',
    'a published model with pairs cannot be archived; both reasons shown', r::text);
  INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand)
    SELECT id, bodega, 1 FROM f360.product_variants WHERE product_id = pid LIMIT 1;
  r := pg_temp.as(car, format($q$SELECT public.f360_product_archive_state(%L)$q$, pid));
  PERFORM pg_temp.ok(r->'blockers'->>0 = 'Tiene 1 pares en inventario', 'one pair in stock blocks archiving', r::text);

  -- homologation: confirmed on a real channel blocks; on a practice channel (demo_…) it does not
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_arch', 'ZZ real', 'https://zz.invalid', bodega, true);
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('demo_zz_arch', 'ZZ práctica', 'https://zz.invalid', bodega, true);
  PERFORM public.f360_legacy_load_snapshot('zz_arch', '[{"woo_variation_id":970001,"woo_product_id":9700,"woo_product_name":"ZZ Legacy","woo_size":"36"}]');
  PERFORM public.f360_legacy_load_snapshot('demo_zz_arch', '[{"woo_variation_id":970002,"woo_product_id":9701,"woo_product_name":"ZZ Demo","woo_size":"36"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_arch', ARRAY[970001], NULL, 'ZZ Legacy Modelo', NULL, 'Negro', NULL)$q$);
  lp := (r->>'product_id')::uuid;
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('demo_zz_arch', ARRAY[970002], NULL, 'Demo · ZZ Modelo', NULL, 'Negro', NULL)$q$);
  dp := (r->>'product_id')::uuid;
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, true, 'prueba')$q$, lp));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Homologación%', 'a model confirmed in the real homologation cannot be archived (reopen first)', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_set_product_archived(%L, true, 'Modelo de práctica')$q$, dp));
  PERFORM pg_temp.ok(r->>'status' = 'archived', 'a practice-channel model (demo_…) can be archived', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
