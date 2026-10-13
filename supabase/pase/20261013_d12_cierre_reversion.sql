-- D12 cierre · PRODUCCIÓN · REVERSIÓN: vuelve exactamente al estado de producción del 2026-10-13 (cuerpo = supabase/rollbacks/20261029000200_d12_close_anon_legacy.down.sql).
BEGIN;
DO $$ DECLARE x record; BEGIN
  SELECT * INTO x FROM (select (select md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) from pg_policies where schemaname = 'public' and tablename in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests','channels')) as pol, (select coalesce(md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)),'none') || ' ' || count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon' and table_name in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests')) as gr, (select count(*) from supabase_migrations.schema_migrations where version = '20261029000200') as mig, (select count(*) from pg_proc where proname = 'd12_store_reader') as fn) q;
  IF x.pol <> '3bd28e95980503cf45d894a3ce31d406 17' THEN RAISE EXCEPTION 'D12-CIERRE-REV PRE: políticas distintas a lo revisado (%)', x.pol; END IF;
  IF x.gr <> 'none 0' THEN RAISE EXCEPTION 'D12-CIERRE-REV PRE: permisos anon distintos a lo revisado (%)', x.gr; END IF;
  IF x.mig <> 1 OR x.fn <> 1 THEN RAISE EXCEPTION 'D12-CIERRE-REV PRE: estado de migración inesperado (mig %, fn %)', x.mig, x.fn; END IF;
END $$;
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
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261029000200';
DO $$ DECLARE x record; BEGIN
  SELECT * INTO x FROM (select (select md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) from pg_policies where schemaname = 'public' and tablename in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests','channels')) as pol, (select coalesce(md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)),'none') || ' ' || count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon' and table_name in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests')) as gr, (select count(*) from supabase_migrations.schema_migrations where version = '20261029000200') as mig, (select count(*) from pg_proc where proname = 'd12_store_reader') as fn) q;
  IF x.pol <> 'f5dfca9959e332fa69ae9a1df7881cf1 25' THEN RAISE EXCEPTION 'D12-CIERRE-REV POST: políticas distintas a lo revisado (%)', x.pol; END IF;
  IF x.gr <> 'b28a74994513795a07db0a9e343d0d58 35' THEN RAISE EXCEPTION 'D12-CIERRE-REV POST: permisos anon distintos a lo revisado (%)', x.gr; END IF;
  IF x.mig <> 0 OR x.fn <> 1 THEN RAISE EXCEPTION 'D12-CIERRE-REV POST: estado de migración inesperado (mig %, fn %)', x.mig, x.fn; END IF;
END $$;
COMMIT;
