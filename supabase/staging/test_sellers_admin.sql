-- Rehearsal of 20261013000100_f360_sellers_admin (Vendedoras) — ALWAYS rolled back. Prepend the migration and append
-- ROLLBACK when sending. Flow: owner adds a seller with no app account → pending + customers row; first login links
-- auth_user_id → active with role, store and PIN; she starts a shift with her PIN at her ONLY store; store change,
-- PIN reset, deactivation; an owner/operator is never downgraded. Raises on the first failed check.
DO $$
DECLARE owner_id uuid; st1 uuid; st2 uuid; uid uuid := gen_random_uuid(); j jsonb; sid uuid; cu public.customers; ph text := '+525599990001';
BEGIN
  SELECT auth_user_id INTO owner_id FROM f360.user_roles WHERE role = 'owner' LIMIT 1;
  SELECT id INTO st1 FROM f360.locations WHERE status = 'active' AND sellable AND type = 'store' ORDER BY name LIMIT 1;
  SELECT id INTO st2 FROM f360.locations WHERE status = 'active' AND sellable AND id <> st1 ORDER BY name LIMIT 1;
  IF owner_id IS NULL OR st1 IS NULL OR st2 IS NULL THEN RAISE EXCEPTION 'fixture: need an owner and two sellable stores'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);

  -- 1 · bad input is refused
  BEGIN PERFORM public.f360_admin_seller_add('Prueba Vendedora', '123', st1, '0810'); RAISE EXCEPTION 'T1 phone accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'T1%' THEN RAISE; END IF; END;
  BEGIN PERFORM public.f360_admin_seller_add('Prueba Vendedora', '5599990001', st1, '12'); RAISE EXCEPTION 'T1 pin accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'T1%' THEN RAISE; END IF; END;

  -- 2 · add without account → pending, customers row created exactly as the app login writes the phone
  j := public.f360_admin_seller_add('Prueba Vendedora', '55 9999 0001', st1, '0810');
  sid := (j->>'id')::uuid;
  IF j->>'status' <> 'pendiente' OR j->>'phone_last4' <> '0001' OR j ? 'pin_hash' THEN RAISE EXCEPTION 'T2 %', j; END IF;
  SELECT * INTO cu FROM public.customers WHERE phone = ph;
  IF cu.id IS NULL OR cu.role <> 'staff' OR cu.auth_user_id IS NOT NULL THEN RAISE EXCEPTION 'T2 customers row %', to_jsonb(cu); END IF;
  BEGIN PERFORM public.f360_admin_seller_add('Otra', '5599990001', st1, '1111'); RAISE EXCEPTION 'T2 duplicate accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'T2%' THEN RAISE; END IF; END;

  -- 3 · first app login (whatsapp-otp links auth_user_id) → active: role, assignment, credentials
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', '525599990001@fuxia.app', '', now(), now(), now());
  UPDATE public.customers SET auth_user_id = uid WHERE id = cu.id;
  IF (SELECT status FROM f360.sellers WHERE id = sid) <> 'activa' THEN RAISE EXCEPTION 'T3 not activated'; END IF;
  IF (SELECT role FROM f360.user_roles WHERE auth_user_id = uid) <> 'seller' THEN RAISE EXCEPTION 'T3 role'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.location_assignments WHERE auth_user_id = uid AND location_id = st1 AND active) THEN RAISE EXCEPTION 'T3 store'; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360.seller_credentials WHERE auth_user_id = uid) THEN RAISE EXCEPTION 'T3 pin'; END IF;

  -- 4 · she sees ONLY her store and starts a shift with her PIN (as her)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  j := public.f360_my_locations();
  IF jsonb_array_length(j) <> 1 OR (j->0->>'id')::uuid <> st1 THEN RAISE EXCEPTION 'T4 locations %', j; END IF;
  j := public.f360_start_seller_shift(st1, '0810');
  IF NOT (j->>'ok')::boolean THEN RAISE EXCEPTION 'T4 shift %', j; END IF;
  BEGIN PERFORM public.f360_admin_sellers(); RAISE EXCEPTION 'T4 seller listed sellers';
  EXCEPTION WHEN insufficient_privilege OR raise_exception THEN IF SQLERRM LIKE 'T4%' THEN RAISE; END IF; END;

  -- 5 · store change moves her and closes the open shift; PIN reset; deactivate removes access
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  j := public.f360_admin_seller_set_store(sid, st2);
  IF (j->'location'->>'id')::uuid <> st2 THEN RAISE EXCEPTION 'T5 store %', j; END IF;
  IF EXISTS (SELECT 1 FROM f360.location_assignments WHERE auth_user_id = uid AND location_id = st1 AND active) THEN RAISE EXCEPTION 'T5 old store active'; END IF;
  IF EXISTS (SELECT 1 FROM f360.seller_sessions WHERE auth_user_id = uid AND revoked_at IS NULL) THEN RAISE EXCEPTION 'T5 shift not revoked'; END IF;
  PERFORM public.f360_admin_seller_reset_pin(sid, '4321');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  j := public.f360_start_seller_shift(st2, '4321');
  IF NOT (j->>'ok')::boolean THEN RAISE EXCEPTION 'T5 new pin %', j; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  j := public.f360_admin_seller_deactivate(sid);
  IF j->>'status' <> 'inactiva' OR EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = uid) THEN RAISE EXCEPTION 'T5 deactivate %', j; END IF;

  -- 6 · an owner added as seller keeps her owner role
  IF EXISTS (SELECT 1 FROM public.customers c WHERE c.auth_user_id = owner_id AND f360.normalize_phone(c.phone) IS NOT NULL) THEN
    j := public.f360_admin_seller_add('Dueña Prueba', (SELECT c.phone FROM public.customers c WHERE c.auth_user_id = owner_id LIMIT 1), st1, '2222');
    IF (SELECT role FROM f360.user_roles WHERE auth_user_id = owner_id) <> 'owner' THEN RAISE EXCEPTION 'T6 owner downgraded'; END IF;
  END IF;

  RAISE NOTICE 'sellers admin: all checks passed';
END $$;
