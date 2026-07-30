-- ============================================================================
-- Fuxia Ballerinas — Reglas de puntos + conexión web↔app definitiva (Fase 0)
-- ----------------------------------------------------------------------------
-- Decisiones confirmadas (Mario, jul 2026):
--   • 100 puntos por par.
--   • Niveles: Plata a 300 pts (3 pares) · Oro a 900 pts (9 pares).
--   • Puntos se acreditan al confirmar pago (status 'processing'), con reversa
--     si la orden se cancela o reembolsa.
-- Idempotente.
-- ============================================================================

-- ── 1. Alinear tier_config a la regla oficial ──────────────────────────────
-- Antes decía 501/1201; la app y el webhook usan 300/900. Esta es la fuente de
-- verdad que leen las edge functions para asignar recompensa.
UPDATE public.tier_config SET min_points = 0,   min_pairs = 0 WHERE tier = 'bronze';
UPDATE public.tier_config SET min_points = 300, min_pairs = 3 WHERE tier = 'silver';
UPDATE public.tier_config SET min_points = 900, min_pairs = 9 WHERE tier = 'gold';

-- ── 2. Soporte de reversa en transactions (reembolsos/cancelaciones) ────────
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS reversed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS wc_status   TEXT;

-- ── 3. Órdenes huérfanas: compras web sin clienta registrada todavía ────────
-- Cuando el webhook no encuentra a la clienta (compró antes de bajar la app, o
-- usó otro teléfono/email), en vez de descartar la orden la guardamos aquí.
-- Al registrarse (o agregar email), `link-orders` las acredita retroactivamente.
CREATE TABLE IF NOT EXISTS public.unmatched_orders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wc_order_id INTEGER UNIQUE NOT NULL,
  phone       TEXT,               -- normalizado a +52...
  email       TEXT,               -- lowercase
  total       DECIMAL(10,2) NOT NULL,
  currency    TEXT DEFAULT 'MXN',
  pairs       INTEGER NOT NULL DEFAULT 0,
  points      INTEGER NOT NULL DEFAULT 0,
  items       JSONB NOT NULL DEFAULT '[]'::jsonb,
  wc_status   TEXT,
  matched_at  TIMESTAMPTZ,        -- se setea cuando se acredita a una clienta
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_unmatched_phone ON public.unmatched_orders (phone) WHERE matched_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_unmatched_email ON public.unmatched_orders (email) WHERE matched_at IS NULL;

-- Solo el service role toca esta tabla (webhook + link-orders). Sin acceso cliente.
ALTER TABLE public.unmatched_orders ENABLE ROW LEVEL SECURITY;
-- (sin policies = nadie con anon/authenticated puede leerla; service role bypassa)

-- ── 3b. Anti fuerza-bruta en OTP: contador de intentos por código ──────────
ALTER TABLE public.otp_verifications
  ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;

-- ── 4. Índices que faltaban para el matching del webhook ───────────────────
CREATE INDEX IF NOT EXISTS idx_customers_email ON public.customers (lower(email));
CREATE INDEX IF NOT EXISTS idx_transactions_wc_order ON public.transactions (wc_order_id);
