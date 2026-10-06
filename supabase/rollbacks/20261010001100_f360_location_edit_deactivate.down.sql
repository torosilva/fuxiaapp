-- Rollback of 20261010001100_f360_location_edit_deactivate.sql.
-- Locations already given of baja stay 'inactive' (reactivate by hand if needed); edits already made stay.
DROP FUNCTION public.f360_deactivate_location(uuid);
DROP FUNCTION public.f360_update_location(uuid, text, text, date, date);
