-- D12 fase A · PRODUCCIÓN · REVERSIÓN exacta. Cuerpo = supabase/rollbacks/20261027000100_d12_legacy_rls_phase_a.down.sql (sha256 89baff21fb527fc4…). Vuelve a la huella 2ec9510e (15).
BEGIN;
DO $$ BEGIN
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s|%s', tablename, policyname, permissive, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('staff', 'offline_sales', 'support_tickets')) <> 'af59dcb17262410f50c250b4be082926 12' THEN RAISE EXCEPTION 'D12 PRE-REV: políticas staff/offline_sales/support_tickets distintas a lo esperado (af59dcb17262410f50c250b4be082926 12)'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) FROM pg_policies WHERE schemaname = 'public' AND roles::text LIKE '%anon%') <> 'a8609ffb7700f84e1104acf7e2b76732 7' THEN RAISE EXCEPTION 'D12 PRE-REV: políticas anon cambiaron'; END IF;
  IF (SELECT md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)) FROM information_schema.role_table_grants WHERE table_schema = 'public' AND table_name IN ('staff', 'offline_sales', 'offline_sale_items', 'support_tickets', 'channel_inventory', 'channels', 'inventory_change_requests')) <> '27b518b74bdc4cebf24308338a5df00b' THEN RAISE EXCEPTION 'D12 PRE-REV: permisos de tabla cambiaron'; END IF;
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
