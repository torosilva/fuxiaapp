-- Fuxia 360 · pase D8 (2026-10-08) — Carolina: "regístrenoslos como pedido a la medida" (Loafers animal print 38 for Mariana Cantú).
-- Sold by Carolina over WhatsApp / Instagram, already PAID; the model is new (not in the catalog yet: Carolina is creating it) and
-- the pair was ordered from Colombia, arriving next week. Shipped together with her Canutillos Dorado 38 (set aside at Polanco,
-- to be recorded as a store sale in the sellers' app). Same function the store uses (f360_custom_request_create), then marked
-- 'cotizada' as Mario so it shows as in progress. Only first name + phone (the address stays with Carolina).
-- Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
CREATE TEMP TABLE d8 ON COMMIT DROP AS
SELECT public.f360_custom_request_create(jsonb_build_object(
  'target_key', 'woo_production', 'product_name', 'Loafers animal print', 'color', 'Animal print', 'size', '38 (tienda)', 'store_size', '38',
  'name', 'Mariana Cantú', 'phone', '+528110240698', 'country', 'MX',
  'note', 'PAGADO. Venta de Carolina por WhatsApp/Instagram (2026-10-08). Modelo nuevo pedido a Colombia, llega la próxima semana. Enviar a San Pedro Garza García, NL junto con su Canutillos Dorado 38 (apartado en Polanco).'
)) AS r;
SELECT public.f360_custom_request_set((SELECT (r->>'id')::uuid FROM d8), 'cotizada');
SELECT jsonb_build_object('a_la_medida', (SELECT r FROM d8));
COMMIT;
