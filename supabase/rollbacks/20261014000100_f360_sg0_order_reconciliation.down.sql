-- Rollback of 20261014000100_f360_sg0_order_reconciliation. Deploy the previous f360-woo-sync FIRST (the new one calls
-- f360_commerce_reconcile_begin / _diff). Run log rows of kind 'reconcile' are KEPT (audit): the restored CHECK is NOT VALID,
-- so it applies to new rows only.
DROP FUNCTION IF EXISTS public.f360_commerce_reconcile_diff(text, jsonb);
DROP FUNCTION IF EXISTS public.f360_commerce_reconcile_begin(text, integer);

CREATE OR REPLACE VIEW f360.commerce_source_health AS
  SELECT t.key AS target_key, s.last_attempt_at, s.last_success_at, s.last_error, s.last_error_at, s.cursor_modified,
         (SELECT max(d.received_at) FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.result IN ('applied', 'not_paid', 'duplicate')) AS last_webhook_at,
         CASE WHEN s.last_success_at IS NULL THEN 'UNVERIFIED'
              WHEN s.last_success_at < now() - interval '60 minutes' THEN 'STALE'
              ELSE 'VERIFIED' END AS freshness
  FROM f360.sales_targets t LEFT JOIN f360.commerce_sync_state s ON s.target_id = t.id
  WHERE t.active AND NOT t.is_production;

CREATE OR REPLACE FUNCTION public.f360_channel_mode(p_target_key text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('key', key, 'is_production', is_production, 'active', active, 'catalog_mode', catalog_mode,
    'stock_sync_mode', stock_sync_mode, 'stock_policy', stock_policy)
  FROM f360.sales_targets WHERE key = p_target_key
$$;

DROP FUNCTION IF EXISTS f360.sg0_orders_path_on(f360.sales_targets);
DROP FUNCTION IF EXISTS f360.sg0_order_target(text);

ALTER TABLE f360.commerce_sync_runs DROP CONSTRAINT commerce_sync_runs_kind_check;
ALTER TABLE f360.commerce_sync_runs ADD CONSTRAINT commerce_sync_runs_kind_check CHECK (kind IN ('poll', 'backfill')) NOT VALID;
