-- Rollback of 20261007002400 (read-only helpers; nothing else depends on them).
DROP FUNCTION IF EXISTS public.f360_inventory_certification();
DROP FUNCTION IF EXISTS public.f360_scarcity_state(int);
DROP FUNCTION IF EXISTS f360.online_scarcity_reliable(uuid, uuid);
DROP FUNCTION IF EXISTS f360.online_ats_locations(uuid);
DROP FUNCTION IF EXISTS f360.variant_inventory_certified(uuid, uuid);
