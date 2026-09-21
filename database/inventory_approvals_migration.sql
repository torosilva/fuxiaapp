-- ============================================================================
-- inventory_change_requests: cola de aprobaciones para cambios de inventario
-- que hace una vendedora (role='staff'). La admin (role='admin') sigue
-- escribiendo directo a channel_inventory sin pasar por acá.
--
-- Modelo A/A/autoaprobado:
--   · A) Alcance: todo cambio manual (bulk_add, adjust_stock, delete) va a
--     cola cuando lo pide una vendedora.
--   · A) Bloqueante: el cambio se aplica SOLO cuando admin aprueba
--     (via la edge function `inventory-approve` que usa service role para
--     bypass RLS).
--   · Autoaprobado: si el que pide es admin, la app aplica directo a la
--     tabla real y no pasa por acá.
--
-- Nota: las ventas registradas por /vendedora/sale NO pasan por acá — son
-- transacciones reales con QR y siguen descontando stock directo.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inventory_change_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id UUID NOT NULL REFERENCES public.channels(id) ON DELETE CASCADE,
  -- Snapshot del quién pidió: guardamos el ID Y el nombre para que aunque se
  -- borre la vendedora, siga apareciendo en el historial de aprobaciones.
  requested_by_staff_id UUID REFERENCES public.staff(id) ON DELETE SET NULL,
  requested_by_name TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('bulk_add', 'adjust_stock', 'delete')),
  -- payload: shape depende del `action`:
  --   bulk_add     → { product_name, price, sku, image_url, colors[], sizes[], stock_per_combo }
  --   adjust_stock → { channel_inventory_id, delta, current_stock, target_stock }
  --   delete       → { channel_inventory_id, product_name, size, color, remaining }
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  reviewed_by_customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_icr_pending_recent
  ON public.inventory_change_requests(status, created_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_icr_channel_recent
  ON public.inventory_change_requests(channel_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_icr_staff_recent
  ON public.inventory_change_requests(requested_by_staff_id, created_at DESC);

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.inventory_change_requests ENABLE ROW LEVEL SECURITY;

-- staff y admin insertan requests con su propia sesión.
DROP POLICY IF EXISTS "icr staff insert" ON public.inventory_change_requests;
CREATE POLICY "icr staff insert" ON public.inventory_change_requests
  FOR INSERT
  WITH CHECK (public.my_role() IN ('admin', 'staff'));

-- Todos leen (staff ven las propias, admin ve todas). La UI filtra por rol.
DROP POLICY IF EXISTS "icr staff read" ON public.inventory_change_requests;
CREATE POLICY "icr staff read" ON public.inventory_change_requests
  FOR SELECT
  USING (public.my_role() IN ('admin', 'staff'));

-- El UPDATE (marcar approved/rejected) lo hace SOLO el edge function con
-- service_role. Ninguna sesión de app tiene permiso — así una vendedora no
-- puede aprobar sus propias requests. No creamos policy de UPDATE.

COMMENT ON TABLE public.inventory_change_requests IS
  'Cola de cambios de inventario propuestos por vendedoras (role=staff). ' ||
  'Admin los aprueba o rechaza vía la edge function inventory-approve. ' ||
  'Requests aprobadas gatillan la escritura real en channel_inventory.';
