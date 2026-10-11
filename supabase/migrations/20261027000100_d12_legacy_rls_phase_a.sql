-- D12 · Phase A — legacy public tables: signed-in reads restricted to authorized roles; each customer sees only her own records.
-- Scope (authorized 2026-10-11, STAGING only): public.staff, public.offline_sales, public.support_tickets, signed-in (authenticated) paths.
-- The anonymous (anon) policies used by the legacy PIN screen are NOT touched here: they are Phase B (store migration first).
-- Also closes an escalation found during the review: 3 policies trusted auth.jwt() -> user_metadata ->> 'phone', which the user
-- can edit (auth.updateUser({ data })); identity now comes only from public.customers.auth_user_id (my_role / my_phone / my_customer_id).
-- Expected policy fingerprint before (prod = staging, 15 policies): 2ec9510e087e128f34d390291306d617.
-- Rollback: supabase/rollbacks/20261027000100_d12_legacy_rls_phase_a.down.sql

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
