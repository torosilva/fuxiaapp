// STAGING ONLY — removes the SYNTHETIC C3 fixtures created by c3_concurrency.mjs / c3_e2e_prepare.mjs (prefix 'ZZ PRUEBA C3 ')
// or by the demo scripts demo_c3_*.mjs (prefix 'Demo · '). Customers are matched by prefix AND a lab phone (+1555010…).
// Scope, strictly: locations named 'ZZ PRUEBA C3 %' and their legacy channel(s) 'ZZ PRUEBA C3 %', the cutovers/counts/
// audit of those locations, the ledger events that touch only those locations (opening count, sales), the RPC sales of
// those locations with their items and loyalty transactions/purchase items, the synthetic customer/card
// ('ZZ PRUEBA C3 clienta'), roles 'ZZ PRUEBA C3 %', their PINs/sessions/assignments. It REFUSES to run if any of those
// events touches another location. Append-only guards are lifted ONLY inside this one transaction.
// Kept on purpose (append-only audit by design): f360.access_changes, f360.seller_auth_events, public.loyalty_apply_audit.
import { psql } from '../s00a/lib.mjs';

export const C3_PREFIX = 'ZZ PRUEBA C3 ';

export function cleanupC3Fixtures(prefix = C3_PREFIX) {
  if (!/^(ZZ PRUEBA C3 |Demo · )$/.test(prefix)) throw new Error('unknown fixture prefix');
  return psql(`
BEGIN;
CREATE TEMP TABLE zz_loc ON COMMIT DROP AS SELECT id, legacy_channel_id FROM f360.locations WHERE name LIKE '${prefix}%';
CREATE TEMP TABLE zz_ch ON COMMIT DROP AS SELECT id FROM public.channels WHERE name LIKE '${prefix}%';
CREATE TEMP TABLE zz_ev ON COMMIT DROP AS SELECT DISTINCT m.event_id AS id FROM f360.inventory_movements m
  WHERE m.from_location_id IN (SELECT id FROM zz_loc) OR m.to_location_id IN (SELECT id FROM zz_loc);
CREATE TEMP TABLE zz_sale ON COMMIT DROP AS SELECT id, loyalty_transaction_id FROM public.offline_sales WHERE location_id IN (SELECT id FROM zz_loc);
CREATE TEMP TABLE zz_cust ON COMMIT DROP AS SELECT c.id AS customer_id, lc.id AS card_id FROM public.customers c LEFT JOIN public.loyalty_cards lc ON lc.customer_id = c.id
  WHERE c.name LIKE '${prefix}%' AND c.phone LIKE '+1555010%';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM zz_loc WHERE legacy_channel_id IS NOT NULL AND legacy_channel_id NOT IN (SELECT id FROM zz_ch)) THEN
    RAISE EXCEPTION 'cleanup refused: a synthetic location is linked to a real channel';
  END IF;
  IF EXISTS (SELECT 1 FROM f360.inventory_movements m WHERE m.event_id IN (SELECT id FROM zz_ev)
             AND ((m.from_location_id IS NOT NULL AND m.from_location_id NOT IN (SELECT id FROM zz_loc))
               OR (m.to_location_id IS NOT NULL AND m.to_location_id NOT IN (SELECT id FROM zz_loc)))) THEN
    RAISE EXCEPTION 'cleanup refused: a synthetic event touches a real location';
  END IF;
  IF EXISTS (SELECT 1 FROM public.transactions t WHERE t.id IN (SELECT loyalty_transaction_id FROM zz_sale)
             AND t.loyalty_card_id NOT IN (SELECT card_id FROM zz_cust)) THEN
    RAISE EXCEPTION 'cleanup refused: a synthetic sale credited a real card';
  END IF;
END $$;
ALTER TABLE public.channel_inventory DISABLE TRIGGER channel_inventory_freeze;
ALTER TABLE f360.legacy_inventory_map DISABLE TRIGGER legacy_inventory_map_guard;
ALTER TABLE f360.location_cutovers DISABLE TRIGGER location_cutovers_guard;
ALTER TABLE f360.cutover_counts DISABLE TRIGGER cutover_counts_guard;
ALTER TABLE f360.cutover_changes DISABLE TRIGGER cutover_changes_append_only;
ALTER TABLE f360.inventory_movements DISABLE TRIGGER inventory_movements_append_only;
ALTER TABLE f360.inventory_events DISABLE TRIGGER inventory_events_append_only;
ALTER TABLE public.offline_sale_items DISABLE TRIGGER offline_sale_items_append_only;
DELETE FROM public.offline_sale_items WHERE sale_id IN (SELECT id FROM zz_sale);
DELETE FROM public.offline_sales WHERE id IN (SELECT id FROM zz_sale);
DELETE FROM public.purchase_items WHERE transaction_id IN (SELECT id FROM public.transactions WHERE loyalty_card_id IN (SELECT card_id FROM zz_cust));
DELETE FROM public.transactions WHERE loyalty_card_id IN (SELECT card_id FROM zz_cust);
DELETE FROM public.loyalty_cards WHERE id IN (SELECT card_id FROM zz_cust);
DELETE FROM public.customers WHERE id IN (SELECT customer_id FROM zz_cust);
DELETE FROM f360.inventory_balances WHERE location_id IN (SELECT id FROM zz_loc);
UPDATE f360.inventory_balances SET last_event_id = NULL WHERE last_event_id IN (SELECT id FROM zz_ev);
DELETE FROM f360.cutover_changes WHERE cutover_id IN (SELECT id FROM f360.location_cutovers WHERE location_id IN (SELECT id FROM zz_loc));
DELETE FROM f360.cutover_counts WHERE cutover_id IN (SELECT id FROM f360.location_cutovers WHERE location_id IN (SELECT id FROM zz_loc));
DELETE FROM f360.location_cutovers WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM f360.inventory_movements WHERE event_id IN (SELECT id FROM zz_ev);
DELETE FROM f360.inventory_events WHERE id IN (SELECT id FROM zz_ev);
DELETE FROM f360.legacy_inventory_map WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM public.channel_inventory WHERE channel_id IN (SELECT id FROM zz_ch);
ALTER TABLE public.channel_inventory ENABLE TRIGGER channel_inventory_freeze;
ALTER TABLE f360.legacy_inventory_map ENABLE TRIGGER legacy_inventory_map_guard;
ALTER TABLE f360.location_cutovers ENABLE TRIGGER location_cutovers_guard;
ALTER TABLE f360.cutover_counts ENABLE TRIGGER cutover_counts_guard;
ALTER TABLE f360.cutover_changes ENABLE TRIGGER cutover_changes_append_only;
ALTER TABLE f360.inventory_movements ENABLE TRIGGER inventory_movements_append_only;
ALTER TABLE f360.inventory_events ENABLE TRIGGER inventory_events_append_only;
ALTER TABLE public.offline_sale_items ENABLE TRIGGER offline_sale_items_append_only;
DELETE FROM f360.seller_sessions WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM f360.location_assignments WHERE location_id IN (SELECT id FROM zz_loc);
DELETE FROM f360.locations WHERE id IN (SELECT id FROM zz_loc);
DELETE FROM public.channels WHERE id IN (SELECT id FROM zz_ch);
DELETE FROM f360.seller_credentials WHERE auth_user_id IN (SELECT auth_user_id FROM f360.user_roles WHERE display_name LIKE '${prefix}%');
DELETE FROM f360.user_roles WHERE display_name LIKE '${prefix}%';
COMMIT;
SELECT (SELECT count(*) FROM f360.locations WHERE name LIKE '${prefix}%') + (SELECT count(*) FROM public.channels WHERE name LIKE '${prefix}%')
     + (SELECT count(*) FROM f360.user_roles WHERE display_name LIKE '${prefix}%') + (SELECT count(*) FROM public.customers WHERE name LIKE '${prefix}%' AND phone LIKE '+1555010%');`).trim().split('\n').pop();
}
