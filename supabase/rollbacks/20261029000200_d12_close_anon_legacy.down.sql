-- Rollback of 20261029000200_d12_close_anon_legacy: restores exactly the production state of 2026-10-13 (policy definitions
-- copied from pg_policies; anon held all 7 table privileges on these 5 tables and none on offline_sale_items).
GRANT DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.staff, public.offline_sales, public.channel_inventory,
  public.support_tickets, public.inventory_change_requests TO anon;

DROP POLICY "d12 icr read store roles" ON public.inventory_change_requests;
CREATE POLICY "icr read open" ON public.inventory_change_requests AS PERMISSIVE FOR SELECT TO public USING (true);

CREATE POLICY anon_read_active_staff ON public.staff AS PERMISSIVE FOR SELECT TO anon USING ((active = true));
CREATE POLICY anon_insert_offline_sales ON public.offline_sales AS PERMISSIVE FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY anon_read_offline_sales ON public.offline_sales AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY anon_read_own_sales ON public.offline_sales AS PERMISSIVE FOR SELECT TO anon USING (true);
CREATE POLICY anon_update_inventory_sold ON public.channel_inventory AS PERMISSIVE FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY anon_read_inventory ON public.channel_inventory AS PERMISSIVE FOR SELECT TO anon USING (true);

CREATE POLICY admins_all_channels ON public.channels AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM customers
  WHERE ((customers.phone = ((auth.jwt() -> 'user_metadata'::text) ->> 'phone'::text)) AND (customers.role = ANY (ARRAY['admin'::text, 'staff'::text]))))));
CREATE POLICY admins_all_inventory ON public.channel_inventory AS PERMISSIVE FOR ALL TO authenticated
  USING ((EXISTS ( SELECT 1 FROM customers
  WHERE ((customers.phone = ((auth.jwt() -> 'user_metadata'::text) ->> 'phone'::text)) AND (customers.role = ANY (ARRAY['admin'::text, 'staff'::text]))))));
