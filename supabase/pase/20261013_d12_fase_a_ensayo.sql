-- D12 fase A · PRODUCCIÓN · ENSAYO (solo --dry-run): aplica, comprueba, revierte y comprueba en UNA transacción que se deshace.
BEGIN;
DO $$ BEGIN
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, permissive, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('staff', 'offline_sales', 'support_tickets')) <> '2ec9510e087e128f34d390291306d617 15' THEN RAISE EXCEPTION 'D12 PRE: políticas staff/offline_sales/support_tickets distintas a lo esperado (2ec9510e087e128f34d390291306d617 15)'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12 PRE: políticas anon cambiaron'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'support_tickets', 'channel_inventory', 'channels', 'inventory_change_requests')) <> '27b518b74bdc4cebf24308338a5df00b' THEN RAISE EXCEPTION 'D12 PRE: permisos de tabla cambiaron'; END IF;
END $$;
-- D12 · Phase A — legacy public tables: signed-in reads restricted to authorized roles; each customer sees only her own records.
-- Scope (authorized 2026-10-11, STAGING only): public.staff, public.offline_sales, public.support_tickets, signed-in (authenticated) paths.
-- The anonymous (anon) policies used by the legacy PIN screen are NOT touched here: they are Phase B (store migration first).
-- Also closes an escalation found during the review: 3 policies trusted auth.jwt() -> user_metadata ->> 'phone', which the user
-- can edit (auth.updateUser({ data })); identity now comes only from public.customers.auth_user_id (my_role / my_phone / my_customer_id).
-- Expected policy fingerprint before (prod = staging, 15 policies): 2ec9510e087e128f34d390291306d617.

-- Who may read store data while signed in: legacy admin/staff (public.customers.role) or a Fuxia 360 owner/operator/seller.
-- The Fuxia 360 seller is included because her shift at a legacy location opens vendedora/home and sales-today (offline_sales).
CREATE OR REPLACE FUNCTION public.d12_store_reader() RETURNS boolean
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND (
    coalesce(public.my_role() IN ('admin', 'staff'), false)
    OR EXISTS (SELECT 1 FROM f360.user_roles r WHERE r.auth_user_id = auth.uid() AND r.role IN ('owner', 'operator', 'seller')));
$$;
-- Who may read public.staff (column pin) while signed in: legacy admin/staff or a Fuxia 360 owner/operator (the legacy PIN screen
-- opened with a session, "modo anterior", looks a seller up by pin). Fuxia 360 sellers never read it (their shift is
-- f360_start_seller_shift). SECURITY DEFINER because authenticated has no grant on f360.user_roles.
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

-- offline_sales: store roles read all; a customer reads only hers ("offline_sales own by phone" stays: my_customer_id / my_phone).
DROP POLICY "auth read offline_sales" ON public.offline_sales;   -- any session: every sale (phones, totals, items)
DROP POLICY customers_read_own_sales ON public.offline_sales;    -- user_metadata phone (editable by the user)
DROP POLICY admins_staff_all_sales ON public.offline_sales;      -- user_metadata phone; staff insert/update policies stay (my_role)
CREATE POLICY "d12 offline_sales read store roles" ON public.offline_sales FOR SELECT TO authenticated
  USING (public.d12_store_reader());

-- support_tickets: admin/staff read all; a customer reads only her own. Tickets are created by escalate-to-staff (service role).
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
-- Rollback of 20261027000100_d12_legacy_rls_phase_a: restores the exact pre-D12 policies (definitions copied from pg_policies,
-- identical in production and staging). Afterwards the fingerprint must be 2ec9510e087e128f34d390291306d617 again.
DROP POLICY "d12 support_tickets read own" ON public.support_tickets;
DROP POLICY "d12 support_tickets read staff" ON public.support_tickets;
DROP POLICY "d12 offline_sales read store roles" ON public.offline_sales;
DROP POLICY "d12 staff read store roles" ON public.staff;
DROP FUNCTION public.d12_store_reader();
DROP FUNCTION public.d12_staff_reader();

CREATE POLICY "auth read staff" ON public.staff AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));
CREATE POLICY staff_read_own ON public.staff AS PERMISSIVE FOR SELECT TO authenticated USING ((active = true));
CREATE POLICY admins_all_staff ON public.staff AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM customers
  WHERE ((customers.phone = ((auth.jwt() -> 'user_metadata'::text) ->> 'phone'::text)) AND (customers.role = 'admin'::text)))));

CREATE POLICY "auth read offline_sales" ON public.offline_sales AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));
CREATE POLICY customers_read_own_sales ON public.offline_sales AS PERMISSIVE FOR SELECT TO authenticated
  USING ((customer_phone = ((auth.jwt() -> 'user_metadata'::text) ->> 'phone'::text)));
CREATE POLICY admins_staff_all_sales ON public.offline_sales AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM customers
  WHERE ((customers.phone = ((auth.jwt() -> 'user_metadata'::text) ->> 'phone'::text)) AND (customers.role = ANY (ARRAY['admin'::text, 'staff'::text]))))));

CREATE POLICY "auth read support_tickets" ON public.support_tickets AS PERMISSIVE FOR SELECT TO public USING ((auth.role() = 'authenticated'::text));
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261027000100';
DO $$ BEGIN
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, permissive, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('staff', 'offline_sales', 'support_tickets')) <> '2ec9510e087e128f34d390291306d617 15' THEN RAISE EXCEPTION 'D12 POST-REV: políticas staff/offline_sales/support_tickets distintas a lo esperado (2ec9510e087e128f34d390291306d617 15)'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12 POST-REV: políticas anon cambiaron'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'support_tickets', 'channel_inventory', 'channels', 'inventory_change_requests')) <> '27b518b74bdc4cebf24308338a5df00b' THEN RAISE EXCEPTION 'D12 POST-REV: permisos de tabla cambiaron'; END IF;
END $$;
COMMIT;
