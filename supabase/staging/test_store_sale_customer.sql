-- Rehearsal of 20261013000200_f360_store_sale_customer (needs 20261013000100 first) — ALWAYS rolled back.
-- Counter flow: seller shift → new customer without e-mail → sale linked to her → stock down, points HELD, claim code
-- closed → she logs in to the app (auth_user_id linked) → points credited once; a verified customer's sale credits now;
-- the same key twice is one sale. Raises on the first failed check.
DO $$
DECLARE owner_id uuid; st uuid; v uuid; seller uuid := gen_random_uuid(); cust_uid uuid := gen_random_uuid(); tok text; j jsonb; cref uuid;
  k uuid := gen_random_uuid(); before_qty int; pts0 int; sale public.offline_sales;
BEGIN
  SELECT auth_user_id INTO owner_id FROM f360.user_roles WHERE role = 'owner' LIMIT 1;
  SELECT b.location_id, b.variant_id INTO st, v FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id
    JOIN f360.product_variants pv ON pv.id = b.variant_id JOIN f360.products p ON p.id = pv.product_id
    WHERE l.status = 'active' AND l.sellable AND l.ledger_authority = 'f360' AND b.on_hand >= 2 AND p.regular_price IS NOT NULL
      AND pv.status = 'active' AND NOT f360.location_in_cutover(l.id)
      AND f360.reserved_qty(b.variant_id, b.location_id, NULL) = 0 LIMIT 1;
  IF owner_id IS NULL OR st IS NULL THEN RAISE EXCEPTION 'fixture: need an owner and a priced pair in an F360 store'; END IF;

  -- seller (Vendedoras) + first login + shift
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  PERFORM public.f360_admin_seller_add('Vendedora Prueba', '5599990011', st, '0810');
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (seller, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '525599990011@fuxia.app', '', now(), now(), now());
  UPDATE public.customers SET auth_user_id = seller WHERE phone = '+525599990011';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
  j := public.f360_start_seller_shift(st, '0810'); tok := j->>'token';
  IF tok IS NULL THEN RAISE EXCEPTION 'T0 shift %', j; END IF;

  -- 1 · new customer at the counter, no e-mail
  j := public.f360_shift_customer_find(tok, '5599990022');
  IF (j->>'found')::boolean THEN RAISE EXCEPTION 'T1 found before register'; END IF;
  j := public.f360_shift_customer_register(tok, '5599990022', 'Clienta Prueba', '', NULL, NULL, NULL, '37');
  IF NOT (j->>'ok')::boolean OR NOT (j->>'created')::boolean THEN RAISE EXCEPTION 'T1 register %', j; END IF;
  cref := (j->'customer'->>'customer_ref')::uuid;
  j := public.f360_shift_customer_register(tok, '5599990022', 'Clienta Prueba', 'mal-correo', NULL, NULL, NULL, NULL);
  IF (j->>'created')::boolean THEN RAISE EXCEPTION 'T1 duplicate created'; END IF;
  j := public.f360_shift_customer_find(tok, '55 9999 0022');
  IF NOT (j->>'found')::boolean OR (j->'customer'->>'customer_ref')::uuid <> cref THEN RAISE EXCEPTION 'T1 find %', j; END IF;

  -- 2 · sale linked to her: stock down, points held, code closed; same key = same sale
  SELECT on_hand INTO before_qty FROM f360.inventory_balances WHERE variant_id = v AND location_id = st;
  j := public.f360_record_store_sale_for(tok, k, jsonb_build_array(jsonb_build_object('variant_id', v, 'quantity', 1)), 'card', NULL, cref);
  IF j->>'points_state' <> 'held' OR (j->>'points')::int <= 0 OR j ? 'code' THEN RAISE EXCEPTION 'T2 %', j; END IF;
  IF (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = st) <> before_qty - 1 THEN RAISE EXCEPTION 'T2 stock'; END IF;
  SELECT * INTO sale FROM public.offline_sales WHERE idempotency_key = k;
  IF sale.customer_id <> cref OR sale.claimed_at IS NULL THEN RAISE EXCEPTION 'T2 link'; END IF;
  j := public.f360_record_store_sale_for(tok, k, jsonb_build_array(jsonb_build_object('variant_id', v, 'quantity', 1)), 'card', NULL, cref);
  IF (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = st) <> before_qty - 1 THEN RAISE EXCEPTION 'T2 replay sold twice'; END IF;
  IF (SELECT count(*) FROM f360.loyalty_holds WHERE customer_id = cref) <> 1 THEN RAISE EXCEPTION 'T2 replay held twice'; END IF;

  -- 3 · she logs in to the app → points credited once
  SELECT coalesce(total_points, 0) INTO pts0 FROM public.loyalty_cards WHERE customer_id = cref;
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (cust_uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '525599990022@fuxia.app', '', now(), now(), now());
  UPDATE public.customers SET auth_user_id = cust_uid WHERE id = cref;
  IF (SELECT status FROM f360.loyalty_holds WHERE customer_id = cref) <> 'released' THEN RAISE EXCEPTION 'T3 hold not released'; END IF;
  IF (SELECT total_points FROM public.loyalty_cards WHERE customer_id = cref) <= pts0 THEN RAISE EXCEPTION 'T3 no points'; END IF;

  -- 4 · now verified: the next sale credits at once
  j := public.f360_record_store_sale_for(tok, gen_random_uuid(), jsonb_build_array(jsonb_build_object('variant_id', v, 'quantity', 1)), 'cash', NULL, cref);
  IF j->>'points_state' <> 'credited' THEN RAISE EXCEPTION 'T4 %', j; END IF;

  -- 5 · anonymous sale still works and returns its claim code
  IF (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = st) > 0 THEN
    j := public.f360_record_store_sale_for(tok, gen_random_uuid(), jsonb_build_array(jsonb_build_object('variant_id', v, 'quantity', 1)), 'cash', NULL, NULL);
    IF j->>'code' IS NULL THEN RAISE EXCEPTION 'T5 %', j; END IF;
  END IF;
  RAISE NOTICE 'store sale customer: all checks passed';
END $$;

-- 6 · the seller's catalog carries product, category and a photo path (when the model has photos)
DO $$
DECLARE seller uuid; tok text; st uuid; j jsonb;
BEGIN
  SELECT auth_user_id INTO seller FROM f360.sellers WHERE phone = '+525599990011';
  SELECT location_id INTO st FROM f360.sellers WHERE phone = '+525599990011';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated')::text, true);
  j := public.f360_start_seller_shift(st, '0810'); tok := j->>'token';
  j := public.f360_shift_catalog(tok);
  IF NOT (j->'items'->0 ? 'product_id') OR NOT (j->'items'->0 ? 'category') OR NOT (j->'items'->0 ? 'image') THEN RAISE EXCEPTION 'T6 %', j->'items'->0; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'items') x WHERE x->>'image' IS NOT NULL) THEN RAISE EXCEPTION 'T6 no photos at all'; END IF;
END $$;
