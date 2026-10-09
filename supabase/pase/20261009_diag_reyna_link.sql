-- DIAGNOSTIC ONLY — run with: scripts/f360/prod_sql.sh --dry-run (always rolled back). Reproduces what whatsapp-otp does on
-- Reyna's login (link customers.auth_user_id) to see why the link does not stick (2026-10-09).
BEGIN;
UPDATE public.customers c SET auth_user_id = u.id
  FROM auth.users u
  WHERE c.name = 'Reyna Vega' AND c.auth_user_id IS NULL AND u.email = right(c.phone, 12) || '@fuxia.app';
SELECT jsonb_build_object('linked', (SELECT auth_user_id IS NOT NULL FROM public.customers WHERE name = 'Reyna Vega'),
  'seller', (SELECT status FROM f360.sellers WHERE name = 'Reyna Vega'));
COMMIT;
