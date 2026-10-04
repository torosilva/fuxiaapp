-- CRO-5a · Guard de inventario certificado — database tests (STAGING). One transaction, ROLLED BACK.
-- Fixture: the staging4 target (fulfillment Bodega CDMX); the real online stores are taken out of the online set for the
-- test (sellable = false, rolled back) and two own stores "ZZ Cert A/B" are used. Certification evidence is inserted the
-- way the real flows write it (OPENING_PHYSICAL_COUNT event; opening count 'cargado' with its lines).
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
-- evidence as the real flows write it
CREATE FUNCTION pg_temp.cutover_ok(p_loc uuid) RETURNS void LANGUAGE sql AS $$
  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_name, actor_role, note, business_reference_type, business_reference_id)
  VALUES ('OPENING_PHYSICAL_COUNT', gen_random_uuid(), 'Prueba', 'owner', 'test cutover', 'location_cutover', p_loc::text) $$;
CREATE FUNCTION pg_temp.opening_loaded(p_loc uuid, p_variants uuid[], p_out uuid[] DEFAULT '{}') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ev uuid; c uuid;
BEGIN
  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_name, actor_role, note, business_reference_type, business_reference_id)
    VALUES ('OPENING_PHYSICAL_COUNT', gen_random_uuid(), 'Prueba', 'owner', 'test opening', 'opening_count', p_loc::text) RETURNING id INTO ev;
  INSERT INTO f360.opening_counts (target_id, location_id, status, started_by_name, loaded_by_name, loaded_at, load_event_id)
    VALUES ((SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4'), p_loc, 'cargado', 'Prueba', 'Prueba', now() - interval '1 minute', ev) RETURNING id INTO c;
  INSERT INTO f360.opening_count_lines (count_id, variant_id, in_scope, final_qty) SELECT c, x, true, 0 FROM unnest(p_variants) x;
  INSERT INTO f360.opening_count_lines (count_id, variant_id, in_scope, final_qty) SELECT c, x, false, 0 FROM unnest(p_out) x;
  RETURN c;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; r jsonb; tid uuid; bodega uuid; a uuid; b uuid; baz uuid; pid uuid; v uuid; v2 uuid; ats_before int;
  mto_before boolean; res_before int; queue_before int; orders_before int; ats0 int;
BEGIN
  SELECT id, fulfillment_location_id INTO tid, bodega FROM f360.sales_targets WHERE key = 'woo_staging4';
  -- isolate: only our two stores are online for this test
  UPDATE f360.locations SET sellable = false WHERE id IN (SELECT f360.online_store_locations());
  a := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Cert A', 'store')$q$)->>'id')::uuid;
  b := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Cert B', 'store')$q$)->>'id')::uuid;
  baz := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Cert Bazar', 'bazaar')$q$)->>'id')::uuid;
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Cert Modelo', ARRAY['36','37'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v2 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  UPDATE f360.product_variants SET created_at = now() - interval '30 days' WHERE product_id = pid;   -- sizes that existed before any count
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, last_pushed_stock) VALUES (tid, v, 992036, 0);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, a, v));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, b, v));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":5}]')$q$, baz, v));
  PERFORM pg_temp.ok(f360.online_ats(v, bodega) = 2 AND (SELECT count(*) FROM f360.online_ats_locations(bodega)) = 3,
    'fixture: online set = Bodega + ZZ Cert A + ZZ Cert B; ATS = 2 (bazaar not counted)', f360.online_ats(v, bodega)::text);
  ats_before := f360.online_ats(v, bodega);
  mto_before := (SELECT make_to_order FROM f360.products WHERE id = pid);
  res_before := (SELECT count(*) FROM f360.reservations); queue_before := (SELECT count(*) FROM f360.stock_sync_queue);
  orders_before := (SELECT count(*) FROM f360.woo_order_lines);

  -- 1 · nothing certified
  PERFORM pg_temp.ok(NOT f360.online_scarcity_reliable(v, bodega), 'no location certified → not reliable', '');
  r := pg_temp.as(NULL, $q$SELECT public.f360_scarcity_state(992036)$q$, 'anon');
  PERFORM pg_temp.ok(r = '{"reliable": false}'::jsonb, 'store page (anon) gets only {reliable:false} — no quantities, no locations', r::text);

  -- 2 · Bodega certified (variant in scope) + A certified, B not → not reliable
  PERFORM pg_temp.opening_loaded(bodega, ARRAY[v]);
  PERFORM pg_temp.cutover_ok(a);
  PERFORM pg_temp.ok(f360.variant_inventory_certified(v, bodega) AND f360.variant_inventory_certified(v, a) AND NOT f360.variant_inventory_certified(v, b),
    'evidence read correctly: Bodega (opening count, in scope), A (cutover), B none', '');
  PERFORM pg_temp.ok(NOT f360.online_scarcity_reliable(v, bodega), 'one eligible location (B) uncertified → not reliable', '');

  -- 3 · all certified → reliable; ATS 2
  PERFORM pg_temp.cutover_ok(b);
  PERFORM pg_temp.ok(f360.online_scarcity_reliable(v, bodega) AND f360.online_ats(v, bodega) = 2, 'all eligible certified → reliable (ATS = 2)', '');
  r := pg_temp.as(NULL, $q$SELECT public.f360_scarcity_state(992036)$q$, 'anon');
  PERFORM pg_temp.ok(r = '{"reliable": true}'::jsonb, 'store page gets {reliable:true}', r::text);
  PERFORM pg_temp.ok(NOT f360.variant_inventory_certified(v, baz), 'the uncertified bazaar does not matter (not eligible)', '');

  -- 4 · ATS = 1 (a pair leaves B) → still reliable (reliability is about evidence, not quantity)
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1}]', 'prueba')$q$, b, v));
  PERFORM pg_temp.ok(f360.online_ats(v, bodega) = 1 AND f360.online_scarcity_reliable(v, bodega), 'ATS = 1 and all certified → reliable', f360.online_ats(v, bodega)::text);

  -- 5 · MTO on / off does not change reliability (nor MTO itself)
  UPDATE f360.products SET make_to_order = false WHERE id = pid;
  PERFORM pg_temp.ok(f360.online_scarcity_reliable(v, bodega), 'MTO off → same reliability', '');
  UPDATE f360.products SET make_to_order = true WHERE id = pid;
  PERFORM pg_temp.ok(f360.online_scarcity_reliable(v, bodega), 'MTO on → same reliability', '');

  -- 6 · scope rules of an opening count
  PERFORM pg_temp.ok(NOT f360.variant_inventory_certified(v2, bodega), 'a size that existed but was not in the Bodega count → not certified there', '');
  PERFORM pg_temp.ok(NOT f360.online_scarcity_reliable(v2, bodega), '… so that size is not reliable online', '');
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Cert Nuevo', ARRAY['38'], '[{"name":"Rojo"}]'::jsonb)$q$)->>'id')::uuid;
  PERFORM pg_temp.ok(f360.variant_inventory_certified((SELECT id FROM f360.product_variants WHERE product_id = pid), bodega),
    'a size created after the count was loaded → certified (its stock was born recorded)', '');

  -- 7 · nothing else changed
  PERFORM pg_temp.ok(f360.online_ats(v, bodega) = ats_before - 1 AND (SELECT make_to_order FROM f360.products WHERE id = (SELECT product_id FROM f360.product_variants WHERE id = v)) = mto_before,
    'ATS only moved by the test adjustment; MTO unchanged', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.reservations) = res_before AND (SELECT count(*) FROM f360.woo_order_lines) = orders_before,
    'Gold reservations and Woo orders untouched by the guard', '');
  r := public.f360_sync_claim_stock('woo_staging4', 500);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x ? 'reliable' OR x ? 'certified'), 'Woo stock push payload unchanged (no new fields)', '');

  -- 8 · permissions
  r := pg_temp.as(NULL, $q$SELECT public.f360_inventory_certification()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot read the certification report', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_inventory_certification()$q$);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'name' = 'ZZ Cert A' AND x->>'certified' = 'true' AND x->>'via' = 'cutover'),
    'team report shows how each location is certified', left(r::text, 120));
  r := pg_temp.as(NULL, $q$SELECT public.f360_scarcity_state(999999999)$q$, 'anon');
  PERFORM pg_temp.ok(r = '{"reliable": false}'::jsonb, 'unknown variation → fail closed', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
