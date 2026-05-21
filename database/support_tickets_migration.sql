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

-- RLS: read for admins, insert from the edge function (service role bypasses).
ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

-- Las policies se DROP-ean primero para que la migración sea idempotente
-- (se puede correr varias veces sin "policy already exists").

-- Admins can see and update all tickets.
DROP POLICY IF EXISTS "admins read tickets" ON public.support_tickets;
CREATE POLICY "admins read tickets" ON public.support_tickets
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = auth.uid()::uuid AND c.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "admins update tickets" ON public.support_tickets;
CREATE POLICY "admins update tickets" ON public.support_tickets
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.customers c
      WHERE c.id = auth.uid()::uuid AND c.role = 'admin'
    )
  );

-- Customers can read their own tickets (so app could show "tu ticket está abierto" if we ever expose it).
DROP POLICY IF EXISTS "customers read own tickets" ON public.support_tickets;
CREATE POLICY "customers read own tickets" ON public.support_tickets
  FOR SELECT
  USING (customer_id = auth.uid()::uuid);
