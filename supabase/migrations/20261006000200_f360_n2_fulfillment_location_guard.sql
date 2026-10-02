-- N2 (docs/fuxia360/INVENTORY_MODEL.md) · A sales channel's source location can never be a SYSTEM location ("En camino",
-- type 'transit'): that stock is not sellable, so a channel publishing from it would promise pairs that are on a truck.
-- Scope = system locations. Deliberately NOT "sellable = false": that flag means "in-store sales can be recorded here",
-- and Bodega CDMX (the Woo source) is sellable = false by design.
-- Additive: one trigger, no data change (no current target uses a transit location; checked below).
-- Rollback: supabase/rollbacks/20261006000200_f360_n2_fulfillment_location_guard.down.sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM f360.sales_targets t JOIN f360.locations l ON l.id = t.fulfillment_location_id WHERE l.type = 'transit') THEN
    RAISE EXCEPTION 'N2: hay un canal cuyo origen es una ubicación de sistema; corregirlo antes de aplicar esta migración.';
  END IF;
END $$;

CREATE FUNCTION f360.sales_target_location_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM f360.locations WHERE id = NEW.fulfillment_location_id AND type = 'transit') THEN
    RAISE EXCEPTION 'La ubicación de origen de un canal no puede ser "En camino": es una ubicación de sistema y no se vende.';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION f360.sales_target_location_guard() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER sales_targets_location_guard BEFORE INSERT OR UPDATE OF fulfillment_location_id ON f360.sales_targets
  FOR EACH ROW EXECUTE FUNCTION f360.sales_target_location_guard();
COMMENT ON TRIGGER sales_targets_location_guard ON f360.sales_targets IS
  'N2: a channel source location cannot be a system location (transit / "En camino"). Locations cannot become transit later (single-transit index).';
