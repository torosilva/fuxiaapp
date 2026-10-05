-- Fuxia 360 · Pase a producción (opción B) · F1 pre-checks — SOLO LECTURA.
-- Pegar COMPLETO en Supabase → proyecto de PRODUCCIÓN (tgzg…) → SQL Editor → Run.
-- No cambia nada: corre dentro de una transacción READ ONLY y termina con ROLLBACK. Devuelve solo conteos (sin datos de clientas).
-- Referencia: docs/fuxia360/ops/PASE_F1_MIGRATIONS_AUDIT.md §P-1…P-10. (P-5 y P-6 se verifican en F2 / con la CLI.)
BEGIN READ ONLY;

WITH norm AS (
  SELECT id, CASE
      WHEN d ~ '^521\d{10}$' THEN '+52' || substr(d, 4)
      WHEN d ~ '^52\d{10}$' THEN '+' || d
      WHEN d ~ '^0(44|45)\d{10}$' THEN '+52' || substr(d, 4)
      WHEN d ~ '^\d{10}$' AND left(phone, 1) <> '+' THEN '+52' || d
      ELSE CASE WHEN left(phone, 1) = '+' THEN '+' || d END END AS n
  FROM (SELECT id, phone, regexp_replace(coalesce(phone, ''), '\D', '', 'g') AS d FROM public.customers) x
)
SELECT * FROM (VALUES
  ('P-1 grupos de clientas duplicadas por teléfono normalizado', (SELECT count(*) FROM (SELECT n FROM norm WHERE n IS NOT NULL GROUP BY n HAVING count(*) > 1) g)::text, '0'),
  ('P-1b clientas en esos grupos', (SELECT coalesce(sum(c), 0) FROM (SELECT count(*) c FROM norm WHERE n IS NOT NULL GROUP BY n HAVING count(*) > 1) g)::text, '0'),
  ('P-2 clientas con teléfono fuera de formato +52…', (SELECT count(*) FROM public.customers WHERE phone !~ '^\+\d{8,15}$')::text, '0'),
  ('P-2b total de clientas', (SELECT count(*) FROM public.customers)::text, '(info)'),
  ('P-3 existencias inválidas (stock<0, sold<0 o sold>stock)', (SELECT count(*) FROM public.channel_inventory WHERE stock < 0 OR sold < 0 OR sold > stock)::text, '0'),
  ('P-4 esquema f360 ya existe', (to_regnamespace('f360') IS NOT NULL)::text, 'false'),
  ('P-4 tablas offline_sale_items / loyalty_apply_audit ya existen', ((to_regclass('public.offline_sale_items') IS NOT NULL) OR (to_regclass('public.loyalty_apply_audit') IS NOT NULL))::text, 'false'),
  ('P-4 funciones public.f360_* o loyalty_apply ya existen', (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid = p.pronamespace WHERE s.nspname = 'public' AND (p.proname LIKE 'f360\_%' OR p.proname = 'loyalty_apply'))::text, '0'),
  ('P-4 columnas nuevas ya existentes', (SELECT count(*) FROM information_schema.columns WHERE table_schema = 'public' AND
      (table_name, column_name) IN (('customers', 'source'), ('customers', 'postal_code'), ('customers', 'birthday_day'), ('offline_sales', 'idempotency_key'), ('transactions', 'idempotency_key')))::text, '0'),
  ('P-7 extensión pg_cron instalada', (SELECT count(*) FROM pg_extension WHERE extname = 'pg_cron')::text, '(info)'),
  ('P-7 extensión pgcrypto instalada', (SELECT count(*) FROM pg_extension WHERE extname = 'pgcrypto')::text, '1'),
  ('P-7 extensión supabase_vault instalada', (SELECT count(*) FROM pg_extension WHERE extname = 'supabase_vault')::text, '(info)'),
  ('P-7 pg_net disponible para instalar', (SELECT count(*) FROM pg_available_extensions WHERE name = 'pg_net')::text, '1'),
  ('P-8 bucket product-images existe', (SELECT count(*) FROM storage.buckets WHERE id = 'product-images')::text, '(info)'),
  ('P-8 objetos f360/ en el bucket', (SELECT count(*) FROM storage.objects WHERE bucket_id = 'product-images' AND name LIKE 'f360/%')::text, '0'),
  ('P-9 tarjetas con QR que no empieza con FX-', (SELECT count(*) FROM public.loyalty_cards WHERE qr_code NOT LIKE 'FX-%')::text, '0'),
  ('P-9b total de tarjetas', (SELECT count(*) FROM public.loyalty_cards)::text, '(info)'),
  ('P-10 políticas RLS que dan acceso a anon (A2 pendiente si > 0)', (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND 'anon' = ANY (roles))::text, '(info)'),
  ('P-10 políticas anon_insert_offline_sales / anon_update_inventory_sold / anon_read_active_staff', (SELECT count(*) FROM pg_policies WHERE schemaname = 'public'
      AND policyname IN ('anon_insert_offline_sales', 'anon_update_inventory_sold', 'anon_read_active_staff'))::text, '(info: 3 = A2 no aplicado)')
) AS t(chequeo, resultado, esperado);

ROLLBACK;
