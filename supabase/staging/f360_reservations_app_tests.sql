-- Apartado Gold in the seller app (phase 4) — database tests (STAGING). One transaction, ROLLED BACK.
-- Own stores "ZZ App Tienda" (seller S1) and "ZZ App Otra" (seller S3); lab customer C1 made Gold here.
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
  PERFORM set_config('f360.sale_customer', '', true);
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS c1 FROM public.customers WHERE phone = '+15550100011' \gset
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT id AS s3 FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.s1', :'s1', true), set_config('t.s3', :'s3', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; s1 uuid := current_setting('t.s1')::uuid;
  s3 uuid := current_setting('t.s3')::uuid; r jsonb; loc uuid; loc2 uuid; pid uuid; v uuid; tok text; tok3 text; res1 uuid; qr1 text; c1cust uuid; n int;
BEGIN
  SELECT id INTO c1cust FROM public.customers WHERE auth_user_id = c1;
  UPDATE public.loyalty_cards SET tier = 'gold' WHERE customer_id = c1cust;
  SELECT qr_code INTO qr1 FROM public.loyalty_cards WHERE customer_id = c1cust LIMIT 1;
  loc := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ App Tienda', 'store')$q$)->>'id')::uuid;
  loc2 := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ App Otra', 'store')$q$)->>'id')::uuid;
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ App Modelo', ARRAY['36'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  UPDATE f360.products SET regular_price = 2800 WHERE id = pid;
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2}]')$q$, loc, v));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, loc2, v));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora Uno')$q$, s1));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, s1, loc));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_seller_pin(%L, '2468')$q$, s1));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora Otra')$q$, s3));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, s3, loc2));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_seller_pin(%L, '1357')$q$, s3));
  tok := pg_temp.as(s1, format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, loc))->>'token';
  tok3 := pg_temp.as(s3, format($q$SELECT public.f360_start_seller_shift(%L, '1357')$q$, loc2))->>'token';
  PERFORM pg_temp.ok(tok IS NOT NULL AND tok3 IS NOT NULL AND qr1 IS NOT NULL, 'fixtures: two stores, one seller each with a shift open, Gold customer', '');

  -- 1 · reserving notifies the store's team, and only that team
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v));
  res1 := (r->>'id')::uuid;
  SELECT count(*) INTO n FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text;
  PERFORM pg_temp.ok(res1 IS NOT NULL AND n = 1 AND EXISTS (SELECT 1 FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text AND auth_user_id = s1),
    'a reservation queues ONE notice, for the seller of that store', n::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text AND auth_user_id = s3),
    'the seller of another store is not notified', '');
  SELECT body INTO r FROM (SELECT to_jsonb(body) AS body FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text) x;
  PERFORM pg_temp.ok(r::text LIKE '%Separa ZZ App Modelo Negro 36 para %hasta las %m.%' AND r::text NOT LIKE '%+1555%',
    'notice says what to separate, for whom (first name) and until when; no phone', r::text);

  -- 2 · the outbox is private; the sender is service-only
  r := pg_temp.as(s1, $q$SELECT to_jsonb(count(*)) FROM f360.push_outbox$q$);
  PERFORM pg_temp.ok(r ? 'error', 'sellers cannot read the outbox', r::text);
  r := pg_temp.as(s1, $q$SELECT public.f360_push_claim(10)$q$);
  PERFORM pg_temp.ok(r ? 'error', 'only the service can claim notices', r::text);
  r := public.f360_push_claim(500);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'id' = (SELECT id::text FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text) AND jsonb_typeof(x->'tokens') = 'array'),
    'service claims the notice with the seller''s device tokens', left(r::text, 100));
  PERFORM public.f360_push_result(jsonb_build_array(jsonb_build_object('id', (SELECT id FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text), 'done', true, 'result', 'ok 1')));
  PERFORM pg_temp.ok((SELECT sent_at IS NOT NULL AND attempts = 1 FROM f360.push_outbox WHERE data->>'reservation_id' = res1::text), 'result recorded: sent once', '');
  r := public.f360_push_claim(500);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->'data'->>'reservation_id' = res1::text), 'a sent notice is never sent again', '');

  -- 3 · the seller sees her store's reservations (location from the shift), not the other store's
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_reservations(%L)$q$, tok));
  PERFORM pg_temp.ok(jsonb_array_length(r) = 1 AND r->0->>'id' = res1::text AND r->0->>'status' = 'activa' AND r->0->>'size' = '36'
    AND r->0 ? 'phone_last4' AND NOT (r->0 ? 'phone') AND r::text NOT LIKE '%+1555%', 'seller lists the active reservation of her store (first name + last 4 only)', left(r::text, 120));
  r := pg_temp.as(s3, format($q$SELECT public.f360_shift_reservations(%L)$q$, tok3));
  PERFORM pg_temp.ok(jsonb_array_length(r) = 0, 'the other store''s seller does not see it', r::text);
  r := pg_temp.as(s3, format($q$SELECT public.f360_shift_reservations(%L)$q$, tok));
  PERFORM pg_temp.ok(r ? 'error', 'someone else''s shift token is refused', r::text);

  -- 4 · "Ya lo separé": only her store, idempotent, does not move inventory
  r := pg_temp.as(s3, format($q$SELECT public.f360_shift_reservation_separate(%L, %L)$q$, tok3, res1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no es de tu tienda%', 'another store cannot mark it separated', r::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_reservation_separate(%L, %L)$q$, tok, res1));
  PERFORM pg_temp.ok(r->>'separated_by' = 'ZZ Vendedora Uno' AND (SELECT on_hand FROM f360.inventory_balances WHERE location_id = loc AND variant_id = v) = 2,
    'seller marks "Ya lo separé" (her name); inventory unchanged', r::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_reservation_separate(%L, %L)$q$, tok, res1));
  PERFORM pg_temp.ok(r->>'separated_by' = 'ZZ Vendedora Uno', 'marking twice is harmless', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_reservations(%L)$q$, loc));
  PERFORM pg_temp.ok(r->0->>'separated_by' = 'ZZ Vendedora Uno', 'admin Apartados shows who separated it', left(r::text, 80));

  -- 5 · catalog shows reserved pairs; the store sale to someone else respects them, to her closes the reservation
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_catalog(%L)$q$, tok));
  PERFORM pg_temp.ok((SELECT (x->>'available')::int = 2 AND (x->>'reserved')::int = 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'variant_id' = v::text),
    'shift catalog: 2 on hand, 1 reserved', left(r::text, 160));
  r := pg_temp.as(s1, format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"variant_id":"%s","quantity":2}]', 'cash')$q$, tok, v));
  PERFORM pg_temp.ok(r->>'error' LIKE '%apartado para otra clienta%', 'selling both pairs without her card is refused', r::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"variant_id":"%s","quantity":1}]', 'card', NULL, %L)$q$, tok, v, qr1));
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND (SELECT status FROM f360.reservations WHERE id = res1) = 'vendida', 'selling to her (card QR) closes her reservation as vendida', r::text);
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_reservations(%L)$q$, tok));
  PERFORM pg_temp.ok(r->0->>'status' = 'vendida', 'the seller''s list shows it as sold (history of the day)', left(r::text, 80));
  r := pg_temp.as(s1, format($q$SELECT public.f360_shift_reservation_separate(%L, %L)$q$, tok, res1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya no está activo%', 'a closed reservation cannot be marked', r::text);

  -- 6 · a store with nobody assigned queues nothing (and the reservation still works)
  PERFORM pg_temp.as(s3, format($q$SELECT public.f360_end_seller_shift(%L)$q$, tok3));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_location_assignment(%L, %L, false)$q$, s3, loc2));
  UPDATE public.loyalty_cards SET tier = 'gold' WHERE customer_id = c1cust;                -- the sale above recalculated her tier
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc2, v));
  PERFORM pg_temp.ok(r ? 'id' AND NOT EXISTS (SELECT 1 FROM f360.push_outbox WHERE data->>'reservation_id' = r->>'id'),
    'no team at the store → reservation OK, no notice queued', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
