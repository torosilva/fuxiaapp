// STAGING ONLY — removes the SYNTHETIC transfer fixtures created by s0_transfers_concurrency.mjs and the transfers e2e.
// Scope is strictly: locations named 'ZZ PRUEBA T %', their transfers/lines/audit, the ledger events those transfers created,
// their balances, assignments, and roles named 'ZZ PRUEBA %'. It REFUSES to run if any of those transfers or events touch
// a location outside that set (other than "En camino"). The append-only guards are lifted only inside this one transaction.
// Kept on purpose (append-only by design): f360.access_changes rows about these fixtures.
import { psql } from '../s00a/lib.mjs';

export const ZZ_PREFIX = 'ZZ PRUEBA T ';

export function cleanupTransferFixtures() {
  return psql(`
BEGIN;
CREATE TEMP TABLE zz_loc ON COMMIT DROP AS SELECT id FROM f360.locations WHERE name LIKE '${ZZ_PREFIX}%' AND type <> 'transit';
CREATE TEMP TABLE zz_tr ON COMMIT DROP AS SELECT id, number FROM f360.transfers WHERE from_location_id IN (SELECT id FROM zz_loc) OR to_location_id IN (SELECT id FROM zz_loc);
CREATE TEMP TABLE zz_ev ON COMMIT DROP AS
  SELECT DISTINCT m.event_id AS id FROM f360.inventory_movements m WHERE m.from_location_id IN (SELECT id FROM zz_loc) OR m.to_location_id IN (SELECT id FROM zz_loc)
  UNION SELECT e.id FROM f360.inventory_events e WHERE e.business_reference_type = 'transfer' AND e.business_reference_id IN (SELECT number FROM zz_tr);
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.transfers t WHERE t.id IN (SELECT id FROM zz_tr)
             AND (t.from_location_id NOT IN (SELECT id FROM zz_loc) OR t.to_location_id NOT IN (SELECT id FROM zz_loc))) THEN
    RAISE EXCEPTION 'cleanup refused: a synthetic transfer touches a real location';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.inventory_movements m WHERE m.event_id IN (SELECT id FROM zz_ev)
             AND ((m.from_location_id IS NOT NULL AND m.from_location_id NOT IN (SELECT id FROM zz_loc) AND m.from_location_id <> f360.transit_location())
               OR (m.to_location_id IS NOT NULL AND m.to_location_id NOT IN (SELECT id FROM zz_loc) AND m.to_location_id <> f360.transit_location()))) THEN
    RAISE EXCEPTION 'cleanup refused: a synthetic event touches a real location';
  END IF;
END $$;
-- undo the synthetic events' effect on "En camino" (net 0 when every synthetic transfer finished), then drop empty rows
UPDATE f360.inventory_balances b SET on_hand = b.on_hand - d.q, last_event_id = NULL
  FROM (SELECT variant_id, sum(CASE WHEN to_location_id = f360.transit_location() THEN quantity ELSE -quantity END) AS q
        FROM f360.inventory_movements WHERE event_id IN (SELECT id FROM zz_ev)
          AND f360.transit_location() IN (from_location_id, to_location_id) GROUP BY 1) d
  WHERE b.location_id = f360.transit_location() AND b.variant_id = d.variant_id;
UPDATE f360.inventory_balances SET last_event_id = NULL WHERE last_event_id IN (SELECT id FROM zz_ev);
DELETE FROM f360.inventory_balances b WHERE b.location_id = f360.transit_location() AND b.on_hand = 0
  AND NOT EXISTS (SELECT 1 FROM f360.inventory_movements m WHERE m.variant_id = b.variant_id AND f360.transit_location() IN (m.from_location_id, m.to_location_id)
                  AND m.event_id NOT IN (SELECT id FROM zz_ev));
DELETE FROM f360.inventory_balances WHERE location_id IN (SELECT id FROM zz_loc);
ALTER TABLE f360.transfers DISABLE TRIGGER transfers_guard;
ALTER TABLE f360.transfer_lines DISABLE TRIGGER transfer_lines_guard;
ALTER TABLE f360.transfer_changes DISABLE TRIGGER transfer_changes_append_only;
ALTER TABLE f360.inventory_movements DISABLE TRIGGER inventory_movements_append_only;
ALTER TABLE f360.inventory_events DISABLE TRIGGER inventory_events_append_only;
DELETE FROM f360.transfer_changes WHERE transfer_id IN (SELECT id FROM zz_tr);
DELETE FROM f360.transfer_lines WHERE transfer_id IN (SELECT id FROM zz_tr);
DELETE FROM f360.transfers WHERE id IN (SELECT id FROM zz_tr);
DELETE FROM f360.inventory_movements WHERE event_id IN (SELECT id FROM zz_ev);
DELETE FROM f360.inventory_events WHERE id IN (SELECT id FROM zz_ev);
ALTER TABLE f360.transfers ENABLE TRIGGER transfers_guard;
ALTER TABLE f360.transfer_lines ENABLE TRIGGER transfer_lines_guard;
ALTER TABLE f360.transfer_changes ENABLE TRIGGER transfer_changes_append_only;
ALTER TABLE f360.inventory_movements ENABLE TRIGGER inventory_movements_append_only;
ALTER TABLE f360.inventory_events ENABLE TRIGGER inventory_events_append_only;
DELETE FROM f360.seller_sessions WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM f360.location_assignments WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM f360.locations WHERE id IN (SELECT id FROM zz_loc);
DELETE FROM f360.seller_credentials WHERE auth_user_id IN (SELECT auth_user_id FROM f360.user_roles WHERE display_name LIKE 'ZZ PRUEBA %');
DELETE FROM f360.user_roles WHERE display_name LIKE 'ZZ PRUEBA %';
COMMIT;
SELECT (SELECT count(*) FROM f360.locations WHERE name LIKE '${ZZ_PREFIX}%') + (SELECT count(*) FROM f360.user_roles WHERE display_name LIKE 'ZZ PRUEBA %')
     + (SELECT count(*) FROM f360.inventory_balances WHERE location_id = f360.transit_location() AND on_hand <> 0);`).trim().split('\n').pop();
}
