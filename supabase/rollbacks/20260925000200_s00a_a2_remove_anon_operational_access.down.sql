-- Rollback of S0.0A-A2: restores the exact production definitions dumped in docs/fuxia360/audit/live/schema.sql.
-- WARNING: re-opens P0-3/P0-4/P0-5 anonymous access. Use only if A2 breaks a critical flow, then fix forward.
BEGIN;
DROP POLICY IF EXISTS "icr read staff admin" ON public.inventory_change_requests;
DROP POLICY IF EXISTS "icr insert staff admin" ON public.inventory_change_requests;
CREATE POLICY "icr read open" ON public.inventory_change_requests FOR SELECT USING (true);
CREATE POLICY "icr insert with valid staff or admin/staff role" ON public.inventory_change_requests FOR INSERT
  WITH CHECK (((public.my_role() = ANY (ARRAY['admin'::text, 'staff'::text])) OR ((requested_by_staff_id IS NOT NULL)
    AND (EXISTS (SELECT 1 FROM public.staff WHERE ((staff.id = inventory_change_requests.requested_by_staff_id) AND (staff.active = true)))))));
CREATE POLICY "anon_insert_offline_sales"  ON public.offline_sales FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "anon_read_offline_sales"    ON public.offline_sales FOR SELECT TO anon USING (true);
CREATE POLICY "anon_read_own_sales"        ON public.offline_sales FOR SELECT TO anon USING (true);
CREATE POLICY "anon_read_active_staff"     ON public.staff FOR SELECT TO anon USING ((active = true));
CREATE POLICY "anon_read_inventory"        ON public.channel_inventory FOR SELECT TO anon USING (true);
CREATE POLICY "anon_update_inventory_sold" ON public.channel_inventory FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "anon_read_active_channels"  ON public.channels FOR SELECT TO anon USING ((active = true));
GRANT ALL ON TABLE public.staff, public.channel_inventory, public.offline_sales, public.inventory_change_requests,
  public.channels, public.support_tickets TO anon;
COMMIT;
