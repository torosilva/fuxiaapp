-- Fuxia 360 · pase E8 (2026-10-08) — Mario: "¿podemos hacer una prueba con el mío?". ONE test thank-you WhatsApp to Mario's own
-- WhatsApp (his customer row, found by his auth user id — no phone in git), through the real queue + f360-whatsapp + Twilio
-- template. No sale, no points, no stock. ref_type 'prueba' so it never collides with a real purchase. Apply ONLY with prod_sql.sh.
BEGIN;
INSERT INTO f360.whatsapp_outbox (kind, customer_id, phone, variables, ref_type, ref_id)
  SELECT 'thanks', c.id, f360.normalize_phone(c.phone), '{"1": "Polanco", "2": "Mario", "3": "100"}'::jsonb, 'prueba', 'mario-2026-10-08-1'
  FROM public.customers c WHERE c.auth_user_id = 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b'
  ON CONFLICT (kind, ref_type, ref_id) DO NOTHING;
SELECT f360.whatsapp_tick();
SELECT jsonb_build_object('en_cola', (SELECT count(*) FROM f360.whatsapp_outbox WHERE ref_type = 'prueba' AND ref_id = 'mario-2026-10-08-1'));
COMMIT;
