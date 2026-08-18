-- ============================================================================
-- Fuxia Ballerinas — Overrides de imagen de producto (independiente de la web)
-- ----------------------------------------------------------------------------
-- Problema: las fotos de producto viven en WooCommerce. Si se borra/rompe una
-- imagen en WordPress, la app la muestra en blanco y no hay forma de arreglarla
-- sin tocar la web.
--
-- Solución: una tabla que mapea `wc_product_id -> image_url`. La app la lee y,
-- si existe un override para un producto, usa ESA imagen en vez de la de la web.
-- Las imágenes se suben a un bucket público de Supabase Storage (`product-images`)
-- que vos controlás, sin depender de WordPress. Orden de preferencia en la app:
--   override (Supabase) → imagen de la web → placeholder de marca.
--
-- Lectura pública (solo son URLs de fotos, no hay PII). Escritura: service role
-- o dashboard. Idempotente.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.product_image_overrides (
  wc_product_id INTEGER PRIMARY KEY,          -- id del producto en WooCommerce
  image_url     TEXT NOT NULL,                -- URL pública (bucket Supabase u otra)
  note          TEXT,                         -- opcional: por qué se sobreescribió
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Lectura pública (la app usa la anon key). Sin policy de escritura = solo el
-- service role / dashboard puede insertar o modificar.
ALTER TABLE public.product_image_overrides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "overrides public read" ON public.product_image_overrides;
CREATE POLICY "overrides public read" ON public.product_image_overrides
  FOR SELECT USING (true);

GRANT SELECT ON public.product_image_overrides TO anon, authenticated;

-- Bucket público para hospedar las fotos que subís vos (no la web).
-- Público = servible via /storage/v1/object/public/product-images/... sin auth.
INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;
