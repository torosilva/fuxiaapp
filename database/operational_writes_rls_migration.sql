-- ============================================================================
-- Fuxia Ballerinas — RLS: escrituras operativas por rol
-- ----------------------------------------------------------------------------
-- Problema que resuelve: `rls_migration.sql` activó RLS en las tablas operativas
-- (channels, staff, channel_inventory, offline_sales, support_tickets) pero SOLO
-- creó políticas de SELECT. Sin políticas de INSERT/UPDATE/DELETE, Postgres
-- rechaza en silencio TODA escritura hecha desde la app con la sesión del usuario
-- (anon key + JWT), que es justo como escriben las pantallas de admin/vendedora:
--   · admin/channel/[id].tsx        → insert channel_inventory
--   · admin/import-woo.tsx          → insert channel_inventory (importación Woo)
--   · admin/bazar-template.tsx      → insert channel_inventory (plantilla)
--   · admin/channel-new.tsx         → insert channels
--   · admin/staff-new.tsx           → insert staff
--   · vendedora/sale.tsx            → update channel_inventory + insert offline_sales
-- Efecto: no se podía cargar inventario NI registrar ventas.
--
-- Este archivo agrega políticas de escritura gateadas por rol (customers.role):
--   · admin  → gestiona canales, staff e inventario.
--   · staff  → registra ventas y descuenta stock (update inventario + insert venta).
--
-- REQUISITO OPERATIVO: el dispositivo de la tienda/bazar debe tener iniciada la
-- sesión de una cuenta con role 'admin' o 'staff'. El PIN de vendedora valida
-- quién opera, pero la escritura en la BD va con la sesión de Supabase del
-- dispositivo. (Este era el "gap de Fase 1" del RUNBOOK-fase0.md.)
--
-- Las edge functions con SERVICE_ROLE_KEY bypassan RLS — no se ven afectadas.
-- Idempotente: se puede correr varias veces. Aplicar en el SQL Editor de Supabase.
-- ============================================================================

-- ── Helper: rol del usuario autenticado ─────────────────────────────────────
-- STABLE + SECURITY DEFINER para no recursar al leer customers dentro de las
-- políticas de otras tablas.
CREATE OR REPLACE FUNCTION public.my_role()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

-- ── channels (solo admin escribe) ───────────────────────────────────────────
DROP POLICY IF EXISTS "channels admin write" ON public.channels;
CREATE POLICY "channels admin write" ON public.channels
  FOR ALL
  USING (public.my_role() = 'admin')
  WITH CHECK (public.my_role() = 'admin');

-- ── staff (solo admin escribe) ──────────────────────────────────────────────
DROP POLICY IF EXISTS "staff admin write" ON public.staff;
CREATE POLICY "staff admin write" ON public.staff
  FOR ALL
  USING (public.my_role() = 'admin')
  WITH CHECK (public.my_role() = 'admin');

-- ── channel_inventory (admin y staff escriben) ──────────────────────────────
-- admin: carga/edita inventario (importación Woo, plantilla, alta manual).
-- staff: descuenta stock (update sold) al registrar una venta.
DROP POLICY IF EXISTS "inventory staff write" ON public.channel_inventory;
CREATE POLICY "inventory staff write" ON public.channel_inventory
  FOR ALL
  USING (public.my_role() IN ('admin', 'staff'))
  WITH CHECK (public.my_role() IN ('admin', 'staff'));

-- ── offline_sales (admin y staff insertan la venta) ─────────────────────────
-- Nota: la política de SELECT "offline_sales own by phone" (de rls_migration.sql)
-- se conserva para que la clienta vea sus ventas por teléfono. Esta añade la
-- escritura del punto de venta.
DROP POLICY IF EXISTS "offline_sales staff insert" ON public.offline_sales;
CREATE POLICY "offline_sales staff insert" ON public.offline_sales
  FOR INSERT
  WITH CHECK (public.my_role() IN ('admin', 'staff'));

DROP POLICY IF EXISTS "offline_sales staff update" ON public.offline_sales;
CREATE POLICY "offline_sales staff update" ON public.offline_sales
  FOR UPDATE
  USING (public.my_role() IN ('admin', 'staff'))
  WITH CHECK (public.my_role() IN ('admin', 'staff'));

-- ============================================================================
-- Verificación:
--   SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname='public' AND tablename='channel_inventory';
--   -- Debe listar la de SELECT + "inventory staff write" (ALL).
--
-- Rollback (si algo se rompe):
--   DROP POLICY IF EXISTS "channels admin write"       ON public.channels;
--   DROP POLICY IF EXISTS "staff admin write"          ON public.staff;
--   DROP POLICY IF EXISTS "inventory staff write"      ON public.channel_inventory;
--   DROP POLICY IF EXISTS "offline_sales staff insert" ON public.offline_sales;
--   DROP POLICY IF EXISTS "offline_sales staff update" ON public.offline_sales;
-- ============================================================================
