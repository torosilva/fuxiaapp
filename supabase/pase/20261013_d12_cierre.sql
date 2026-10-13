-- D12 cierre de la entrada vieja de NIP · PRODUCCIÓN · aplicar (Mario 2026-10-13: "Ya"). Cuerpo = supabase/migrations/20261029000200_d12_close_anon_legacy.sql (sha256 347f46b9533326be…), idéntico a lo probado en staging.
-- Guardas: antes = huella de producción leída hoy (igual a staging antes del cierre); después = huella de staging después del cierre.
-- Reversión: supabase/pase/20261013_d12_cierre_reversion.sql
BEGIN;
DO $$ DECLARE x record; BEGIN
  SELECT * INTO x FROM (select (select md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) from pg_policies where schemaname = 'public' and tablename in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests','channels')) as pol, (select coalesce(md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)),'none') || ' ' || count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon' and table_name in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests')) as gr, (select count(*) from supabase_migrations.schema_migrations where version = '20261029000200') as mig, (select count(*) from pg_proc where proname = 'd12_store_reader') as fn) q;
  IF x.pol <> 'f5dfca9959e332fa69ae9a1df7881cf1 25' THEN RAISE EXCEPTION 'D12-CIERRE PRE: políticas distintas a lo revisado (%)', x.pol; END IF;
  IF x.gr <> 'b28a74994513795a07db0a9e343d0d58 35' THEN RAISE EXCEPTION 'D12-CIERRE PRE: permisos anon distintos a lo revisado (%)', x.gr; END IF;
  IF x.mig <> 0 OR x.fn <> 1 THEN RAISE EXCEPTION 'D12-CIERRE PRE: estado de migración inesperado (mig %, fn %)', x.mig, x.fn; END IF;
END $$;
-- >>> cuerpo de la migración
-- D12 fase B · cierre de la entrada vieja (NIP sin cuenta). Mario 2026-10-13: "Ya" (plan directo: se deja solo la
-- entrada con cuenta; Carolina da de alta a las vendedoras de Guadalajara/Contreras cuando quiera).
-- Sin sesión (anon) ya no se lee el personal (NIP), ni ventas, ni inventario, ni solicitudes, y no se escribe nada en las
-- tablas de la app anterior. Quedan igual: la venta por turno F360 (RPC SECURITY DEFINER), lo que ven/escriben las cuentas
-- autorizadas (fase A), el reclamo de puntos (Edge Function claim-sale, llave de servicio) y la lista de tiendas (channels).
-- También quita las 2 políticas que confiaban en user_metadata.phone (editable por la usuaria): channels/channel_inventory.
-- La pantalla vieja de la app responde "PIN incorrecto" a todo NIP.
-- Rollback: supabase/rollbacks/20261029000200_d12_close_anon_legacy.down.sql

-- 1 · políticas anónimas de la app anterior
DROP POLICY anon_read_active_staff ON public.staff;                 -- NIP del personal
DROP POLICY anon_insert_offline_sales ON public.offline_sales;      -- registrar ventas
DROP POLICY anon_read_offline_sales ON public.offline_sales;        -- leer todas las ventas
DROP POLICY anon_read_own_sales ON public.offline_sales;            -- ídem (USING true)
DROP POLICY anon_update_inventory_sold ON public.channel_inventory;  -- modificar inventario
DROP POLICY anon_read_inventory ON public.channel_inventory;        -- leer inventario
-- 2 · solicitudes de inventario: legibles por cualquiera (rol public, USING true) → solo cuentas de tienda
DROP POLICY "icr read open" ON public.inventory_change_requests;
CREATE POLICY "d12 icr read store roles" ON public.inventory_change_requests FOR SELECT TO authenticated
  USING (public.d12_store_reader());
-- 3 · identidad falsificable (user_metadata.phone): hay equivalentes con my_role() ("channels admin write",
--     "inventory staff write")
DROP POLICY admins_all_channels ON public.channels;
DROP POLICY admins_all_inventory ON public.channel_inventory;
-- 4 · sin permisos de tabla para anon (defensa en profundidad: aunque alguien agregue una política anon por error)
REVOKE ALL ON public.staff, public.offline_sales, public.offline_sale_items, public.channel_inventory,
  public.support_tickets, public.inventory_change_requests FROM anon;
-- <<< cuerpo
DO $$ DECLARE x record; BEGIN
  SELECT * INTO x FROM (select (select md5(string_agg(format('%s|%s|%s|%s|%s|%s', tablename, policyname, cmd, roles::text, coalesce(qual,''), coalesce(with_check,'')), E'\n' order by tablename, policyname)) || ' ' || count(*) from pg_policies where schemaname = 'public' and tablename in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests','channels')) as pol, (select coalesce(md5(string_agg(format('%s|%s|%s', table_name, grantee, privilege_type), ',' order by table_name, grantee, privilege_type)),'none') || ' ' || count(*) from information_schema.role_table_grants where table_schema = 'public' and grantee = 'anon' and table_name in ('staff','offline_sales','offline_sale_items','channel_inventory','support_tickets','inventory_change_requests')) as gr, (select count(*) from supabase_migrations.schema_migrations where version = '20261029000200') as mig, (select count(*) from pg_proc where proname = 'd12_store_reader') as fn) q;
  IF x.pol <> '3bd28e95980503cf45d894a3ce31d406 17' THEN RAISE EXCEPTION 'D12-CIERRE POST: políticas distintas a lo revisado (%)', x.pol; END IF;
  IF x.gr <> 'none 0' THEN RAISE EXCEPTION 'D12-CIERRE POST: permisos anon distintos a lo revisado (%)', x.gr; END IF;
  IF x.mig <> 0 OR x.fn <> 1 THEN RAISE EXCEPTION 'D12-CIERRE POST: estado de migración inesperado (mig %, fn %)', x.mig, x.fn; END IF;
END $$;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261029000200', 'd12_close_anon_legacy', ARRAY[$m$-- D12 fase B · cierre de la entrada vieja (NIP sin cuenta). Mario 2026-10-13: "Ya" (plan directo: se deja solo la
-- entrada con cuenta; Carolina da de alta a las vendedoras de Guadalajara/Contreras cuando quiera).
-- Sin sesión (anon) ya no se lee el personal (NIP), ni ventas, ni inventario, ni solicitudes, y no se escribe nada en las
-- tablas de la app anterior. Quedan igual: la venta por turno F360 (RPC SECURITY DEFINER), lo que ven/escriben las cuentas
-- autorizadas (fase A), el reclamo de puntos (Edge Function claim-sale, llave de servicio) y la lista de tiendas (channels).
-- También quita las 2 políticas que confiaban en user_metadata.phone (editable por la usuaria): channels/channel_inventory.
-- La pantalla vieja de la app responde "PIN incorrecto" a todo NIP.
-- Rollback: supabase/rollbacks/20261029000200_d12_close_anon_legacy.down.sql

-- 1 · políticas anónimas de la app anterior
DROP POLICY anon_read_active_staff ON public.staff;                 -- NIP del personal
DROP POLICY anon_insert_offline_sales ON public.offline_sales;      -- registrar ventas
DROP POLICY anon_read_offline_sales ON public.offline_sales;        -- leer todas las ventas
DROP POLICY anon_read_own_sales ON public.offline_sales;            -- ídem (USING true)
DROP POLICY anon_update_inventory_sold ON public.channel_inventory;  -- modificar inventario
DROP POLICY anon_read_inventory ON public.channel_inventory;        -- leer inventario
-- 2 · solicitudes de inventario: legibles por cualquiera (rol public, USING true) → solo cuentas de tienda
DROP POLICY "icr read open" ON public.inventory_change_requests;
CREATE POLICY "d12 icr read store roles" ON public.inventory_change_requests FOR SELECT TO authenticated
  USING (public.d12_store_reader());
-- 3 · identidad falsificable (user_metadata.phone): hay equivalentes con my_role() ("channels admin write",
--     "inventory staff write")
DROP POLICY admins_all_channels ON public.channels;
DROP POLICY admins_all_inventory ON public.channel_inventory;
-- 4 · sin permisos de tabla para anon (defensa en profundidad: aunque alguien agregue una política anon por error)
REVOKE ALL ON public.staff, public.offline_sales, public.offline_sale_items, public.channel_inventory,
  public.support_tickets, public.inventory_change_requests FROM anon;$m$]);
COMMIT;
