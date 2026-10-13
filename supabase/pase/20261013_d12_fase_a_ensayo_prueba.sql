-- D12 fase A · PRODUCCIÓN · ENSAYO aplicar + prueba por perfil (solo --dry-run).
BEGIN;
DO $$ BEGIN
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, permissive, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('staff', 'offline_sales', 'support_tickets')) <> '2ec9510e087e128f34d390291306d617 15' THEN RAISE EXCEPTION 'D12 PRE: políticas staff/offline_sales/support_tickets distintas a lo esperado (2ec9510e087e128f34d390291306d617 15)'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12 PRE: políticas anon cambiaron'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'support_tickets', 'channel_inventory', 'channels', 'inventory_change_requests')) <> '27b518b74bdc4cebf24308338a5df00b' THEN RAISE EXCEPTION 'D12 PRE: permisos de tabla cambiaron'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.d12_store_reader() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    coalesce(public.my_role() IN ('admin', 'staff'), false)
    OR EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = auth.uid() AND r.role IN ('owner', 'operator', 'seller')));
$$;
CREATE OR REPLACE FUNCTION public.d12_staff_reader() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    coalesce(public.my_role() IN ('admin', 'staff'), false)
    OR EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = auth.uid() AND r.role IN ('owner', 'operator')));
$$;
REVOKE ALL ON FUNCTION public.d12_store_reader(), public.d12_staff_reader() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.d12_store_reader(), public.d12_staff_reader() TO authenticated, service_role;

DROP POLICY "auth read staff" ON public.staff;             -- any session: every staff row with pin
DROP POLICY staff_read_own ON public.staff;                -- any session: every active staff row with pin
DROP POLICY admins_all_staff ON public.staff;              -- user_metadata phone; "staff admin write" (my_role() = 'admin') stays
CREATE POLICY "d12 staff read store roles" ON public.staff FOR SELECT TO authenticated
  USING (public.d12_staff_reader());

DROP POLICY "auth read offline_sales" ON public.offline_sales;   -- any session: every sale (phones, totals, items)
DROP POLICY customers_read_own_sales ON public.offline_sales;    -- user_metadata phone (editable by the user)
DROP POLICY admins_staff_all_sales ON public.offline_sales;      -- user_metadata phone; staff insert/update policies stay (my_role)
CREATE POLICY "d12 offline_sales read store roles" ON public.offline_sales FOR SELECT TO authenticated
  USING (public.d12_store_reader());

DROP POLICY "auth read support_tickets" ON public.support_tickets;   -- any session: every ticket
CREATE POLICY "d12 support_tickets read staff" ON public.support_tickets FOR SELECT TO authenticated
  USING (coalesce(public.my_role() IN ('admin', 'staff'), false));
CREATE POLICY "d12 support_tickets read own" ON public.support_tickets FOR SELECT TO authenticated
  USING (customer_id IS NOT NULL AND customer_id = public.my_customer_id());
INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES ('20261027000100', 'd12_legacy_rls_phase_a');
DO $$ BEGIN
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, permissive, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('staff', 'offline_sales', 'support_tickets')) <> 'af59dcb17262410f50c250b4be082926 12' THEN RAISE EXCEPTION 'D12 POST: políticas staff/offline_sales/support_tickets distintas a lo esperado (af59dcb17262410f50c250b4be082926 12)'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12 POST: políticas anon cambiaron'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'support_tickets', 'channel_inventory', 'channels', 'inventory_change_requests')) <> '27b518b74bdc4cebf24308338a5df00b' THEN RAISE EXCEPTION 'D12 POST: permisos de tabla cambiaron'; END IF;
END $$;
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
