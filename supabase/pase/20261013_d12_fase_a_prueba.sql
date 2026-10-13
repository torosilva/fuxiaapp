-- D12 fase A · PRODUCCIÓN · PRUEBA POR PERFIL (solo con --dry-run: termina en ROLLBACK, no escribe nada).
-- Usa cuentas reales existentes, solo con SELECT bajo su rol (SET LOCAL ROLE + claims del JWT). No imprime datos personales:
-- si algo no es lo esperado, aborta con el nombre del perfil y conteos.
-- Antes de aplicar la fase A debe FALLAR en "clienta lee staff" (control negativo); después debe pasar.
BEGIN;
DO $$
DECLARE u_admin uuid; u_staff uuid; u_seller uuid; u_cli uuid; cli_id uuid; cli_phone text; admin_phone text;
  all_staff bigint; active_staff bigint; all_sales bigint; all_tickets bigint; all_ci bigint; own_sales bigint; own_tickets bigint;
  seller_tickets bigint; n bigint;
BEGIN
  SELECT c.auth_user_id, c.phone INTO u_admin, admin_phone FROM public.customers c WHERE c.role = 'admin' AND c.auth_user_id IS NOT NULL ORDER BY c.created_at LIMIT 1;
  SELECT c.auth_user_id INTO u_staff FROM public.customers c WHERE c.role = 'staff' AND c.auth_user_id IS NOT NULL ORDER BY c.created_at LIMIT 1;
  SELECT r.auth_user_id INTO u_seller FROM f360.user_roles r JOIN public.customers c ON c.auth_user_id = r.auth_user_id
   WHERE r.role = 'seller' AND c.role = 'customer' LIMIT 1;
  -- a real customer (no store role) who has at least one in-store sale of her own
  SELECT c.auth_user_id, c.id, c.phone INTO u_cli, cli_id, cli_phone FROM public.customers c
   WHERE c.role = 'customer' AND c.auth_user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = c.auth_user_id)
     AND EXISTS (SELECT 1 FROM public.offline_sales o WHERE o.customer_id = c.id OR o.customer_phone = c.phone) LIMIT 1;
  IF u_admin IS NULL OR u_staff IS NULL OR u_seller IS NULL OR u_cli IS NULL THEN RAISE EXCEPTION 'D12 prueba: falta un perfil real'; END IF;

  SELECT count(*), count(*) FILTER (WHERE active) INTO all_staff, active_staff FROM public.staff;
  SELECT count(*) INTO all_sales FROM public.offline_sales;
  SELECT count(*) INTO all_tickets FROM public.support_tickets;
  SELECT count(*) INTO all_ci FROM public.channel_inventory;
  SELECT count(*) INTO own_sales FROM public.offline_sales WHERE customer_id = cli_id OR customer_phone = cli_phone;
  SELECT count(*) INTO own_tickets FROM public.support_tickets WHERE customer_id = cli_id;
  SELECT count(*) INTO seller_tickets FROM public.support_tickets t JOIN public.customers c ON c.id = t.customer_id WHERE c.auth_user_id = u_seller;

  -- clienta: sin personal ni NIP; solo lo suyo
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  n := (SELECT count(*) FROM public.staff); IF n <> 0 THEN RAISE EXCEPTION 'D12 prueba: clienta lee staff (% filas)', n; END IF;
  n := (SELECT count(*) FROM public.offline_sales); IF n <> own_sales THEN RAISE EXCEPTION 'D12 prueba: clienta ve % ventas (suyas %)', n, own_sales; END IF;
  n := (SELECT count(*) FROM public.support_tickets); IF n <> own_tickets THEN RAISE EXCEPTION 'D12 prueba: clienta ve % tickets (suyos %)', n, own_tickets; END IF;
  RESET ROLE;
  -- clienta con user_metadata.phone falsificado (el de la admin)
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_cli, 'role', 'authenticated', 'user_metadata', json_build_object('phone', admin_phone))::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> 0 OR (SELECT count(*) FROM public.offline_sales) <> own_sales THEN RAISE EXCEPTION 'D12 prueba: teléfono falsificado abre datos'; END IF;
  RESET ROLE;
  -- personal de la app anterior y admin: todo
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_staff, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> all_staff OR (SELECT count(*) FROM public.offline_sales) <> all_sales OR (SELECT count(*) FROM public.support_tickets) <> all_tickets
    THEN RAISE EXCEPTION 'D12 prueba: personal no ve todo'; END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> all_staff OR (SELECT count(*) FROM public.offline_sales) <> all_sales OR (SELECT count(*) FROM public.support_tickets) <> all_tickets
    THEN RAISE EXCEPTION 'D12 prueba: admin no ve todo'; END IF;
  RESET ROLE;
  -- vendedora F360 (rol customer en la app): ventas sí; personal no; tickets solo los suyos
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u_seller, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  IF (SELECT count(*) FROM public.staff) <> 0 OR (SELECT count(*) FROM public.offline_sales) <> all_sales OR (SELECT count(*) FROM public.support_tickets) <> seller_tickets
    THEN RAISE EXCEPTION 'D12 prueba: vendedora F360 fuera de lo esperado'; END IF;
  RESET ROLE;
  -- anónimo (app anterior): igual que antes
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SET LOCAL ROLE anon;
  IF (SELECT count(*) FROM public.staff) <> active_staff OR (SELECT count(*) FROM public.offline_sales) <> all_sales
     OR (SELECT count(*) FROM public.channel_inventory) <> all_ci OR (SELECT count(*) FROM public.support_tickets) <> 0
    THEN RAISE EXCEPTION 'D12 prueba: el acceso anónimo de la app anterior cambió'; END IF;
  RESET ROLE;
END $$;
COMMIT;
