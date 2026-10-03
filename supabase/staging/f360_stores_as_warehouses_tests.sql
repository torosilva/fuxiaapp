-- Stores are warehouses too (Mario 2026-10-03) — database tests (STAGING). One transaction, ROLLED BACK.
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
SELECT auth_user_id AS c1 FROM public.customers WHERE phone = '+15550100011' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; r jsonb; tid uuid; bodega uuid; tienda uuid; pid uuid; v uuid; ev int;
  ord jsonb;
BEGIN
  SELECT id, fulfillment_location_id INTO tid, bodega FROM f360.sales_targets WHERE key = 'woo_staging4';
  tienda := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Bodega Tienda', 'store')$q$)->>'id')::uuid;
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Online Modelo', ARRAY['36'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  UPDATE f360.products SET regular_price = 2800 WHERE id = pid;
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pid;
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id, last_pushed_stock) VALUES (tid, v, 991036, 0);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, bodega, v));
  DELETE FROM f360.stock_sync_queue WHERE variant_id = v;
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2}]')$q$, tienda, v));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v AND target_id = tid), 'a receipt in a STORE re-sends the size online', '');
  PERFORM pg_temp.ok(f360.online_ats(v, bodega) = 3, 'online stock = Bodega 1 + store 2 = 3', f360.online_ats(v, bodega)::text);

  -- a Gold reservation in the store lowers what is online
  UPDATE public.loyalty_cards SET tier = 'gold' WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1);
  DELETE FROM f360.stock_sync_queue WHERE variant_id = v;
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, tienda, v));
  PERFORM pg_temp.ok(r ? 'id' AND f360.online_ats(v, bodega) = 2 AND EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v), 'Gold reservation → online 2 and re-sent', r::text);

  -- order 1: Bodega has it → sold from Bodega (as before)
  ord := jsonb_build_object('id', 991000001, 'status', 'processing', 'date_modified_gmt', '2026-10-03T20:00:00', 'currency', 'MXN',
           'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', 991000, 'variation_id', 991036, 'quantity', 1, 'sku', (SELECT sku FROM f360.product_variants WHERE id = v))), 'refunds', '[]'::jsonb);
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-sw-1","topic":"order.created"}', ord);
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = bodega) = 0
    AND NOT EXISTS (SELECT 1 FROM f360.online_store_shipments WHERE woo_order_id = 991000001), 'Bodega has it → sold from Bodega, no store shipment', r::text);
  -- order 2: Bodega 0 → the store ships its FREE pair (the reserved one is untouched)
  SELECT count(*) INTO ev FROM f360.push_outbox;
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-sw-2","topic":"order.created"}', jsonb_set(ord, '{id}', '991000002'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sold' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = tienda) = 1
    AND EXISTS (SELECT 1 FROM f360.online_store_shipments WHERE woo_order_id = 991000002 AND location_id = tienda AND status = 'por_enviar'),
    'Bodega 0 → sold from the store, shipment "por enviar"', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.reservations WHERE variant_id = v AND status = 'activa') = 1, 'the Gold-reserved pair is still held', '');
  -- order 3: only the reserved pair is left → not taken; becomes 5–7 días
  r := public.f360_ingest_woo_order('woo_staging4', '{"delivery_id":"zz-sw-3","topic":"order.created"}', jsonb_set(ord, '{id}', '991000003'));
  PERFORM pg_temp.ok(r->'lines'->0->>'outcome' = 'sobre_pedido' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = tienda) = 1,
    'only a reserved pair left → never taken; 5–7 días', r::text);
  -- team list + "ya se envió"
  r := pg_temp.as(car, $q$SELECT public.f360_online_store_shipments()$q$);
  PERFORM pg_temp.ok(r->0->>'store' = 'ZZ Bodega Tienda' AND r->0->>'status' = 'por_enviar', 'team sees what the store must ship', left(r::text, 120));
  r := pg_temp.as(car, format($q$SELECT public.f360_online_store_shipment_sent(%L)$q$, r->0->>'id'));
  PERFORM pg_temp.ok(r->>'status' = 'enviado', 'marked as shipped', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_online_store_shipments()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot see shipments', r::text);
  -- bazaars are not online stock
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.online_store_locations() x JOIN f360.locations l ON l.id = x WHERE l.type <> 'store'), 'only stores count (no bazaars, no warehouses besides Bodega)', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
