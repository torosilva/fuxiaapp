-- Track D · D4 — store visibility requests, opening load from an approved count, channel link / unlink — tests (STAGING).
-- One transaction, ROLLED BACK. Own channel "zz_d4" and location "ZZ D4 Bodega".
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
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'operator', 'ZZ Operación', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator' RETURNING auth_user_id AS op \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.mario', :'mario', true), set_config('t.op', :'op', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; mar uuid := current_setting('t.mario')::uuid; op uuid := current_setting('t.op')::uuid;
  r jsonb; loc uuid; tgt uuid; cid uuid; pid uuid; v36 uuid; v37 uuid; k uuid := gen_random_uuid(); cl jsonb;
BEGIN
  loc := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ D4 Bodega', 'warehouse')$q$)->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_d4', 'ZZ D4', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_d4', '[{"woo_variation_id":981036,"woo_product_id":9810,"woo_product_name":"ZZ D4 negro","woo_size":"36"},
    {"woo_variation_id":981037,"woo_product_id":9810,"woo_product_name":"ZZ D4 negro","woo_size":"37"},
    {"woo_variation_id":981136,"woo_product_id":9811,"woo_product_name":"ZZ D4 ya no existe","woo_size":"36"},
    {"woo_variation_id":981236,"woo_product_id":9812,"woo_product_name":"ZZ D4 pendiente","woo_size":"36"}]');
  pid := (pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d4', ARRAY[981036, 981037], NULL, 'ZZ D4 Modelo', 'ballerinas', 'Negro', NULL)$q$)->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  PERFORM pg_temp.as(car, $q$SELECT public.f360_legacy_mark('zz_d4', ARRAY[981136], 'sin_correspondencia', 'No existe')$q$);

  -- ── store visibility: only what Carolina decided "no existe" ──
  r := pg_temp.as(car, $q$SELECT public.f360_store_visibility_request('zz_d4', 9812, 'ocultar', 'prueba')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo se ocultan productos que se marcaron%', 'a product without the "no existe" decision cannot be hidden', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_store_visibility_request('zz_d4', 9810, 'ocultar', 'prueba')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'a confirmed (adopted) product cannot be hidden', r::text);
  r := pg_temp.as(op, $q$SELECT public.f360_store_visibility_request('zz_d4', 9811, 'ocultar', 'No existe físicamente')$q$);
  PERFORM pg_temp.ok(r->>'pending' = 'ocultar', 'Carolina''s "no existe" product: hide request queued', r::text);
  r := pg_temp.as(op, $q$SELECT public.f360_store_visibility_request('zz_d4', 9811, 'ocultar', 'otra vez')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE 'Ya hay una solicitud pendiente%', 'no duplicate pending request', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_visibility_claim('zz_d4')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'only the worker (service_role) claims requests', r::text);
  cl := public.f360_visibility_claim('zz_d4');
  PERFORM pg_temp.ok(jsonb_array_length(cl) = 1 AND (cl->0->>'woo_product_id')::int = 9811 AND cl->0->>'kind' = 'ocultar', 'worker claims the hide request', cl::text);
  r := public.f360_visibility_result('zz_d4', jsonb_build_array(jsonb_build_object('id', cl->0->>'id', 'ok', true, 'before', 'publish', 'after', 'private')));
  PERFORM pg_temp.ok((SELECT status || '|' || woo_status_before FROM f360.woo_visibility_requests WHERE target_id = tgt) = 'hecho|publish', 'result recorded with the previous Woo status', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_store_visibility_request('zz_d4', 9811, 'mostrar', 'Sí existe, error')$q$);
  cl := public.f360_visibility_claim('zz_d4');
  PERFORM pg_temp.ok(cl->0->>'kind' = 'mostrar' AND cl->0->>'restore_status' = 'publish', 'show again restores the previous status (publish)', cl::text);

  -- ── rehearsal: link one model without the full count (staging) ──
  r := pg_temp.as(op, format($q$SELECT public.f360_legacy_link_products('zz_d4', ARRAY[%L]::uuid[], 'ensayo')$q$, pid));
  PERFORM pg_temp.ok(r ? 'error', 'an operator cannot link models', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_link_products('zz_d4', ARRAY[%L]::uuid[], ' ')$q$, pid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%motivo%', 'a rehearsal link needs a reason', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_link_products('zz_d4', ARRAY[%L]::uuid[], 'Ensayo: ver Botas en staging4')$q$, pid));
  PERFORM pg_temp.ok((r->>'linked')::int = 2 AND (SELECT count(*) FROM f360.stock_sync_queue WHERE target_id = tgt) = 2, 'rehearsal: one model linked (2 sizes) and queued for a push', r::text);
  PERFORM pg_temp.as(car, $q$SELECT public.f360_legacy_unlink_channel('zz_d4', 'fin del ensayo por modelo')$q$);

  -- ── opening load ──
  cid := (pg_temp.as(car, $q$SELECT public.f360_opening_start('zz_d4')$q$)->'count'->>'id')::uuid;
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":2},{"variant_id":"%s","qty":0}]')$q$, cid, v36, v37));
  PERFORM pg_temp.as(mar, format($q$SELECT public.f360_opening_record(%L, '2', '[{"variant_id":"%s","qty":2},{"variant_id":"%s","qty":0}]')$q$, cid, v36, v37));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_load(%L, %L)$q$, cid, k));
  PERFORM pg_temp.ok(r->>'error' LIKE 'Solo se carga un conteo aprobado%', 'only an approved count can be loaded', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_link_channel('zz_d4')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE 'Primero se carga el saldo inicial%', 'the channel cannot be linked before the opening is loaded', r::text);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_freeze(%L)$q$, cid));
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_reconcile(%L)$q$, cid));
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_approve(%L, 'Ensayo D4')$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'aprobado', 'fixture: count approved by Mario (36 = 2, 37 = 0)', r::text);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_load(%L, %L)$q$, cid, k));
  PERFORM pg_temp.ok(r ? 'error', 'an operator cannot load the opening balance', r::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_load(%L, %L)$q$, cid, k));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'cargado' AND (r->>'loaded_pairs')::int = 2
    AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v36 AND location_id = loc) = 2
    AND NOT EXISTS (SELECT 1 FROM f360.inventory_balances WHERE variant_id = v37 AND location_id = loc AND on_hand <> 0)
    AND (SELECT event_type FROM f360.inventory_events WHERE id = (SELECT load_event_id FROM f360.opening_counts WHERE id = cid)) = 'OPENING_PHYSICAL_COUNT'
    AND NOT f360.location_in_cutover(loc),
    'Mario loads: one OPENING event, 36 → 2 pairs, 37 stays 0; the freeze ends', r::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_load(%L, %L)$q$, cid, k));
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v36 AND location_id = loc) = 2, 'same key → replayed, loaded once', r::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_load(%L, gen_random_uuid())$q$, cid));
  PERFORM pg_temp.ok(r ? 'error', 'a loaded count cannot be loaded again', r::text);

  -- ── link the channel + stock push queued for every adopted size (0 → "agotado") ──
  r := pg_temp.as(op, $q$SELECT public.f360_legacy_link_channel('zz_d4')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'an operator cannot link the channel', r::text);
  r := pg_temp.as(mar, $q$SELECT public.f360_legacy_link_channel('zz_d4')$q$);
  PERFORM pg_temp.ok((r->>'linked')::int = 2 AND (SELECT count(*) FROM f360.stock_sync_queue WHERE target_id = tgt) = 2
    AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE target_id = tgt AND woo_variation_id IN (981136, 981236)),
    'link: only confirmed sizes (2) linked and queued; "no existe" / pending ones are not linked', r::text);
  cl := public.f360_sync_claim_stock('zz_d4', 10);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(cl) x WHERE (x->>'woo_variation_id')::int = 981036 AND (x->>'ats')::int = 2 AND (x->>'woo_product_id')::int = 9810)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(cl) x WHERE (x->>'woo_variation_id')::int = 981037 AND (x->>'ats')::int = 0),
    'push carries 36 → 2 and 37 → 0 (Woo will show it sold out)', cl::text);
  r := public.f360_ingest_woo_order('zz_d4', '{"delivery_id":"zz-d4-1","topic":"order.created"}',
    jsonb_build_object('id', 9981001, 'status', 'processing', 'date_modified_gmt', '2026-10-02T12:00:00', 'currency', 'MXN', 'refunds', '[]'::jsonb,
      'line_items', '[{"id":1,"product_id":9810,"variation_id":981036,"sku":"BALL-X","quantity":1}]'::jsonb));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v36 AND location_id = loc) = 1,
    'a store order after the link discounts the counted stock (2 → 1)', r::text);
  r := pg_temp.as(mar, $q$SELECT public.f360_legacy_channel_state('zz_d4')$q$);
  PERFORM pg_temp.ok((r->>'links')::int = 2 AND (r->>'opening_loaded')::boolean, 'channel state: 2 links, opening loaded', r::text);
  r := pg_temp.as(mar, $q$SELECT public.f360_legacy_unlink_channel('zz_d4', 'Ensayo terminado')$q$);
  PERFORM pg_temp.ok((r->>'unlinked')::int = 2 AND NOT EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE target_id = tgt),
    'rehearsal rollback: links removed (inventory history stays)', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
