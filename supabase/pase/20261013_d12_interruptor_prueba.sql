-- D12 interruptor · PRODUCCIÓN · PRUEBA (solo --dry-run, después de aplicar o dentro del ensayo). No apaga ninguna tienda:
-- con cuentas reales solo intenta los caminos que DEBEN ser rechazados, y lee el estado como dueña. No imprime datos personales.
BEGIN;
DO $$
DECLARE u_owner uuid; u_seller uuid; u_cli uuid; admin_phone text; ok boolean; j jsonb; who text; u uuid; n bigint;
BEGIN
  SELECT r.auth_user_id INTO u_owner FROM f360.user_roles r WHERE r.role = 'owner' LIMIT 1;
  SELECT r.auth_user_id INTO u_seller FROM f360.user_roles r WHERE r.role = 'seller' LIMIT 1;
  SELECT c.auth_user_id INTO u_cli FROM public.customers c WHERE c.role = 'customer' AND c.auth_user_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = c.auth_user_id) LIMIT 1;
  SELECT c.phone INTO admin_phone FROM public.customers c WHERE c.role = 'admin' LIMIT 1;
  IF u_owner IS NULL OR u_seller IS NULL OR u_cli IS NULL OR admin_phone IS NULL THEN RAISE EXCEPTION 'D12-SW prueba: falta un perfil real'; END IF;

  -- T1 todas las tiendas encendidas; la pantalla de NIP (anon) ve las mismas 5 tiendas activas que antes
  IF EXISTS (SELECT 1 FROM public.channels WHERE legacy_pin_enabled IS DISTINCT FROM true) THEN RAISE EXCEPTION 'D12-SW T1 tienda apagada'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  IF (SELECT count(*) FROM public.channels WHERE active) <> 5 OR (SELECT count(*) FROM public.channels WHERE active AND legacy_pin_enabled IS DISTINCT FROM false) <> 5
    THEN RAISE EXCEPTION 'D12-SW T1 la pantalla de NIP no ve las 5 tiendas'; END IF;
  -- T2 anon no cambia el interruptor (ni RPC ni UPDATE) y no lee el estado
  ok := false; BEGIN PERFORM public.f360_legacy_pin_set((SELECT id FROM public.channels LIMIT 1), false, 'prueba anon'); EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T2 anon RPC'; END IF;
  ok := false; BEGIN PERFORM public.f360_legacy_pin_status(); EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T2 anon status'; END IF;
  UPDATE public.channels SET legacy_pin_enabled = false;   -- sin política UPDATE para anon: 0 filas
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'D12-SW T2 anon UPDATE'; END IF;

  -- T3 vendedora y clienta: RPC rechazada; clienta con el teléfono de una admin en user_metadata (perfil editable):
  --    la política channels.admins_all_channels la dejaría escribir, pero el disparador lo impide
  FOREACH who IN ARRAY ARRAY['vendedora', 'clienta', 'clienta_falsificada'] LOOP
    u := CASE who WHEN 'vendedora' THEN u_seller ELSE u_cli END;
    PERFORM set_config('request.jwt.claims', CASE WHEN who = 'clienta_falsificada'
      THEN json_build_object('sub', u, 'role', 'authenticated', 'user_metadata', json_build_object('phone', admin_phone))::text
      ELSE json_build_object('sub', u, 'role', 'authenticated')::text END, true);
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_set((SELECT id FROM public.channels LIMIT 1), false, 'prueba'); RESET ROLE;
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'D12-SW T3 % cambió por RPC', who; END IF;
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; UPDATE public.channels SET legacy_pin_enabled = false; GET DIAGNOSTICS n = ROW_COUNT; RESET ROLE;
      ok := n = 0;   -- sin política de escritura: 0 filas
    EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok OR EXISTS (SELECT 1 FROM public.channels WHERE NOT legacy_pin_enabled) THEN RAISE EXCEPTION 'D12-SW T3 % cambió por UPDATE', who; END IF;
    ok := false;
    BEGIN SET LOCAL ROLE authenticated; PERFORM public.f360_legacy_pin_status(); RESET ROLE; EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; ok := true; END;
    IF NOT ok THEN RAISE EXCEPTION 'D12-SW T3 % lee el estado', who; END IF;
  END LOOP;

  -- T4 ni postgres cambia la columna fuera de la RPC
  ok := false; BEGIN UPDATE public.channels SET legacy_pin_enabled = false; EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  IF NOT ok THEN RAISE EXCEPTION 'D12-SW T4 cambio directo'; END IF;

  -- T5 la dueña lee el estado (solo lectura): 5 tiendas, todas encendidas, sin cambios registrados
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_owner, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated; j := public.f360_legacy_pin_status(); RESET ROLE;
  IF jsonb_array_length(j) <> 5 OR EXISTS (SELECT 1 FROM jsonb_array_elements(j) e WHERE NOT (e->>'legacy_pin_enabled')::boolean OR e->'last_change' <> 'null'::jsonb)
    THEN RAISE EXCEPTION 'D12-SW T5 estado %', j; END IF;
  IF (SELECT count(*) FROM f360.legacy_pin_switch_log) <> 0 THEN RAISE EXCEPTION 'D12-SW T5 hubo cambios'; END IF;
END $$;
COMMIT;
