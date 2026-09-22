-- ============================================================================
-- broadcasts: registro de todos los push manuales que envia la admin a
-- segmentos de clientas. Sirve para auditoria + rate limiting (no dejar
-- mandar mas de 1 broadcast por segmento por dia para no spammear).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sent_by_customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  sent_by_name TEXT NOT NULL,
  -- 'all' | 'bronze' | 'silver' | 'gold' | 'inactive'
  segment TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  -- Datos opcionales para deep-link (e.g., abrir un producto)
  deep_link TEXT,
  recipients_count INT NOT NULL DEFAULT 0,
  expo_status INT,
  expo_body_preview TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_broadcasts_recent
  ON public.broadcasts(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_broadcasts_segment_recent
  ON public.broadcasts(segment, created_at DESC);

ALTER TABLE public.broadcasts ENABLE ROW LEVEL SECURITY;

-- Solo admin lee (para historial en la UI).
DROP POLICY IF EXISTS "broadcasts admin read" ON public.broadcasts;
CREATE POLICY "broadcasts admin read" ON public.broadcasts
  FOR SELECT
  USING (public.my_role() = 'admin');

-- El INSERT lo hace la edge function con service_role — no policy para
-- clientes anon/staff, para que no se pueda spammear desde el frontend.

COMMENT ON TABLE public.broadcasts IS
  'Historial de push notifications manuales que envia la admin a segmentos ' ||
  'de clientas. Cada fila es un envio; recipients_count es cuantos tokens ' ||
  'destino tuvo. Rate limit sugerido: max 1 por segmento por dia.';
