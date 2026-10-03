-- One store product per model (Mario 2026-10-03) — database tests (STAGING). One transaction, ROLLED BACK.
-- Botas Largas: today 2 store products (145 Café, 146 Negras). The publish itself is simulated (no Woo call).
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
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.mario', :'mario', true), set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE mario uuid := current_setting('t.mario')::uuid; car uuid := current_setting('t.carolina')::uuid; r jsonb; pid uuid; tid uuid; job uuid; bodega uuid;
  v_cafe36 uuid; n int; before int;
BEGIN
  SELECT id INTO pid FROM f360.products WHERE name = 'Botas Largas';
  SELECT id, fulfillment_location_id INTO tid, bodega FROM f360.sales_targets WHERE key = 'woo_staging4';
  SELECT variant_id INTO v_cafe36 FROM f360.woo_variant_links WHERE target_id = tid AND woo_variation_id = 315;
  r := pg_temp.as(NULL, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[])$q$, pid), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot merge (owner only)', r::text);

  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[], '{"145":"/producto/botas-largas-cafes/"}')$q$, pid));
  job := (r->'items'->0->>'job_id')::uuid;
  PERFORM pg_temp.ok(job IS NOT NULL AND EXISTS (SELECT 1 FROM f360.sync_jobs WHERE id = job AND status = 'queued'), 'start: a normal publish job is requested', left(r::text, 140));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.woo_variant_links vl JOIN f360.product_variants v ON v.id = vl.variant_id WHERE vl.target_id = tid AND v.product_id = pid)
    AND (SELECT count(*) FROM f360.retired_woo_links WHERE target_id = tid AND woo_product_id IN (145, 146)) = 12,
    'old per-colour links retired (12 sizes kept for orders), no longer pushed', '');
  PERFORM pg_temp.ok((SELECT legacy_products->0->>'path' FROM f360.legacy_consolidations WHERE product_id = pid) = '/producto/botas-largas-cafes/'
    AND (SELECT jsonb_array_length(legacy_products) FROM f360.legacy_consolidations WHERE product_id = pid) = 2, 'old store products + paths recorded for redirects', '');
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_start('woo_staging4', ARRAY[%L]::uuid[])$q$, pid));
  PERFORM pg_temp.ok((r->'items'->0->>'job_id')::uuid = job, 'starting again is harmless (same job)', left(r::text, 100));

  -- an order that still arrives for the OLD Café 36 product: recognised, Bodega discounted
  SELECT on_hand INTO before FROM f360.inventory_balances WHERE variant_id = v_cafe36 AND location_id = bodega;
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-cons-1","topic":"order.created"}',
    jsonb_build_object('id', 990000501, 'status', 'processing', 'date_modified_gmt', '2026-10-03T19:00:00', 'currency', 'MXN',
      'line_items', '[{"id":1,"product_id":145,"variation_id":315,"quantity":1}]'::jsonb, 'refunds', '[]'::jsonb));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_cafe36 AND location_id = bodega) = before - 1,
    'order on the old per-colour product → same pair sold (retired link)', r::text);

  -- legacy re-link is refused for a merged model
  BEGIN
    INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id) VALUES (tid, v_cafe36, 315, 'legacy_adopted', 145);
    r := '{}';
  EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya se unió%', 'a merged model cannot be re-linked to the old products', r::text);

  -- finish before the publish: refused
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_finish('woo_staging4', %L)$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Todavía no se publica%', 'finish waits for the publish', r::text);

  -- simulate the publisher's success (new product 990777 + its F360 variations)
  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id, woo_status) VALUES (tid, pid, 990777, 'draft');
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin)
    SELECT tid, v.id, 990800 + row_number() OVER (ORDER BY v.id), 'f360_published' FROM f360.product_variants v WHERE v.product_id = pid AND v.status = 'active';
  UPDATE f360.sync_jobs SET status = 'succeeded' WHERE id = job;
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.woo_variant_links WHERE target_id = tid AND woo_product_id IS NULL AND origin = 'f360_published'
    AND variant_id IN (SELECT id FROM f360.product_variants WHERE product_id = pid)) = 12, 'new single product may link the 12 sizes (guard allows a merge)', '');

  DELETE FROM f360.stock_sync_queue WHERE target_id = tid;
  r := pg_temp.as(mario, format($q$SELECT public.f360_consolidate_finish('woo_staging4', %L)$q$, pid));
  PERFORM pg_temp.ok(r->>'status' = 'publicada' AND r->>'new_path' = '/producto/botas-largas/', 'finish: merged; new URL /producto/botas-largas/', left(r::text, 140));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.woo_visibility_requests WHERE target_id = tid AND woo_product_id = 990777 AND kind = 'mostrar' AND status = 'pendiente')
    AND (SELECT count(*) FROM f360.woo_visibility_requests WHERE target_id = tid AND woo_product_id IN (145, 146) AND kind = 'ocultar' AND status = 'pendiente') = 2,
    'new product shown, the 2 old ones hidden (never deleted)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.stock_sync_queue WHERE target_id = tid) = 12, 'stock re-sent to the new product (12 sizes)', '');
  r := public.f360_legacy_content_list('woo_staging4', ARRAY[pid]);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'content push no longer targets the old products', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_consolidations('woo_staging4')$q$);
  PERFORM pg_temp.ok(r->0->>'name' = 'Botas Largas' AND r->0->>'status' = 'publicada', 'team sees the merge status', left(r::text, 120));
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
