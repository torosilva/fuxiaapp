-- One store product per model (Mario 2026-10-03) — database tests (STAGING). One transaction, ROLLED BACK.
-- Own fixture model sold as 2 per-colour store products. The publish itself is simulated (no Woo call).
BEGIN;
-- these tests exercise the REAL sale path: the test-store switch (20261009000300) is turned off inside this rolled-back transaction
UPDATE f360.sales_targets SET is_test = false;
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
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.mario', :'mario', true), set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE mario uuid := current_setting('t.mario')::uuid; car uuid := current_setting('t.carolina')::uuid; r jsonb; pid uuid; tid uuid; job uuid; bodega uuid;
  v_n36 uuid; v_r36 uuid; before int; c_n uuid; c_r uuid;
BEGIN
  SELECT id, fulfillment_location_id INTO tid, bodega FROM f360.sales_targets WHERE key = 'woo_staging4';
  -- fixture: model "ZZ Unir" (Negro, Rojo · 36) sold in the store as 2 per-colour products (990145 Negro, 990146 Rojo)
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Unir', ARRAY['36'], '[{"name":"Negro"},{"name":"Rojo"}]'::jsonb)$q$)->>'id')::uuid;
  UPDATE f360.products SET regular_price = 2800, category_key = 'botas', description = 'Prueba' WHERE id = pid;
  SELECT id INTO c_n FROM f360.product_colors WHERE product_id = pid AND name = 'Negro';
  SELECT id INTO c_r FROM f360.product_colors WHERE product_id = pid AND name = 'Rojo';
  INSERT INTO f360.product_media (product_id, color_id, storage_path) VALUES (pid, c_n, 'f360/zz/n.jpg'), (pid, c_r, 'f360/zz/r.jpg');
  SELECT id INTO v_n36 FROM f360.product_variants WHERE color_id = c_n; SELECT id INTO v_r36 FROM f360.product_variants WHERE color_id = c_r;
  INSERT INTO f360.legacy_woo_map (target_id, woo_variation_id, woo_product_id, woo_product_name, snapshot_at, status, human_locked, confirmed_variant_id)
    VALUES (tid, 990315, 990145, 'ZZ Unir Negras', now(), 'confirmado', true, v_n36), (tid, 990316, 990146, 'ZZ Unir Rojas', now(), 'confirmado', true, v_r36);
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id)
    VALUES (tid, v_n36, 990315, 'legacy_adopted', 990145), (tid, v_r36, 990316, 'legacy_adopted', 990146);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2}]')$q$, bodega, v_n36));

  r := pg_temp.as(NULL, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[])$q$, pid), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot merge (owner only)', r::text);
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[], '{"990145":"/producto/zz-unir-negras/"}')$q$, pid));
  job := (r->'items'->0->>'job_id')::uuid;
  PERFORM pg_temp.ok(job IS NOT NULL AND EXISTS (SELECT 1 FROM f360.sync_jobs WHERE id = job AND status = 'queued'), 'start: a normal publish job is requested', left(r::text, 140));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id WHERE vl.target_id = tid AND v.product_id = pid)
    AND (SELECT count(*) FROM f360.retired_woo_links WHERE target_id = tid AND woo_product_id IN (990145, 990146)) = 2,
    'old per-colour links retired (kept for orders), no longer pushed', '');
  PERFORM pg_temp.ok((SELECT legacy_products->0->>'path' FROM f360.legacy_consolidations WHERE product_id = pid) = '/producto/zz-unir-negras/'
    AND (SELECT jsonb_array_length(legacy_products) FROM f360.legacy_consolidations WHERE product_id = pid) = 2, 'old store products + paths recorded for redirects', '');
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[])$q$, pid));
  PERFORM pg_temp.ok((r->'items'->0->>'job_id')::uuid = job, 'starting again is harmless (same job)', left(r::text, 100));
  UPDATE f360.sync_jobs SET status = 'failed' WHERE id = job;
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[])$q$, pid));
  PERFORM pg_temp.ok((r->'items'->0->>'job_id')::uuid <> job, 'a failed publish is retried with a new job', left(r::text, 100));
  job := (r->'items'->0->>'job_id')::uuid;

  SELECT on_hand INTO before FROM f360.inventory_balances WHERE variant_id = v_n36 AND location_id = bodega;
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-cons-1","topic":"order.created"}',
    jsonb_build_object('id', 990000501, 'status', 'processing', 'date_modified_gmt', '2026-10-03T19:00:00', 'currency', 'MXN',
      'line_items', '[{"id":1,"product_id":990145,"variation_id":990315,"quantity":1}]'::jsonb, 'refunds', '[]'::jsonb));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_n36 AND location_id = bodega) = before - 1,
    'order on the old per-colour product → same pair sold (retired link)', r::text);
  BEGIN
    INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id) VALUES (tid, v_n36, 990315, 'legacy_adopted', 990145);
    r := '{}';
  EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya se unió%', 'a merged model cannot be re-linked to the old products', r::text);
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_finish('woo_staging4', %L)$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Todavía no se publica%', 'finish waits for the publish', r::text);

  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id, woo_status) VALUES (tid, pid, 990777, 'draft');
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin) VALUES (tid, v_n36, 990801, 'f360_published'), (tid, v_r36, 990802, 'f360_published');
  UPDATE f360.sync_jobs SET status = 'succeeded' WHERE id = job;
  PERFORM pg_temp.ok(true, 'new single product may link its sizes (guard allows a merge)', '');
  DELETE FROM f360.stock_sync_queue WHERE target_id = tid;
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_finish('woo_staging4', %L)$q$, pid));
  PERFORM pg_temp.ok(r->>'status' = 'publicada' AND r->>'new_path' = '/producto/zz-unir/', 'finish: merged; new URL', left(r::text, 140));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.woo_visibility_requests WHERE target_id = tid AND woo_product_id = 990777 AND kind = 'mostrar' AND status = 'pendiente')
    AND (SELECT count(*) FROM f360.woo_visibility_requests WHERE target_id = tid AND woo_product_id IN (990145, 990146) AND kind = 'ocultar' AND status = 'pendiente') = 2,
    'new product shown, the 2 old ones hidden (never deleted)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.stock_sync_queue WHERE target_id = tid) = 2, 'stock re-sent to the new product', '');
  r := public.f360_legacy_content_list('woo_staging4', ARRAY[pid]);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'content push no longer targets the old products', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_consolidations('woo_staging4')$q$);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'name' = 'ZZ Unir' AND x->>'status' = 'publicada'), 'team sees the merge status', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
