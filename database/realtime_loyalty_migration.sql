-- ============================================================================
-- Fuxia Ballerinas — Realtime en loyalty_cards
-- ----------------------------------------------------------------------------
-- Permite que la app reciba al instante los cambios de puntos de SU tarjeta
-- (para disparar la animación de celebración en tiempo real, sin reabrir).
-- RLS ("cards self read") ya limita a la propia tarjeta de cada clienta.
-- Idempotente.
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'loyalty_cards'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.loyalty_cards;
  END IF;
END $$;
