-- D12 · Phase A (20261027000100) — who reads public.staff / offline_sales / support_tickets (staging). Run as a whole file: BEGIN … ROLLBACK.
-- Identities: anon · customer (incl. forged user_metadata phone) · legacy staff · legacy admin · Fuxia 360 seller · Fuxia 360 operator.
BEGIN;
DO $$
DECLARE ch uuid; st uuid; s1 uuid; s2 uuid; s3 uuid; n bigint; v text; ok boolean;
  u_cli uuid := gen_random_uuid(); u_cli2 uuid := gen_random_uuid(); u_staff uuid := gen_random_uuid(); u_admin uuid := gen_random_uuid();
  u_seller uuid := gen_random_uuid(); u_oper uuid := gen_random_uuid();
  all_staff bigint; active_staff bigint; all_sales bigint; all_tickets bigint; fn text;
BEGIN
  -- fixtures (this transaction only)
  INSERT INTO auth.users (id, email, aud, role)
  SELECT x, 'zz-d12-' || i || '@staging.invalid', 'authenticated', 'authenticated'
    FROM unnest(ARRAY[u_cli, u_cli2, u_staff, u_admin, u_seller, u_oper]) WITH ORDINALITY AS t(x, i);
  INSERT INTO public.customers (name, phone, role, auth_user_id) VALUES
    ('zz d12 clienta', '+520000000101', 'customer', u_cli), ('zz d12 clienta2', '+520000000102', 'customer', u_cli2),
    ('zz d12 staff', '+520000000103', 'staff', u_staff), ('zz d12 admin', '+520000000104', 'admin', u_admin),
    ('zz d12 seller', '+520000000105', 'customer', u_seller), ('zz d12 oper', '+520000000106', 'customer', u_oper);
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (u_seller, 'seller', 'zz seller'), (u_oper, 'operator', 'zz oper');
  INSERT INTO public.channels (name, type) VALUES ('zz d12 canal', 'store') RETURNING id INTO ch;
  INSERT INTO public.staff (name, pin, channel_id, active) VALUES ('zz d12 vendedora', '9917', ch, true) RETURNING id INTO st;
  INSERT INTO public.offline_sales (code, items, total, channel_id, customer_phone) VALUES ('ZZD12A', '[]', 100, ch, '+520000000101') RETURNING id INTO s1;
  INSERT INTO public.offline_sales (code, items, total, channel_id, customer_id)
    VALUES ('ZZD12B', '[]', 200, ch, (SELECT id FROM public.customers WHERE auth_user_id = u_cli2)) RETURNING id INTO s2;
  INSERT INTO public.offline_sales (code, items, total, channel_id) VALUES ('ZZD12C', '[]', 300, ch) RETURNING id INTO s3;
  INSERT INTO public.support_tickets (customer_id, customer_phone, customer_name, topic) VALUES
    ((SELECT id FROM public.customers WHERE auth_user_id = u_cli), '+520000000101', 'zz', 'zz d12'),
    ((SELECT id FROM public.customers WHERE auth_user_id = u_cli2), '+520000000102', 'zz', 'zz d12');
  SELECT count(*), count(*) FILTER (WHERE active) INTO all_staff, active_staff FROM public.staff;
  SELECT count(*) INTO all_sales FROM public.offline_sales;
  SELECT count(*) INTO all_tickets FROM public.support_tickets;

  -- P1 customer: no staff (no pin), only her own sale and ticket
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> 0 THEN RAISE EXCEPTION 'P1 customer reads staff'; END IF;
  IF (SELECT count(*) FROM public.staff WHERE pin = '9917') <> 0 THEN RAISE EXCEPTION 'P1 customer finds a pin'; END IF;
  IF (SELECT array_agg(id) FROM public.offline_sales) IS DISTINCT FROM ARRAY[s1] THEN RAISE EXCEPTION 'P1 customer sales'; END IF;
  IF (SELECT count(*) FROM public.support_tickets) <> 1 THEN RAISE EXCEPTION 'P1 customer tickets'; END IF;
  -- tracking/index.tsx: her unclaimed sales by phone still appear
  IF (SELECT count(*) FROM public.offline_sales WHERE customer_phone = '+520000000101' AND claimed_at IS NULL) <> 1 THEN RAISE EXCEPTION 'P1 tracking'; END IF;
  RESET ROLE;
  -- the second customer sees hers by customer_id, not the first one's
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli2, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT array_agg(id) FROM public.offline_sales) IS DISTINCT FROM ARRAY[s2] THEN RAISE EXCEPTION 'P1 customer2 sales'; END IF;
  RESET ROLE;

  -- P2 forged identity: the customer edits user_metadata.phone to the admin's phone (auth.updateUser) → still a customer
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated',
    'user_metadata', json_build_object('phone', '+520000000104'))::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> 0 OR (SELECT count(*) FROM public.offline_sales) <> 1 OR (SELECT count(*) FROM public.support_tickets) <> 1 THEN
    RAISE EXCEPTION 'P2 forged admin phone opens data';
  END IF;
  UPDATE public.staff SET active = active WHERE id = st;  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'P2 forged admin phone updates staff'; END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated',
    'user_metadata', json_build_object('phone', '+520000000102'))::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT array_agg(id) FROM public.offline_sales) IS DISTINCT FROM ARRAY[s1] THEN RAISE EXCEPTION 'P2 forged phone reads another customer''s sales'; END IF;
  RESET ROLE;

  -- P3 legacy staff: all staff incl. pin (PIN screen with a session), all sales, all tickets, can record a sale
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_staff, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> all_staff THEN RAISE EXCEPTION 'P3 staff list'; END IF;
  IF (SELECT id FROM public.staff WHERE pin = '9917' AND channel_id = ch AND active) IS DISTINCT FROM st THEN RAISE EXCEPTION 'P3 pin lookup'; END IF;
  IF (SELECT count(*) FROM public.offline_sales) <> all_sales THEN RAISE EXCEPTION 'P3 staff sales'; END IF;
  IF (SELECT count(*) FROM public.support_tickets) <> all_tickets THEN RAISE EXCEPTION 'P3 staff tickets'; END IF;
  INSERT INTO public.offline_sales (code, items, total, channel_id, staff_id) VALUES ('ZZD12D', '[]', 50, ch, st);
  RESET ROLE;

  -- P4 legacy admin: everything + manages staff (admin/staff screens)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> all_staff OR (SELECT count(*) FROM public.offline_sales) <> all_sales + 1
     OR (SELECT count(*) FROM public.support_tickets) <> all_tickets THEN RAISE EXCEPTION 'P4 admin reads'; END IF;
  UPDATE public.staff SET pin = '9918' WHERE id = st;  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'P4 admin cannot update staff'; END IF;
  RESET ROLE;

  -- P5 Fuxia 360 seller (legacy role customer): sales of the store (vendedora/home, sales-today) but never staff/pin or tickets
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_seller, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> 0 THEN RAISE EXCEPTION 'P5 seller reads staff'; END IF;
  IF (SELECT count(*) FROM public.offline_sales WHERE channel_id = ch) <> 4 THEN RAISE EXCEPTION 'P5 seller sales'; END IF;
  IF (SELECT count(*) FROM public.support_tickets) <> 0 THEN RAISE EXCEPTION 'P5 seller tickets'; END IF;
  RESET ROLE;

  -- P6 Fuxia 360 operator: legacy PIN screen ("modo anterior") still finds the seller by pin
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_oper, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT id FROM public.staff WHERE pin = '9918' AND channel_id = ch AND active) IS DISTINCT FROM st THEN RAISE EXCEPTION 'P6 operator pin lookup'; END IF;
  IF (SELECT count(*) FROM public.support_tickets) <> 0 THEN RAISE EXCEPTION 'P6 operator tickets'; END IF;
  RESET ROLE;

  -- P7 anon: unchanged in Phase A (legacy PIN screen and legacy sale keep working; closed in Phase B)
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  IF (SELECT count(*) FROM public.staff) <> active_staff THEN RAISE EXCEPTION 'P7 anon PIN screen changed'; END IF;
  INSERT INTO public.offline_sales (code, items, total, channel_id, staff_id) VALUES ('ZZD12E', '[]', 60, ch, st);
  IF (SELECT count(*) FROM public.support_tickets) <> 0 THEN RAISE EXCEPTION 'P7 anon tickets'; END IF;
  RESET ROLE;

  -- P8 no client-callable SECURITY DEFINER function hands these tables to a customer
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated')::text, true);
  FOREACH fn IN ARRAY ARRAY[format('public.f360_get_sale(%L::uuid)', s3), 'public.f360_favorites_report(NULL, 10)', 'public.f360_review_work_queue()',
                            'public.f360_legacy_store_sales_import(false)', format('public.f360_review_confirm_candidate(%L::uuid, %L::uuid, NULL)', s3, s3),
                            'public.f360_hist_sales_save(NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)'] LOOP
    ok := false;
    BEGIN
      SET LOCAL ROLE authenticated;
      EXECUTE 'SELECT left((' || fn || ')::text, 200)' INTO v;
      RESET ROLE;
    EXCEPTION WHEN others THEN RESET ROLE; ok := true; END;
    IF NOT ok AND v NOT LIKE '%"ok": false%' THEN RAISE EXCEPTION 'P8 % answered a customer: %', fn, v; END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname IN ('public', 'f360', 'f360_board') AND p.prosecdef
     AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
     AND p.prosrc ~* 'public\.staff\M|\mfrom\s+staff\M|\mjoin\s+staff\M|\msupport_tickets\M';
  IF n <> 0 THEN RAISE EXCEPTION 'P8 % client-callable definer functions read staff/support_tickets', n; END IF;

  RAISE NOTICE 'D12 FASE A OK · staff % · ventas % · tickets %', all_staff, all_sales, all_tickets;
END $$;
ROLLBACK;
