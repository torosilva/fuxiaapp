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
