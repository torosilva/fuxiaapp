-- Track D · D2 — legacy homologation + legacy channel links — database tests (STAGING). One transaction, ROLLED BACK.
-- Uses a throw-away channel "zz_d2" and fake Woo ids (9001…, 99xxxx): the real homologation rows of woo_staging4 are not touched.
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
CREATE FUNCTION pg_temp.st(p_var int) RETURNS text LANGUAGE sql AS
$$ SELECT m.status FROM f360.legacy_woo_map m JOIN f360.sales_targets t ON t.id = m.target_id AND t.key = 'zz_d2' WHERE m.woo_variation_id = p_var $$;
CREATE FUNCTION pg_temp.order_json(p_id bigint, p_lines jsonb) RETURNS jsonb LANGUAGE sql AS
$$ SELECT jsonb_build_object('id', p_id, 'status', 'processing', 'date_modified_gmt', '2026-10-02T12:00:00', 'currency', 'MXN', 'refunds', '[]'::jsonb, 'line_items', p_lines) $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS seller FROM f360.user_roles WHERE role = 'seller' ORDER BY created_at LIMIT 1 \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.seller', :'seller', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; sel uuid := current_setting('t.seller')::uuid;
  bodega uuid := (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX');
  mac uuid := (SELECT id FROM f360.products WHERE name = 'Macarena');
  tgt uuid; r jsonb; err text; pid uuid; pid2 uuid; v_nude35 uuid; v_verde37 uuid; ev0 int; bal0 int; lk0 int; q0 int; n int; snap jsonb;
BEGIN
  PERFORM pg_temp.ok(car IS NOT NULL AND sel IS NOT NULL AND bodega IS NOT NULL AND mac IS NOT NULL, 'fixtures: Carolina (owner), a seller, Bodega CDMX, Macarena', '');
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_d2', 'ZZ D2', 'https://zz.invalid', bodega, true) RETURNING id INTO tgt;

  -- ── snapshot (system) ──
  r := public.f360_legacy_load_snapshot('zz_d2', jsonb_build_array(
    jsonb_build_object('woo_variation_id', 900101, 'woo_product_id', 9001, 'woo_product_name', 'ZZ Paula nude', 'woo_parent_sku', 'BALL-PAULA-NDE', 'woo_size', '35', 'woo_regular_price', 2800, 'sold_all', 3),
    jsonb_build_object('woo_variation_id', 900102, 'woo_product_id', 9001, 'woo_product_name', 'ZZ Paula nude', 'woo_parent_sku', 'BALL-PAULA-NDE', 'woo_size', '36', 'woo_regular_price', 2800),
    jsonb_build_object('woo_variation_id', 900201, 'woo_product_id', 9002, 'woo_product_name', 'ZZ Paula negro', 'woo_parent_sku', 'BALL-PAULA-TPE-1', 'woo_size', '35'),
    jsonb_build_object('woo_variation_id', 900202, 'woo_product_id', 9002, 'woo_product_name', 'ZZ Paula negro', 'woo_parent_sku', 'BALL-PAULA-TPE-1', 'woo_size', '37'),
    jsonb_build_object('woo_variation_id', 900301, 'woo_product_id', 9003, 'woo_product_name', 'ZZ Mules', 'woo_size', '37'),
    jsonb_build_object('woo_variation_id', 900302, 'woo_product_id', 9003, 'woo_product_name', 'ZZ Mules', 'woo_size', '37', 'woo_color', 'Verde'),
    jsonb_build_object('woo_variation_id', 900401, 'woo_product_id', 9004, 'woo_product_name', 'ZZ Paula nude copia', 'woo_size', '35')));
  PERFORM pg_temp.ok((r->>'new')::int = 7 AND pg_temp.st(900101) = 'sin_correspondencia', 'snapshot loads 7 variations; before any proposal they are "sin correspondencia"', r::text);
  BEGIN PERFORM public.f360_legacy_load_snapshot('zz_d2', '[{"woo_variation_id":900101,"woo_product_id":9001,"woo_product_name":"ZZ Paula nude","woo_size":"38"}]'); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%requiere revisión humana%', 'a Woo variation whose size changed is refused on reload (needs a person)', err);
  BEGIN PERFORM public.f360_legacy_load_snapshot('woo_production_zz', '[]'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'unknown / production channel refused', err);

  -- ── permissions ──
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_load_snapshot('zz_d2', '[]')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'Carolina (authenticated) cannot write the Woo snapshot', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_propose('zz_d2', '[]')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'Carolina (authenticated) cannot write system proposals', r::text);
  r := pg_temp.as(sel, $q$SELECT public.f360_legacy_homologation('zz_d2')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'a seller cannot open the homologation', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_legacy_homologation('zz_d2')$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot open the homologation', r::text);
  BEGIN EXECUTE 'SET LOCAL ROLE authenticated'; PERFORM count(*) FROM f360.legacy_woo_map; RESET ROLE; err := 'read';
  EXCEPTION WHEN OTHERS THEN RESET ROLE; err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'read', 'no direct table access for authenticated', err);

  -- ── proposals (system) ──
  r := public.f360_legacy_propose('zz_d2', jsonb_build_array(
    jsonb_build_object('woo_variation_id', 900101, 'model', 'ZZ Paula', 'color', 'Nude', 'size', '35', 'confidence', 'alta', 'reason', 't', 'status', 'propuesto'),
    jsonb_build_object('woo_variation_id', 900102, 'model', 'ZZ Paula', 'color', 'Nude', 'size', '36', 'confidence', 'alta', 'reason', 't', 'status', 'propuesto'),
    jsonb_build_object('woo_variation_id', 900201, 'model', 'ZZ Paula', 'color', 'Nude', 'size', '35', 'confidence', 'media', 'reason', 't', 'status', 'propuesto'),
    jsonb_build_object('woo_variation_id', 900202, 'model', 'ZZ Paula', 'color', 'Negro', 'size', '37', 'confidence', 'alta', 'reason', 't', 'status', 'propuesto'),
    jsonb_build_object('woo_variation_id', 900301, 'model', 'ZZ Mules', 'size', '37', 'confidence', 'baja', 'reason', 'cualquier color', 'status', 'requiere_revision'),
    jsonb_build_object('woo_variation_id', 900302, 'model', 'ZZ Mules', 'color', 'Verde', 'size', '37', 'confidence', 'alta', 'reason', 't', 'status', 'propuesto')));
  PERFORM pg_temp.ok(pg_temp.st(900101) = 'conflicto' AND pg_temp.st(900201) = 'conflicto' AND pg_temp.st(900102) = 'propuesto',
    'two Woo variations proposed onto the same model+colour+size → both "conflicto"', r::text);
  PERFORM pg_temp.ok(pg_temp.st(900301) = 'requiere_revision' AND pg_temp.st(900302) = 'propuesto' AND pg_temp.st(900401) = 'sin_correspondencia',
    'any-colour variation → requiere revisión; coloured one → propuesto; no proposal → sin correspondencia', '');
  r := public.f360_legacy_propose('zz_d2', '[{"woo_variation_id":900201,"model":"ZZ Paula","color":"Negro","size":"35","confidence":"alta","reason":"t","status":"propuesto"}]');
  PERFORM pg_temp.ok(pg_temp.st(900101) = 'propuesto' AND pg_temp.st(900201) = 'propuesto', 'fixing the proposal clears the conflict on both rows', r::text);
  BEGIN PERFORM public.f360_legacy_propose('zz_d2', '[{"woo_variation_id":900101,"status":"confirmado"}]'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted' AND pg_temp.st(900101) = 'propuesto', 'the system can never propose "confirmado"', err);

  SELECT count(*) INTO ev0 FROM f360.inventory_events; SELECT count(*) INTO bal0 FROM f360.inventory_balances;
  SELECT count(*) INTO lk0 FROM f360.woo_variant_links; SELECT count(*) INTO q0 FROM f360.stock_sync_queue;

  -- ── Carolina confirms: several Woo products (one per colour) → ONE F360 model ──
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900101, 900102], NULL, 'ZZ Paula', 'ballerinas', 'Nude', 'Woo Paula nude')$q$);
  pid := (r->>'product_id')::uuid;
  PERFORM pg_temp.ok(pid IS NOT NULL AND (r->>'confirmed')::int = 2 AND pg_temp.st(900101) = 'confirmado', 'Carolina confirms Woo "Paula nude" → new model ZZ Paula / Nude / 35, 36', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900201, 900202], %L, NULL, NULL, 'Negro', NULL)$q$, pid));
  PERFORM pg_temp.ok((r->>'product_id')::uuid = pid AND (SELECT count(*) FROM f360.product_colors WHERE product_id = pid) = 2
    AND (SELECT count(*) FROM f360.product_variants WHERE product_id = pid) = 4,
    'Woo "Paula negro" (another Woo product) → the SAME model ZZ Paula, colour Negro: 1 model, 2 colours, 4 variants', r::text);
  PERFORM pg_temp.ok((SELECT string_agg(label, ',' ORDER BY sort) FROM f360.product_sizes WHERE product_id = pid) = '35,36,37',
    'model sizes = union of the Woo sizes, in order', '');
  SELECT v.id INTO v_nude35 FROM f360.product_variants v JOIN f360.product_colors c ON c.id = v.color_id WHERE v.product_id = pid AND c.name = 'Nude' AND v.size_label = '35';
  PERFORM pg_temp.ok((SELECT sku FROM f360.product_variants WHERE id = v_nude35) = 'F360-ZZ-PAULA-NUDE-35'
    AND (SELECT woo_parent_sku FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900101) = 'BALL-PAULA-NDE',
    'F360 variant gets its canonical SKU; the legacy Woo SKU is kept untouched as reference', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.legacy_woo_map_log WHERE target_id = tgt AND action = 'confirm' AND actor_name = 'Carolina') = 4,
    'every confirmation is logged with the person', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = ev0 AND (SELECT count(*) FROM f360.inventory_balances) = bal0
    AND (SELECT count(*) FROM f360.woo_variant_links) = lk0 AND (SELECT count(*) FROM f360.stock_sync_queue) = q0,
    'confirming creates NO inventory, NO balance, NO Woo link and NO stock push', '');

  -- ── human decisions are final for the machine ──
  r := public.f360_legacy_propose('zz_d2', '[{"woo_variation_id":900101,"model":"Otro","color":"Rojo","size":"40","confidence":"alta","reason":"x","status":"propuesto"}]');
  PERFORM pg_temp.ok((r->>'skipped_human')::int = 1 AND (r->>'proposed')::int = 0 AND pg_temp.st(900101) = 'confirmado'
    AND (SELECT proposed_color FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900101) = 'Nude',
    'a new automatic proposal never overwrites a human confirmation', r::text);
  BEGIN PERFORM set_config('f360.legacy_actor', 'system', true);
    UPDATE f360.legacy_woo_map SET status = 'propuesto', confirmed_variant_id = NULL WHERE target_id = tgt AND woo_variation_id = 900101; err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%inferencia automática%', 'even a direct system UPDATE of a human row is refused (trigger)', err);
  BEGIN PERFORM set_config('f360.legacy_actor', 'human', true);
    UPDATE f360.legacy_woo_map SET human_locked = false, status = 'propuesto', confirmed_variant_id = NULL WHERE target_id = tgt AND woo_variation_id = 900101; err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede desmarcar%', 'a human lock can never be removed', err);
  BEGIN DELETE FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900401; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'homologation rows are never deleted', err);
  BEGIN UPDATE f360.legacy_woo_map_log SET note = 'x' WHERE target_id = tgt; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%', 'decision history is append-only', err);

  -- ── conflicts and guards at confirmation ──
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900101], NULL, 'Otro', NULL, 'Nude', NULL)$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya está confirmada%', 'confirming an already confirmed variation is refused (reopen first)', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900401], %L, NULL, NULL, 'Nude', NULL)$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Conflicto:%' AND pg_temp.st(900401) = 'sin_correspondencia',
    'a second Woo variation onto ZZ Paula / Nude / 35 → refused as conflict, nothing changed', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900401], %L, NULL, NULL, 'Nude', NULL)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%se publica desde Fuxia 360%', 'legacy variations cannot be mixed into a model published by F360 (Macarena)', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900301, 900302], NULL, 'ZZ Mules', NULL, 'Verde', NULL)$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%talla 37%', 'two variations with the same size cannot become one colour (any-colour + Verde 37)', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900302], NULL, 'ZZ Paula', NULL, 'Verde', NULL)$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%Ya existe un modelo%', 'a new model with an existing name is refused (pick it from the list)', r::text);

  -- ── human marks + reopen ──
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_mark('zz_d2', ARRAY[900301], 'requiere_revision', '')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'marking requires a reason', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_mark('zz_d2', ARRAY[900301], 'requiere_revision', 'Woo vende "cualquier color": no se sabe qué color sale. Bloqueada para cutover.')$q$);
  PERFORM pg_temp.ok(pg_temp.st(900301) = 'requiere_revision' AND (SELECT human_locked FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900301),
    'Carolina marks the any-colour variation "requiere revisión" (locked, blocked for cutover)', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d2', ARRAY[900302], NULL, 'ZZ Mules', 'sandalia-plana', 'Verde', NULL)$q$);
  pid2 := (r->>'product_id')::uuid;
  SELECT confirmed_variant_id INTO v_verde37 FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900302;
  PERFORM pg_temp.ok(pid2 IS NOT NULL AND v_verde37 IS NOT NULL, 'the coloured variation of the same Woo product is confirmed separately', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_reopen('zz_d2', ARRAY[900202], ' ')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'reopening requires a reason', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_reopen('zz_d2', ARRAY[900202], 'Era talla 38, no 37')$q$);
  PERFORM pg_temp.ok(pg_temp.st(900202) = 'requiere_revision' AND (SELECT confirmed_variant_id IS NULL AND human_locked FROM f360.legacy_woo_map WHERE target_id = tgt AND woo_variation_id = 900202)
    AND EXISTS (SELECT 1 FROM f360.legacy_woo_map_log WHERE target_id = tgt AND woo_variation_id = 900202 AND action = 'reopen'),
    'reopen → requiere revisión, still human-locked, logged; catalog rows are kept', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_homologation('zz_d2')$q$);
  PERFORM pg_temp.ok((r->'summary'->>'variations')::int = 7 AND (r->'summary'->>'woo_products')::int = 4 AND (r->'summary'->>'confirmado')::int = 4
    AND (r->'summary'->>'models_confirmed')::int = 2 AND (r->'summary'->>'coverage_pct')::numeric = 57.1 AND jsonb_array_length(r->'rows') = 7,
    'summary: 7 variations, 4 Woo products, 4 confirmed, 2 F360 models, 57.1 % coverage', r->>'summary');

  -- ── where each confirmed colour comes from in the store (photos / price / description import) ──
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_sources(%L)$q$, pid));
  PERFORM pg_temp.ok(jsonb_array_length(r) = 2 AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'color' = 'Nude' AND (x->>'woo_product_id')::int = 9001 AND (x->>'variations')::int = 2)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'color' = 'Negro' AND (x->>'woo_product_id')::int = 9002 AND (x->>'variations')::int = 1),
    'legacy sources: ZZ Paula Nude ← Woo 9001 (2 sizes), Negro ← Woo 9002 (1 size after the reopen)', r::text);
  r := pg_temp.as(sel, format($q$SELECT public.f360_legacy_sources(%L)$q$, pid));
  PERFORM pg_temp.ok(r ? 'error', 'a seller cannot read legacy sources', r::text);
  PERFORM pg_temp.ok(jsonb_array_length(pg_temp.as(car, format($q$SELECT public.f360_legacy_sources(%L)$q$, mac))) = 0, 'an F360-published model (Macarena) has no legacy sources', '');

  -- ── legacy channel links (D4 will create them; here only the rules) ──
  BEGIN INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id) VALUES (tgt, v_nude35, 900401, 'legacy_adopted', 9004); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%homologación confirmada%', 'a legacy link that does not match a human confirmation is refused', err);
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id) VALUES (tgt, v_nude35, 900101, 'legacy_adopted', 9001);
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, origin, woo_product_id) VALUES (tgt, v_verde37, 900302, 'legacy_adopted', 9003);
  PERFORM pg_temp.ok(true, 'legacy links from confirmed rows accepted (Paula Nude 35 → 900101; Mules Verde 37 → 900302)', '');
  BEGIN INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id) VALUES ((SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4'), v_nude35, 999999); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%catálogo Woo anterior%', 'an F360-published link can never point at an adopted variant', err);
  BEGIN INSERT INTO f360.sync_jobs (target_id, product_id, idempotency_key, requested_by_name) VALUES (tgt, pid, gen_random_uuid(), 'test'); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se publica como producto nuevo%', 'the F360 publisher refuses a legacy model (no duplicate Woo product)', err);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_reopen('zz_d2', ARRAY[900101], 'prueba')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%ligada al canal%', 'a linked variation cannot be reopened in homologation', r::text);

  -- ── order ingestion: legacy resolved by variation_id, NOT by SKU equality ──
  INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) VALUES (v_nude35, bodega, 2)
    ON CONFLICT (variant_id, location_id) DO UPDATE SET on_hand = 2;
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-1","topic":"order.created"}',
    pg_temp.order_json(99000001, '[{"id":1,"product_id":9001,"variation_id":900101,"sku":"BALL-PAULA-NDE","quantity":1}]'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_nude35 AND location_id = bodega) = 1
    AND (SELECT count(*) FROM f360.inventory_events WHERE business_reference_id = 'zz_d2:99000001' AND event_type = 'SALE') = 1,
    'legacy order (Woo SKU BALL-PAULA-NDE ≠ F360 SKU) → resolved by variation_id: SALE, Bodega 2 → 1', r::text);
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-1","topic":"order.created"}',
    pg_temp.order_json(99000001, '[{"id":1,"product_id":9001,"variation_id":900101,"sku":"BALL-PAULA-NDE","quantity":1}]'));
  PERFORM pg_temp.ok(r->>'result' = 'duplicate_delivery' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_nude35 AND location_id = bodega) = 1,
    'replayed delivery → duplicate, no second discount', r::text);
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-2","topic":"order.created"}',
    pg_temp.order_json(99000002, '[{"id":1,"product_id":9001,"variation_id":900101,"quantity":1}]'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_nude35 AND location_id = bodega) = 0,
    'legacy order line with NO SKU at all → still resolved by variation_id (Bodega 1 → 0)', r::text);
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-3","topic":"order.created"}',
    pg_temp.order_json(99000003, '[{"id":1,"product_id":9001,"variation_id":900101,"quantity":1}]'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'oversold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v_nude35 AND location_id = bodega) = 0,
    'count 0 means 0: a further sale is "oversold", never negative', r::text);
  SELECT count(*) INTO n FROM f360.sync_exceptions WHERE target_id = tgt AND kind = 'unknown_sku';
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-4","topic":"order.created"}',
    pg_temp.order_json(99000004, '[{"id":1,"product_id":9003,"variation_id":900301,"quantity":1}]'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'unknown_sku' AND (SELECT count(*) FROM f360.sync_exceptions WHERE target_id = tgt AND kind = 'unknown_sku') = n + 1,
    'sale of a NOT adopted variation (any-colour) of an adopted Woo product → visible alert, nothing discounted', r::text);
  r := public.f360_ingest_woo_order('zz_d2', '{"delivery_id":"zz-d2-5","topic":"order.created"}',
    pg_temp.order_json(99000005, '[{"id":1,"product_id":9999,"variation_id":999901,"sku":"BALL-OTRO","quantity":1}]'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'legacy', 'a Woo product F360 never adopted stays "legacy" (ignored, as today)', r::text);
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-d2-6","topic":"order.created"}',
    pg_temp.order_json(99000006, jsonb_build_array(jsonb_build_object('id', 1, 'product_id', (SELECT woo_product_id FROM f360.woo_product_links pl JOIN f360.sales_targets t ON t.id = pl.target_id AND t.key = 'woo_staging4' WHERE pl.product_id = mac),
      'variation_id', (SELECT vl.woo_variation_id FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id AND t.key = 'woo_staging4' JOIN f360.product_variants v ON v.id = vl.variant_id WHERE v.sku = 'F360-MACARENA-NUDE-37'),
      'sku', 'F360-MACARENA-OTRO', 'quantity', 1))));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sku_mismatch', 'F360-published products keep the SKU check (Macarena with a wrong SKU → sku_mismatch)', r::text);

  -- ── stock push claim + reconciliation see the legacy parent from the variant link ──
  snap := public.f360_reconcile_snapshot('zz_d2');
  PERFORM pg_temp.ok(jsonb_array_length(snap) = 2 AND EXISTS (SELECT 1 FROM jsonb_array_elements(snap) x WHERE (x->>'woo_variation_id')::int = 900101 AND (x->>'woo_product_id')::int = 9001 AND (x->>'ats')::int = 0),
    'reconciliation includes adopted variants with their Woo parent (Paula nude 9001, ATS 0)', snap::text);
  UPDATE f360.stock_sync_queue SET next_attempt_at = now() - interval '1 minute', claimed_at = NULL WHERE target_id = tgt;
  r := public.f360_sync_claim_stock('zz_d2', 10);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE (x->>'woo_variation_id')::int = 900101 AND (x->>'woo_product_id')::int = 9001 AND (x->>'ats')::int = 0),
    'stock push claim carries the legacy parent and ATS 0 (Woo would show it sold out, P3)', r::text);
  PERFORM pg_temp.ok(jsonb_array_length(public.f360_reconcile_snapshot('woo_staging4')) = 18, 'woo_staging4 (Macarena, F360-published) reconciliation unchanged: 18 variants', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
