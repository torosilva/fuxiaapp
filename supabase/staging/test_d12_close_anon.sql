-- D12 · cierre de la entrada vieja (20261029000200), STAGING. Run as a whole file: BEGIN … ROLLBACK. Only fictitious identities.
BEGIN;
DO $$
DECLARE ch uuid; st uuid; ci uuid; n bigint; ok boolean;
  u_staff uuid := gen_random_uuid(); u_admin uuid := gen_random_uuid(); u_cli uuid := gen_random_uuid(); u_seller uuid := gen_random_uuid();
  t text;
BEGIN
  INSERT INTO auth.users (id, email, aud, role)
  SELECT x, 'zz-close-' || i || '@staging.invalid', 'authenticated', 'authenticated' FROM unnest(ARRAY[u_staff, u_admin, u_cli, u_seller]) WITH ORDINALITY t(x, i);
  INSERT INTO public.customers (name, phone, role, auth_user_id) VALUES ('zz staff', '+520000000301', 'staff', u_staff), ('zz admin', '+520000000302', 'admin', u_admin),
    ('zz clienta', '+520000000303', 'customer', u_cli), ('zz seller', '+520000000304', 'customer', u_seller);
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (u_seller, 'seller', 'zz seller');
  INSERT INTO public.channels (name, type) VALUES ('zz canal cierre', 'store') RETURNING id INTO ch;
  INSERT INTO public.staff (name, pin, channel_id, active) VALUES ('zz vendedora', '7319', ch, true) RETURNING id INTO st;
  INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold)
    VALUES (ch, 'zz modelo', '37', 'negro', 2800, 3, 0) RETURNING id INTO ci;
  INSERT INTO public.inventory_change_requests (channel_id, requested_by_staff_id, requested_by_name, action, payload, status)
    VALUES (ch, st, 'zz', 'adjust_stock', '{}', 'pending');

  -- C1 anon: nothing from the legacy tables (the old PIN screen gets no PIN, no sale, no inventory), but still the store list
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  FOREACH t IN ARRAY ARRAY['SELECT count(*) FROM public.staff', 'SELECT count(*) FROM public.offline_sales', 'SELECT count(*) FROM public.channel_inventory',
                           'SELECT count(*) FROM public.support_tickets', 'SELECT count(*) FROM public.inventory_change_requests', 'SELECT count(*) FROM public.offline_sale_items',
                           format('INSERT INTO public.offline_sales (code, items, total, channel_id, staff_id) VALUES (''ZZCLOSE'', ''[]'', 1, %L, %L)', ch, st),
                           format('UPDATE public.channel_inventory SET sold = sold + 1 WHERE id = %L', ci),
                           format('INSERT INTO public.inventory_change_requests (channel_id, requested_by_staff_id, requested_by_name, action, payload) VALUES (%L, %L, ''zz'', ''adjust_stock'', ''{}'')', ch, st)] LOOP
    ok := false;
    BEGIN SET LOCAL ROLE anon; EXECUTE t; RESET ROLE; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'C1 anon pudo: %', t; END IF;
  END LOOP;
  SET LOCAL ROLE anon;
  IF (SELECT count(*) FROM public.channels WHERE id = ch) <> 1 THEN RAISE EXCEPTION 'C1 anon ya no ve la lista de tiendas'; END IF;
  RESET ROLE;
  IF (SELECT sold FROM public.channel_inventory WHERE id = ci) <> 0 OR EXISTS (SELECT 1 FROM public.offline_sales WHERE code = 'ZZCLOSE') THEN RAISE EXCEPTION 'C1 algo se escribió'; END IF;

  -- C2 legacy staff account (session): still reads staff/sales/requests, records a sale and updates inventory (authorized role)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_staff, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT id FROM public.staff WHERE pin = '7319' AND channel_id = ch) IS DISTINCT FROM st THEN RAISE EXCEPTION 'C2 staff pin lookup'; END IF;
  IF (SELECT count(*) FROM public.inventory_change_requests WHERE channel_id = ch) <> 1 THEN RAISE EXCEPTION 'C2 staff icr'; END IF;
  INSERT INTO public.offline_sales (code, items, total, channel_id, staff_id) VALUES ('ZZCLOSE2', '[]', 2800, ch, st);
  UPDATE public.channel_inventory SET sold = sold + 1 WHERE id = ci;  GET DIAGNOSTICS n = ROW_COUNT;
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'C2 staff inventory update'; END IF;

  -- C3 admin account: manages stores through "channels admin write" (my_role), not through user_metadata
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  UPDATE public.channels SET location = 'zz' WHERE id = ch;  GET DIAGNOSTICS n = ROW_COUNT;
  RESET ROLE;
  IF n <> 1 THEN RAISE EXCEPTION 'C3 admin channels'; END IF;

  -- C4 customer with the admin's phone in user_metadata: the removed policies no longer let her write stores or inventory
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated', 'user_metadata', json_build_object('phone', '+520000000302'))::text, true);
  SET LOCAL ROLE authenticated;
  UPDATE public.channels SET location = 'hack' WHERE id = ch;  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'C4 forged phone writes channels'; END IF;
  UPDATE public.channel_inventory SET stock = 99 WHERE id = ci;  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RESET ROLE; RAISE EXCEPTION 'C4 forged phone writes inventory'; END IF;
  IF (SELECT count(*) FROM public.inventory_change_requests) <> 0 THEN RESET ROLE; RAISE EXCEPTION 'C4 customer reads requests'; END IF;
  RESET ROLE;

  -- C5 Fuxia 360 seller: reads her store's requests (vendedora/inventory) like before
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_seller, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.inventory_change_requests WHERE channel_id = ch) <> 1 THEN RESET ROLE; RAISE EXCEPTION 'C5 seller icr'; END IF;
  RESET ROLE;

  -- C6 no anon policy left on the legacy tables, and anon holds no table privilege on them
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%'
             AND tablename IN ('staff', 'offline_sales', 'offline_sale_items', 'channel_inventory', 'support_tickets', 'inventory_change_requests')) THEN RAISE EXCEPTION 'C6 anon policy left'; END IF;
  IF EXISTS (SELECT 1 FROM information_schema.role_table_grants WHERE table_schema = 'public' AND grantee = 'anon'
             AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'channel_inventory', 'support_tickets', 'inventory_change_requests')) THEN RAISE EXCEPTION 'C6 anon grant left'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND coalesce(qual, '') || coalesce(with_check, '') LIKE '%user_metadata%'
             AND tablename IN ('staff', 'offline_sales', 'channels', 'channel_inventory', 'support_tickets', 'inventory_change_requests')) THEN RAISE EXCEPTION 'C6 user_metadata policy left'; END IF;

  RAISE NOTICE 'CIERRE ENTRADA VIEJA OK (C1–C6)';
END $$;
ROLLBACK;
