-- Rollback of Track C · C2 (catalog mapping). Drops only C2 objects. Mapping reviews are lost — export first if needed.
BEGIN;
DROP FUNCTION IF EXISTS public.f360_location_migration_readiness(uuid);
DROP FUNCTION IF EXISTS public.f360_review_legacy_mapping(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public.f360_propose_legacy_mapping(uuid);
DROP FUNCTION IF EXISTS f360.norm_size(text);
DROP FUNCTION IF EXISTS f360.norm(text);
DROP TABLE IF EXISTS f360.legacy_inventory_map;
COMMIT;
