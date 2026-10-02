-- Rollback of 20261006000200_f360_n2_fulfillment_location_guard.sql (no data was changed by the migration).
DROP TRIGGER IF EXISTS sales_targets_location_guard ON f360.sales_targets;
DROP FUNCTION IF EXISTS f360.sales_target_location_guard();
