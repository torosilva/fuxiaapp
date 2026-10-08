-- Fuxia 360 · pase E10 (2026-10-08) — Mario: "mándale un mensaje de ejemplo a Carolina como si fuera Ada". ONE example of the
-- thank-you for a customer WITH the app (kind thanks_member, template fuxia_gracias_socia) to Carolina's own WhatsApp (found by her
-- auth user id — no phone in git), with Ada's sale values (Polanco, 100 points, total 100). No sale, no points. ref_type 'prueba'.
-- If Meta has not approved fuxia_gracias_socia yet, it waits in the queue and goes out the moment it is approved (max 3 days).
BEGIN;
INSERT INTO f360.whatsapp_outbox (kind, customer_id, phone, variables, ref_type, ref_id)
  SELECT 'thanks_member', c.id, f360.normalize_phone(c.phone), '{"1": "Polanco", "2": "Ada", "3": "100", "4": "100"}'::jsonb, 'prueba', 'carolina-ada-2026-10-08'
  FROM public.customers c WHERE c.auth_user_id = '31da6b13-70eb-4d89-8019-6f04c3207300'
  ON CONFLICT (kind, ref_type, ref_id) DO NOTHING;
SELECT f360.whatsapp_tick();
SELECT jsonb_build_object('en_cola', (SELECT count(*) FROM f360.whatsapp_outbox WHERE ref_type = 'prueba' AND ref_id = 'carolina-ada-2026-10-08'));
COMMIT;
