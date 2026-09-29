-- Rollback of P2.3A. Drops ONLY P2.3A objects and restores the P2.1 event_json.
-- NOTE: SALE events already written to the ledger by order ingestion are NOT removed (the ledger is append-only);
-- after rollback they remain as ordinary history rows. STAGING / approved targets only.
BEGIN;
DROP TRIGGER IF EXISTS inventory_balances_enqueue_stock_sync ON f360.inventory_balances;
DROP FUNCTION IF EXISTS public.f360_resolve_sync_issue(uuid, text);
DROP FUNCTION IF EXISTS public.f360_sync_badge();
DROP FUNCTION IF EXISTS public.f360_list_sync_issues(text);
DROP FUNCTION IF EXISTS public.f360_reconcile_finish(text, jsonb);
DROP FUNCTION IF EXISTS public.f360_reconcile_snapshot(text);
DROP FUNCTION IF EXISTS public.f360_sync_stock_result(text, jsonb);
DROP FUNCTION IF EXISTS public.f360_sync_claim_stock(text, integer);
DROP FUNCTION IF EXISTS public.f360_record_webhook_rejection(text, jsonb, text);
DROP FUNCTION IF EXISTS public.f360_ingest_woo_order(text, jsonb, jsonb);
DROP FUNCTION IF EXISTS f360.target_by_key(text);
DROP FUNCTION IF EXISTS f360.enqueue_stock_sync();
DROP TABLE IF EXISTS f360.reconciliation_runs;
DROP TABLE IF EXISTS f360.woo_webhook_deliveries;
DROP TABLE IF EXISTS f360.woo_order_lines;
DROP TABLE IF EXISTS f360.woo_orders;
DROP TABLE IF EXISTS f360.stock_sync_log;
DROP TABLE IF EXISTS f360.stock_sync_queue;
DROP FUNCTION IF EXISTS f360.variant_label(uuid);
DROP FUNCTION IF EXISTS f360.auto_resolve(uuid, text, text);
DROP FUNCTION IF EXISTS f360.open_exception(uuid, text, text, text, jsonb, uuid, uuid, bigint);
DROP TABLE IF EXISTS f360.sync_exceptions;
-- restore event_json without the business reference (P2.1 definition)
CREATE OR REPLACE FUNCTION f360.event_json(p_event_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'type', e.event_type, 'actor_name', e.actor_name, 'note', e.note,
    'occurred_at', e.occurred_at,
    'total_pairs', (SELECT coalesce(sum(m.quantity), 0) FROM f360.inventory_movements m WHERE m.event_id = e.id),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'product_id', p.id, 'product_name', p.name, 'product_image', coalesce(f360.color_primary_image(c.id), f360.product_primary_image(p.id)),
        'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku, 'quantity', m.quantity,
        'from_location', lf.name, 'to_location', lt.name)
        ORDER BY p.name, c.sort, ps.sort), '[]'::jsonb)
      FROM f360.inventory_movements m
      JOIN f360.product_variants v ON v.id = m.variant_id
      JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id
      JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
      LEFT JOIN f360.locations lf ON lf.id = m.from_location_id
      LEFT JOIN f360.locations lt ON lt.id = m.to_location_id
      WHERE m.event_id = e.id))
  FROM f360.inventory_events e WHERE e.id = p_event_id
$$;
COMMIT;
