-- S0.0A-A2 — Remove anonymous access to operational tables (P0-3 anon, P0-4 anon, P0-5 anon).
-- PENDING: not in supabase/migrations/, never picked up by `db push`. Apply ONLY per
-- docs/fuxia360/ops/A2_PRODUCTION_RUNBOOK.md, after its prechecks (incl. the seller pre-login BLOCKER) pass.
-- Policy names/definitions verified against the production schema dump (docs/fuxia360/audit/live/schema.sql:1221-1245,1319-1325).
-- Rollback: supabase/rollbacks/20260925000200_s00a_a2_remove_anon_operational_access.down.sql
BEGIN;

-- 1 · Anonymous policies (the anon key could read PINs, read all sales + customer phones, insert sales,
--     and UPDATE ANY COLUMN of channel_inventory incl. price and stock)
DROP POLICY IF EXISTS "anon_insert_offline_sales"  ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_offline_sales"    ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_own_sales"        ON public.offline_sales;
DROP POLICY IF EXISTS "anon_read_active_staff"     ON public.staff;
DROP POLICY IF EXISTS "anon_read_inventory"        ON public.channel_inventory;
DROP POLICY IF EXISTS "anon_update_inventory_sold" ON public.channel_inventory;
DROP POLICY IF EXISTS "anon_read_active_channels"  ON public.channels;

-- 2 · Inventory change requests: only staff/admin (by role) may read or create them. The "any active staff.id"
--     insert path (staff ids were readable by anon) is removed. G5: TO authenticated alone is not enough.
DROP POLICY IF EXISTS "icr read open" ON public.inventory_change_requests;
DROP POLICY IF EXISTS "icr insert with valid staff or admin/staff role" ON public.inventory_change_requests;
CREATE POLICY "icr read staff admin" ON public.inventory_change_requests FOR SELECT TO authenticated
  USING (public.my_role() = ANY (ARRAY['admin'::text, 'staff'::text]));
CREATE POLICY "icr insert staff admin" ON public.inventory_change_requests FOR INSERT TO authenticated
  WITH CHECK (public.my_role() = ANY (ARRAY['admin'::text, 'staff'::text]));

-- 3 · Defense in depth: no table privileges for anon on these tables
REVOKE ALL ON public.staff, public.channel_inventory, public.offline_sales, public.inventory_change_requests,
  public.channels, public.support_tickets FROM anon;

COMMIT;
