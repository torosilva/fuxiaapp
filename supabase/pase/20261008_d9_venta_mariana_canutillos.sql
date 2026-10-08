-- Fuxia 360 · pase D9 (2026-10-08) — Carolina: Mariana Cantú's purchase, two pairs, shipped together to San Pedro Garza García.
--   1 · Canutillos Dorado 38 (Tienda Polanco: 1 on hand, 0 reserved, read 2026-10-08) → recorded as a STORE SALE by Carolina, with the
--       same function the sellers' app uses (f360_record_store_sale_for: master price, never negative, reservation guard, ledger
--       event, idempotency). Mariana is registered as a customer by her WhatsApp (same function as the counter); her points
--       stay HELD until she logs in to the app with that WhatsApp (existing rule, never twice). Paid to Carolina → method 'other'.
--       Carolina has no open shift, so a one-off shift is opened at Polanco for this sale and closed in the same transaction.
--   2 · Her shipping address goes to her customer ficha (CRM C6, f360.customer_save_address); the Loafers animal print 38
--       request (pase D8, 69d55775…) notes that both pairs ship together when the Loafers arrive from Colombia next week.
-- Fixed idempotency key: re-running returns the same sale, never a second one. Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', '31da6b13-70eb-4d89-8019-6f04c3207300', 'role', 'authenticated')::text, true);
CREATE TEMP TABLE d9 ON COMMIT DROP AS SELECT encode(extensions.gen_random_bytes(32), 'hex') AS token;
INSERT INTO f360.seller_sessions (auth_user_id, location_id, token_hash, expires_at)
  SELECT '31da6b13-70eb-4d89-8019-6f04c3207300', '36f4cd87-eae2-403d-9dfb-9cb0d58b79a9', f360.token_hash(token), now() + interval '10 minutes' FROM d9;
SELECT f360.log_seller('31da6b13-70eb-4d89-8019-6f04c3207300', '36f4cd87-eae2-403d-9dfb-9cb0d58b79a9', 'shift_start', jsonb_build_object('pase', 'D9'));
ALTER TABLE d9 ADD COLUMN cust jsonb, ADD COLUMN sale jsonb;
UPDATE d9 SET cust = public.f360_shift_customer_register(token, '+528110240698', 'Mariana Cantú', NULL, '66250', NULL, NULL, '38', 'MX');
DO $$ BEGIN IF NOT ((SELECT cust FROM d9)->>'ok')::boolean THEN RAISE EXCEPTION 'Registro de clienta rechazado: %', (SELECT cust FROM d9); END IF; END $$;
UPDATE d9 SET sale = public.f360_record_store_sale_for(token, 'd9a1c0de-0d9e-4a5b-9c11-202610080009'::uuid,
  '[{"variant_id": "413cacee-f43c-4012-acb0-1fe5f737c005", "quantity": 1}]'::jsonb, 'other', 'Pagado a Carolina por WhatsApp',
  (SELECT id FROM public.customers WHERE phone = '+528110240698' ORDER BY created_at LIMIT 1));
SELECT f360.revoke_seller_sessions('31da6b13-70eb-4d89-8019-6f04c3207300', NULL, 'pase D9 · venta registrada');
SELECT f360.customer_save_address((SELECT id FROM public.customers WHERE phone = '+528110240698' ORDER BY created_at LIMIT 1),
  'Bosques de Chapultepec 405', 'Bosques del Valle', 'San Pedro Garza García', 'Nuevo León', '66250', 'admin');
UPDATE f360.custom_requests SET updated_at = now(), updated_by = 'Mario Silva',
  note = note || ' · ENVÍO (Carolina 2026-10-08): los dos pares juntos — Canutillos Dorado 38 (venta Polanco ' || ((SELECT sale FROM d9)->>'sale_id') || ') + estos Loafers. Dirección en su ficha de clienta.'
  WHERE id = '69d55775-8380-4191-aa13-1abe2f708d62' AND note NOT LIKE '%ENVÍO (Carolina 2026-10-08)%';
SELECT jsonb_build_object('clienta', (SELECT cust FROM d9), 'venta', (SELECT sale FROM d9),
  'direccion', (SELECT f360.customer_full(id)->'address' FROM public.customers WHERE phone = '+528110240698'),
  'polanco_canutillos_38', (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = '413cacee-f43c-4012-acb0-1fe5f737c005' AND location_id = '36f4cd87-eae2-403d-9dfb-9cb0d58b79a9'));
COMMIT;
