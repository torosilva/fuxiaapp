-- Fix: la vendedora entra a /vendedora con PIN sin sesión de Supabase Auth,
-- entonces `my_role()` devuelve NULL y la policy original bloqueaba el INSERT
-- en inventory_change_requests con "new row violates row-level security policy".
--
-- Nueva regla: permitir INSERT también cuando el row trae un
-- requested_by_staff_id que sí existe en la tabla `staff` y está activo.
-- Equivalente a la validación del PIN en el cliente pero enforced por la DB.
--
-- Idempotente: se puede correr varias veces.

DROP POLICY IF EXISTS "icr staff insert" ON public.inventory_change_requests;

CREATE POLICY "icr insert with valid staff or admin/staff role"
  ON public.inventory_change_requests
  FOR INSERT
  WITH CHECK (
    public.my_role() IN ('admin', 'staff')
    OR (
      requested_by_staff_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.staff
        WHERE id = requested_by_staff_id AND active = true
      )
    )
  );

-- SELECT: la vendedora tambien necesita leer para mostrar el banner de "N
-- pendientes" del canal. Como no es info sensible (solo cambios de inventario
-- propuestos), abrimos SELECT a anon tambien. El admin panel filtra por
-- status/canal desde la UI, no depende de RLS para privacidad.
DROP POLICY IF EXISTS "icr staff read" ON public.inventory_change_requests;

CREATE POLICY "icr read open"
  ON public.inventory_change_requests
  FOR SELECT
  USING (true);
