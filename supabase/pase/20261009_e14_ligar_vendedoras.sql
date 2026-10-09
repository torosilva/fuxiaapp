-- Fuxia 360 · pase E14 (2026-10-09) — Reyna (and any pending seller) signed in with her WhatsApp but her account was not linked
-- to the seller row Carolina created (customers.auth_user_id stayed NULL), so the app took her to "crear perfil" and failed
-- ("Error creando perfil": her number already exists). This does the link the WhatsApp login should have done: for every
-- PENDING seller whose customers row has no account yet, link the existing sign-in account of the SAME number
-- (<digits>@fuxia.app, created by whatsapp-otp). The existing activation trigger then activates the seller (role + store).
-- Sellers who never signed in (no account) are untouched. Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
UPDATE public.customers c SET auth_user_id = u.id
  FROM f360.sellers s, auth.users u
  WHERE s.customer_id = c.id AND s.status = 'pendiente' AND c.auth_user_id IS NULL
    AND u.email = regexp_replace(c.phone, '\D', '', 'g') || '@fuxia.app'
    AND NOT EXISTS (SELECT 1 FROM public.customers x WHERE x.auth_user_id = u.id);
SELECT jsonb_build_object('sellers', (SELECT jsonb_agg(jsonb_build_object('name', s.name, 'status', s.status, 'linked', c.auth_user_id IS NOT NULL) ORDER BY s.name)
  FROM f360.sellers s JOIN public.customers c ON c.id = s.customer_id));
COMMIT;
