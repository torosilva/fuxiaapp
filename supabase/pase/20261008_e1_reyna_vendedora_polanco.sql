-- E1 · Reyna Vega, vendedora de Tienda Polanco en Fuxia 360 (Mario 2026-10-08: "dala de alta como vendedora de la
-- tienda de Polanco para que pueda ver su venta desde la app y el inventario de Polanco").
-- Uses the same owner RPCs the admin would (role, store assignment), acting as Mario (owner): every change is
-- audited in f360.access_changes / seller_auth_events with "Mario Silva" as the actor.
-- Requires: Reyna logged in ONCE in the app with +52 55 1366 7060 (the RPCs refuse a person without an account).
-- The PIN is NOT in this file (never in git): it is set afterwards with f360_set_seller_pin, run by Mario directly.
-- Run: scripts/f360/prod_sql.sh supabase/pase/20261008_e1_reyna_vendedora_polanco.sql (dry-run first, then apply).
BEGIN;
DO $$
DECLARE uid uuid; polanco uuid := '36f4cd87-eae2-403d-9dfb-9cb0d58b79a9';
BEGIN
  SELECT id INTO uid FROM auth.users WHERE phone IN ('525513667060', '5215513667060') ORDER BY created_at LIMIT 1;
  IF uid IS NULL THEN RAISE EXCEPTION 'Reyna todavía no tiene cuenta: que inicie sesión una vez en la app con su teléfono.'; END IF;
  -- act as Mario Silva (owner) so the owner-only RPCs run with their own checks and audit
  PERFORM set_config('request.jwt.claims', json_build_object('sub', 'd11a8d33-cae6-46a5-9d0f-bd2516e8712b', 'role', 'authenticated')::text, true);
  PERFORM public.f360_set_user_role(uid, 'seller', 'Reyna Vega');
  PERFORM public.f360_set_location_assignment(uid, polanco, true);
  RAISE NOTICE 'Reyna Vega (%) = vendedora de Tienda Polanco (falta su PIN)', uid;
END $$;
COMMIT;
