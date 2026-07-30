-- ============================================================================
-- Fuxia Ballerinas — RLS hardening (Fase 0)
-- ----------------------------------------------------------------------------
-- Problema que resuelve: hoy las tablas se leen/escriben con la anon key (que
-- viaja en el bundle de la app). Sin RLS, cualquiera con esa key puede leer
-- TODAS las clientas y modificar puntos. Este archivo:
--   1. Vincula cada customer a su usuario de Supabase Auth (auth_user_id).
--   2. Habilita RLS y agrega políticas de "solo lo mío" en las tablas de clienta.
--   3. Bloquea las tablas operativas a usuarios autenticados (escrituras solo
--      via service role / edge functions).
--
-- Las edge functions usan SERVICE_ROLE_KEY, que bypassa RLS — no se rompen.
-- Aplicar con: psql / Supabase SQL editor. Es idempotente (se puede correr 2x).
-- ============================================================================

-- ── 1. Vínculo customer ↔ auth.users ───────────────────────────────────────
ALTER TABLE public.customers
  ADD COLUMN IF NOT EXISTS auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- Backfill: el auth user se crea con email fake `{phone_sin_+}@fuxia.app`.
UPDATE public.customers c
SET auth_user_id = u.id
FROM auth.users u
WHERE u.email = replace(c.phone, '+', '') || '@fuxia.app'
  AND c.auth_user_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_auth_user_id
  ON public.customers (auth_user_id) WHERE auth_user_id IS NOT NULL;

-- Helper: id(s) de customer del usuario autenticado. STABLE + SECURITY DEFINER
-- para que las políticas no entren en recursión al leer customers.
CREATE OR REPLACE FUNCTION public.my_customer_id()
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.my_phone()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT phone FROM public.customers WHERE auth_user_id = auth.uid() LIMIT 1;
$$;

-- ── 2. Tablas de la clienta: "solo lo mío" ─────────────────────────────────

-- customers ------------------------------------------------------------------
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "customers self read"    ON public.customers;
DROP POLICY IF EXISTS "customers self update"  ON public.customers;
DROP POLICY IF EXISTS "customers self insert"  ON public.customers;

-- Leo mi fila, y las filas de gente que YO referí (para la pantalla de referrals).
CREATE POLICY "customers self read" ON public.customers
  FOR SELECT USING (
    auth_user_id = auth.uid()
    OR referred_by = public.my_customer_id()
  );

CREATE POLICY "customers self update" ON public.customers
  FOR UPDATE USING (auth_user_id = auth.uid())
  WITH CHECK (auth_user_id = auth.uid());

-- Al crear perfil, el cliente inserta su propia fila con SU auth.uid().
CREATE POLICY "customers self insert" ON public.customers
  FOR INSERT WITH CHECK (auth_user_id = auth.uid());

-- loyalty_cards --------------------------------------------------------------
ALTER TABLE public.loyalty_cards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cards self read"   ON public.loyalty_cards;
DROP POLICY IF EXISTS "cards self insert" ON public.loyalty_cards;

CREATE POLICY "cards self read" ON public.loyalty_cards
  FOR SELECT USING (customer_id = public.my_customer_id());

-- Insert al crear perfil. NO hay policy de UPDATE: los puntos SOLO los mueve
-- el service role (webhook / claim-sale). Así el cliente no puede auto-editarse.
CREATE POLICY "cards self insert" ON public.loyalty_cards
  FOR INSERT WITH CHECK (customer_id = public.my_customer_id());

-- transactions ---------------------------------------------------------------
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tx self read" ON public.transactions;
CREATE POLICY "tx self read" ON public.transactions
  FOR SELECT USING (
    loyalty_card_id IN (SELECT id FROM public.loyalty_cards WHERE customer_id = public.my_customer_id())
  );
-- Sin insert/update para el cliente: las escribe el service role.

-- purchase_items -------------------------------------------------------------
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "items self read" ON public.purchase_items;
CREATE POLICY "items self read" ON public.purchase_items
  FOR SELECT USING (
    transaction_id IN (
      SELECT t.id FROM public.transactions t
      JOIN public.loyalty_cards lc ON lc.id = t.loyalty_card_id
      WHERE lc.customer_id = public.my_customer_id()
    )
  );

-- rewards --------------------------------------------------------------------
ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rewards self read" ON public.rewards;
CREATE POLICY "rewards self read" ON public.rewards
  FOR SELECT USING (
    loyalty_card_id IN (SELECT id FROM public.loyalty_cards WHERE customer_id = public.my_customer_id())
  );

-- wishlists ------------------------------------------------------------------
ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wishlist self all" ON public.wishlists;
CREATE POLICY "wishlist self all" ON public.wishlists
  FOR ALL USING (customer_id = public.my_customer_id())
  WITH CHECK (customer_id = public.my_customer_id());

-- push_tokens ----------------------------------------------------------------
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push self all" ON public.push_tokens;
CREATE POLICY "push self all" ON public.push_tokens
  FOR ALL USING (customer_id = public.my_customer_id())
  WITH CHECK (customer_id = public.my_customer_id());

-- ── 3. Tablas operativas (tienda / bazar / admin) ──────────────────────────
-- Hoy se leen con anon key SIN login → cualquiera en internet las ve.
-- Mínimo viable: exigir sesión autenticada para leer; escrituras solo service
-- role. TODO Fase 1: mover validación de PIN de staff a edge function y
-- restringir estas tablas por rol (staff.pin NO debería ser legible por el
-- cliente). Por ahora esto ya cierra el acceso anónimo, que es el hueco grande.

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['channels','staff','channel_inventory','offline_sales','support_tickets']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
    EXECUTE format('DROP POLICY IF EXISTS "auth read %1$s" ON public.%1$I;', t);
    EXECUTE format(
      'CREATE POLICY "auth read %1$s" ON public.%1$I FOR SELECT USING (auth.role() = ''authenticated'');',
      t
    );
  END LOOP;
END $$;

-- offline_sales: además de lo anterior, la clienta puede ver las ventas ligadas
-- a su teléfono (para reclamar / ver pendientes en tracking).
DROP POLICY IF EXISTS "offline_sales own by phone" ON public.offline_sales;
CREATE POLICY "offline_sales own by phone" ON public.offline_sales
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND (customer_id = public.my_customer_id() OR customer_phone = public.my_phone())
  );

-- ============================================================================
-- Rollback de emergencia (si algo se rompe en producción, correr esto y avisar):
--   ALTER TABLE public.customers      DISABLE ROW LEVEL SECURITY;
--   ALTER TABLE public.loyalty_cards  DISABLE ROW LEVEL SECURITY;
--   ... (repetir por tabla)
-- ============================================================================
