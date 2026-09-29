-- Fuxia 360 P2.3A fix — f360_list_sync_issues: "created_at" was ambiguous (reconciliation_runs vs sales_targets)
-- in the last-reconciliation block. Found by supabase/staging/f360_p23a_tests.sql. Same signature and grants.
-- Also returns the non-matching items of the last reconciliation so the Avisos screen can show them.

CREATE OR REPLACE FUNCTION public.f360_list_sync_issues(p_status text DEFAULT 'open') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'issues', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'status', e.status, 'message', e.message,
        'product_id', e.product_id, 'product_name', p.name, 'variant_label', CASE WHEN e.variant_id IS NULL THEN NULL ELSE f360.variant_label(e.variant_id) END,
        'woo_order_id', e.woo_order_id, 'occurrences', e.occurrences, 'created_at', e.created_at, 'last_seen_at', e.last_seen_at,
        'resolved_at', e.resolved_at, 'resolved_by_name', e.resolved_by_name, 'resolution_note', e.resolution_note, 'target', t.name)
        ORDER BY e.created_at DESC), '[]')
      FROM (SELECT * FROM f360.sync_exceptions WHERE (p_status = 'all' OR status = p_status) ORDER BY created_at DESC LIMIT 100) e
      JOIN f360.sales_targets t ON t.id = e.target_id LEFT JOIN f360.products p ON p.id = e.product_id),
    'open_count', (SELECT count(*) FROM f360.sync_exceptions WHERE status = 'open'),
    'last_reconciliation', (SELECT jsonb_build_object('checked', rr.checked, 'in_sync', rr.in_sync, 'drifted', rr.drifted, 'missing', rr.missing,
        'at', rr.created_at, 'by', rr.requested_by_name, 'target', t.name, 'items', rr.items)
      FROM f360.reconciliation_runs rr JOIN f360.sales_targets t ON t.id = rr.target_id ORDER BY rr.created_at DESC LIMIT 1),
    'queue', jsonb_build_object('pending', (SELECT count(*) FROM f360.stock_sync_queue), 'failing', (SELECT count(*) FROM f360.stock_sync_queue WHERE attempts > 0),
      'oldest', (SELECT min(requested_at) FROM f360.stock_sync_queue)),
    'recent_pushes', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', l.created_at, 'label', f360.variant_label(l.variant_id), 'ok', l.ok,
        'ats', l.ats, 'woo_before', l.woo_before, 'pushed', l.pushed, 'error', l.error) ORDER BY l.id DESC), '[]')
      FROM (SELECT * FROM f360.stock_sync_log ORDER BY id DESC LIMIT 15) l),
    'recent_orders', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', d.received_at, 'order', d.woo_order_id, 'status', d.woo_status, 'result', d.result,
        'lines', d.detail->'lines') ORDER BY d.id DESC), '[]')
      FROM (SELECT * FROM f360.woo_webhook_deliveries ORDER BY id DESC LIMIT 15) d));
END $$;
