-- D12 · interruptor por tienda de la pantalla de NIP anterior (20261029000100), STAGING. Run as a whole file: BEGIN … ROLLBACK.
-- Only fictitious identities and a fictitious store; no real account or store is changed.
BEGIN;
DO $$
DECLARE owner_u uuid := gen_random_uuid(); oper_u uuid := gen_random_uuid(); seller_u uuid := gen_random_uuid(); cli_u uuid := gen_random_uuid();
  ch uuid; j jsonb; n bigint; ok boolean; anon_fp text;
BEGIN
  INSERT INTO auth.users (id, email, aud, role)
  SELECT x, 'zz-lps-' || i || '@staging.invalid', 'authenticated', 'authenticated' FROM unnest(ARRAY[owner_u, oper_u, seller_u, cli_u]) WITH ORDINALITY t(x, i);
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (owner_u, 'owner', 'zz Dueña'), (oper_u, 'operator', 'zz Operadora'), (seller_u, 'seller', 'zz Vendedora');
  INSERT INTO public.customers (name, phone, role, auth_user_id) VALUES ('zz admin app', '+520000000201', 'admin', cli_u);   -- legacy app admin, no F360 role
  INSERT INTO public.channels (name, type) VALUES ('zz Tienda interruptor', 'store') RETURNING id INTO ch;
  SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*)
    INTO anon_fp FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%';

  -- S1 every store starts ON (nothing changes for anyone until the owner switches a store off)
  IF EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'S1 a store starts off'; END IF;

  -- S2 no direct change: not even postgres, nor a legacy app admin through the channels write policies
  BEGIN UPDATE public.channels SET legacy_pin_enabled = false WHERE id = ch; RAISE EXCEPTION 'S2 direct update (postgres)';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', cli_u, 'role', 'authenticated', 'user_metadata', json_build_object('phone', '+520000000201'))::text, true);
  ok := false;
  BEGIN SET LOCAL ROLE authenticated; UPDATE public.channels SET legacy_pin_enabled = false WHERE id = ch; RESET ROLE;
  EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
  IF NOT ok OR NOT (SELECT legacy_pin_enabled FROM public.channels WHERE id = ch) THEN RAISE EXCEPTION 'S2 app admin changed the switch directly'; END IF;

  -- S3 only the owner, with a reason
  FOREACH j IN ARRAY ARRAY[to_jsonb(seller_u), to_jsonb(oper_u), to_jsonb(cli_u)] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', j #>> '{}', 'role', 'authenticated')::text, true);
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_set(ch, false, 'prueba'); RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'S3 % switched a store', j; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_u, 'role', 'authenticated')::text, true);
  ok := false;
  BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_set(ch, false, ' '); RESET ROLE; EXCEPTION WHEN raise_exception THEN RESET ROLE; ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'S3 no reason accepted'; END IF;

  -- S4 owner switches it off: column false, one log row; the same call again changes nothing and logs nothing
  SET LOCAL ROLE authenticated;
  j := public.f360_legacy_pin_set(ch, false, 'Tienda migrada a cuentas F360 (prueba)');
  RESET ROLE;
  IF NOT (j->>'changed')::boolean OR (SELECT legacy_pin_enabled FROM public.channels WHERE id = ch) THEN RAISE EXCEPTION 'S4 %', j; END IF;
  SET LOCAL ROLE authenticated; j := public.f360_legacy_pin_set(ch, false, 'otra vez'); RESET ROLE;
  IF (j->>'changed')::boolean OR (SELECT count(*) FROM f360.legacy_pin_switch_log WHERE channel_id = ch) <> 1 THEN RAISE EXCEPTION 'S4 idempotent %', j; END IF;
  IF (SELECT actor FROM f360.legacy_pin_switch_log WHERE channel_id = ch) <> owner_u THEN RAISE EXCEPTION 'S4 actor'; END IF;

  -- S5 the legacy PIN screen (anon) sees the store as off; anon policies and the anon PIN path itself are unchanged
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  IF (SELECT legacy_pin_enabled FROM public.channels WHERE id = ch) IS DISTINCT FROM false THEN RAISE EXCEPTION 'S5 anon does not see the switch'; END IF;
  ok := false; BEGIN PERFORM public.f360_legacy_pin_set(ch, true, 'anon'); EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  RESET ROLE;
  IF NOT ok THEN RAISE EXCEPTION 'S5 anon can switch'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*)
      FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> anon_fp THEN RAISE EXCEPTION 'S5 anon policies changed'; END IF;

  -- S6 the log is immutable (even for postgres)
  BEGIN UPDATE f360.legacy_pin_switch_log SET reason = 'x' WHERE channel_id = ch; RAISE EXCEPTION 'S6 update';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM f360.legacy_pin_switch_log WHERE channel_id = ch; RAISE EXCEPTION 'S6 delete';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', oper_u, 'role', 'authenticated')::text, true);
  ok := false; BEGIN SET LOCAL ROLE authenticated; PERFORM count(*) FROM f360.legacy_pin_switch_log; RESET ROLE; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'S6 log readable directly'; END IF;

  -- S7 status: operator sees each store (switch, legacy sales 14 d, last change); seller and app admin without F360 role cannot
  SET LOCAL ROLE authenticated; j := public.f360_legacy_pin_status(); RESET ROLE;
  IF (SELECT count(*) FROM jsonb_array_elements(j) e WHERE (e->>'channel_id')::uuid = ch AND NOT (e->>'legacy_pin_enabled')::boolean
        AND (e->>'legacy_sales_14d')::int = 0 AND e->'last_change'->>'by' = 'zz Dueña') <> 1 THEN RAISE EXCEPTION 'S7 status %', j; END IF;
  IF jsonb_array_length(j) <> (SELECT count(*) FROM public.channels) THEN RAISE EXCEPTION 'S7 not every store'; END IF;
  FOREACH j IN ARRAY ARRAY[to_jsonb(seller_u), to_jsonb(cli_u)] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', j #>> '{}', 'role', 'authenticated')::text, true);
    ok := false; BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_status(); RESET ROLE; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'S7 % reads status', j; END IF;
  END LOOP;

  -- S8 contingency: switching it back on restores the store the same day, with a second log row
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_u, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated; j := public.f360_legacy_pin_set(ch, true, 'Contingencia: vuelve la app anterior'); RESET ROLE;
  IF NOT (SELECT legacy_pin_enabled FROM public.channels WHERE id = ch) OR (SELECT count(*) FROM f360.legacy_pin_switch_log WHERE channel_id = ch) <> 2 THEN RAISE EXCEPTION 'S8'; END IF;

  RAISE NOTICE 'INTERRUPTOR NIP OK (S1–S8)';
END $$;
ROLLBACK;
