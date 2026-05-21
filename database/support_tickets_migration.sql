-- Support tickets: escalations from Hilo chat that need human follow-up.
-- Created when the bot returns escalate=true. Team is notified via WhatsApp
-- (escalate-to-staff edge function) AND can see pending tickets in the admin
-- panel for historical record.

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  customer_phone  TEXT,
  customer_name   TEXT,
  last_messages   JSONB NOT NULL DEFAULT '[]'::jsonb,
  -- Free-form summary the bot or app passes (last user message, topic, etc.)
  topic           TEXT,
  status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'in_progress', 'resolved')),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at     TIMESTAMPTZ,
  resolved_by     UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  notes           TEXT
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status_created
  ON public.support_tickets (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_customer
  ON public.support_tickets (customer_id);

-- Acceso: igual que el resto de la app (channels, staff, offline_sales),
-- esta tabla se lee con el anon key y el control de acceso se hace en la UI
-- (el panel admin solo es accesible si customer.role === 'admin'). NO usamos
-- RLS basada en auth.uid() porque en esta app customers.id != auth.uid()
-- (el cliente se identifica por teléfono, no por el id de Supabase Auth),
-- así que una policy con auth.uid() nunca matchearía y nadie podría leer.
--
-- Los inserts vienen del edge function escalate-to-staff con el service role
-- key, que bypassa RLS de todos modos.
ALTER TABLE public.support_tickets DISABLE ROW LEVEL SECURITY;

-- Limpieza por si una versión anterior de esta migración dejó policies activas.
DROP POLICY IF EXISTS "admins read tickets"        ON public.support_tickets;
DROP POLICY IF EXISTS "admins update tickets"      ON public.support_tickets;
DROP POLICY IF EXISTS "customers read own tickets" ON public.support_tickets;
