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
