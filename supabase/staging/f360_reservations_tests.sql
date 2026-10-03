-- Entrega inmediata + Apartado Gold (phase 1) — database tests (STAGING). One transaction, ROLLED BACK.
-- Own store "ZZ Res Tienda"; lab customers C1 (made Gold here) and C2 (bronze); lab user S1 as the store's seller.
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
SELECT auth_user_id AS c2 FROM public.customers WHERE phone = '+15550100012' \gset
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.s1', :'s1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; c2 uuid := current_setting('t.c2')::uuid; s1 uuid := current_setting('t.s1')::uuid;
  r jsonb; loc uuid; pid uuid; v uuid; v2 uuid; tok text; res1 uuid; res2 uuid; qr1 text; ev uuid;
BEGIN
  UPDATE public.loyalty_cards SET tier = 'gold' WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1);
  SELECT qr_code INTO qr1 FROM public.loyalty_cards WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1) LIMIT 1;
  loc := (pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Res Tienda', 'store')$q$)->>'id')::uuid;
  pid := (pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Res Modelo', ARRAY['36','37'], '[{"name":"Negro"}]'::jsonb)$q$)->>'id')::uuid;
  UPDATE f360.products SET regular_price = 2800 WHERE id = pid;
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v2 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2},{"variant_id":"%s","quantity":1}]')$q$, loc, v, v2));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora Polanco')$q$, s1));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, s1, loc));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_seller_pin(%L, '2468')$q$, s1));
  tok := pg_temp.as(s1, format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, loc))->>'token';
  PERFORM pg_temp.ok(qr1 IS NOT NULL AND tok IS NOT NULL, 'fixtures: Gold customer C1 with card, store with 2 × Negro 36 and 1 × 37, seller shift open', '');

  -- Entrega inmediata (public: store names only)
  r := pg_temp.as(NULL, format($q$SELECT public.f360_store_availability(%L)$q$, v), 'anon');
  PERFORM pg_temp.ok(r->'stores' @> jsonb_build_array(jsonb_build_object('name', 'ZZ Res Tienda')) AND r::text NOT LIKE '%on_hand%',
    'anyone sees "entrega inmediata en ZZ Res Tienda" (no quantities)', r::text);
  r := pg_temp.as(NULL, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous visitors cannot reserve', r::text);

  -- Gold only, max 2 pairs open
  r := pg_temp.as(c2, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v));
  PERFORM pg_temp.ok(r->>'error' LIKE '%beneficio Fuxia Gold%', 'a non-Gold customer cannot reserve', r::text);
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v));
  res1 := (r->>'id')::uuid;
  PERFORM pg_temp.ok(res1 IS NOT NULL AND (r->>'expires_at')::timestamptz BETWEEN now() + interval '119 minutes' AND clock_timestamp() + interval '121 minutes',
    'Gold customer reserves Negro 36 for 2 hours', r::text);
  res2 := (pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v))->>'id')::uuid;
  r := pg_temp.as(NULL, format($q$SELECT public.f360_store_availability(%L)$q$, v), 'anon');
  PERFORM pg_temp.ok(res2 IS NOT NULL AND jsonb_array_length(r->'stores') = 0, 'both pairs of 36 reserved → no longer "entrega inmediata"', r::text);
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v2));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Ya tienes 2 pares apartados%', 'a third pair is refused (max 2 open)', r::text);
  PERFORM pg_temp.ok((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = loc) = 2, 'reserving moves no inventory (still 2 on hand)', '');

  -- the store cannot give a reserved pair to someone else; a transfer cannot take it either
  r := pg_temp.as(s1, format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"variant_id":"%s","quantity":1}]', 'cash')$q$, tok, v));
  PERFORM pg_temp.ok(r->>'error' LIKE '%apartado para otra clienta%', 'a sale without that customer is refused: the pair is reserved', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, loc, (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX'), v));
  IF r ? 'error' THEN
    PERFORM pg_temp.ok(false, 'transfer request fixture', r::text);
  ELSE
    r := pg_temp.as(car, format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, r->>'id'));
    PERFORM pg_temp.ok(r->>'error' LIKE '%apartado para una clienta Gold%', 'a transfer cannot take a reserved pair out of the store', r::text);
  END IF;

  -- the customer comes: sale with her card → her reservation becomes "vendida"
  r := pg_temp.as(s1, format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"variant_id":"%s","quantity":1}]', 'card', NULL, %L)$q$, tok, v, qr1));
  PERFORM pg_temp.ok(r->>'error' IS NULL AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = loc) = 1
    AND (SELECT count(*) FROM f360.reservations WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1) AND status = 'vendida') = 1
    AND (SELECT count(*) FROM f360.reservations WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1) AND status = 'activa') = 1,
    'Gold customer buys with her card: 1 reservation "vendida", 1 still active, stock 2 → 1', r::text);

  -- staff view (no full phone), customer cancels, expiry
  r := pg_temp.as(car, format($q$SELECT public.f360_reservations(%L)$q$, loc));
  PERFORM pg_temp.ok(jsonb_array_length(r) = 2 AND r->0->>'phone_last4' = '0011' AND r::text NOT LIKE '%+1555%', 'store team sees the reservations (phone: last 4 digits only)', r::text);
  r := pg_temp.as(c2, format($q$SELECT public.f360_reservation_cancel(%L)$q$, res2));
  PERFORM pg_temp.ok(r ? 'error' AND (SELECT status FROM f360.reservations WHERE id = res2) = 'activa', 'another customer cannot cancel it', r::text);
  r := pg_temp.as(c1, $q$SELECT public.f360_my_reservations()$q$);
  PERFORM pg_temp.ok(jsonb_array_length(r) = 2, 'the customer sees her reservations', r::text);
  UPDATE f360.reservations SET expires_at = clock_timestamp() - interval '1 second' WHERE status = 'activa' AND location_id = loc;
  r := pg_temp.as(NULL, format($q$SELECT public.f360_store_availability(%L)$q$, v), 'anon');
  PERFORM pg_temp.ok(jsonb_array_length(r->'stores') = 1, 'after 2 hours the pair is free again even before the job runs', r::text);
  PERFORM f360.expire_reservations();
  PERFORM pg_temp.ok((SELECT status FROM f360.reservations WHERE id IN (res1, res2) AND status <> 'vendida') = 'vencida',
    'the job marks it "vencida" (nothing else happens: Gold has no penalty)', '');
  r := pg_temp.as(s1, format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"variant_id":"%s","quantity":1}]', 'cash')$q$, tok, v));
  PERFORM pg_temp.ok(r->>'error' IS NULL AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = loc) = 0, 'expired: anyone can buy it again', r::text);
  -- the purchase above earned her points and the loyalty trigger recomputed her tier from the lab points: make her Gold again
  UPDATE public.loyalty_cards SET tier = 'gold' WHERE customer_id = (SELECT id FROM public.customers WHERE auth_user_id = c1);
  res1 := (pg_temp.as(c1, format($q$SELECT public.f360_reserve(%L, %L)$q$, loc, v2))->>'id')::uuid;
  r := pg_temp.as(c1, format($q$SELECT public.f360_reservation_cancel(%L, 'Ya no puedo ir')$q$, res1));
  PERFORM pg_temp.ok((SELECT status FROM f360.reservations WHERE id = res1) = 'cancelada', 'the customer cancels her own reservation', r::text);

  -- web: only the service (after WhatsApp code) can reserve by phone
  r := pg_temp.as(c1, format($q$SELECT public.f360_reserve_for_phone('+15550100011', %L, %L)$q$, loc, v2));
  PERFORM pg_temp.ok(r ? 'error', 'reserving by phone is service-only (after the WhatsApp code)', r::text);
  r := public.f360_reserve_for_phone('+15550100011', loc, v2);
  PERFORM pg_temp.ok(r->>'store' = 'ZZ Res Tienda' AND (SELECT channel FROM f360.reservations WHERE id = (r->>'id')::uuid) = 'web', 'service reserves for a verified phone (channel web)', r::text);
  -- web: Gold check before sending a code (service only; first name + boolean, nothing else)
  r := public.f360_gold_check('+15550100011');
  PERFORM pg_temp.ok(r->>'exists' = 'true' AND r->>'gold' = 'true' AND r ? 'first_name' AND NOT (r ? 'points'), 'gold check: Gold customer → first name + true only', r::text);
  r := public.f360_gold_check('+15550100012');
  PERFORM pg_temp.ok(r->>'gold' = 'false', 'gold check: non-Gold customer → false', r::text);
  r := public.f360_gold_check('+15559999999');
  PERFORM pg_temp.ok(r->>'exists' = 'false', 'gold check: unknown phone → not a customer', r::text);
  r := pg_temp.as(c1, $q$SELECT public.f360_gold_check('+15550100011')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'gold check is service-only', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
