-- Sobre pedido (20261007001500): re-send every linked size once so the stores pick up backorders = 'notify' now.
-- Only queues pushes (the regular worker sends them); no stock changes. Rollback: nothing to undo (a queue entry).
INSERT INTO f360.stock_sync_queue (target_id, variant_id, reason)
  SELECT vl.target_id, vl.variant_id, 'Sobre pedido: activar' FROM f360.woo_variant_links vl JOIN f360.sales_targets t ON t.id = vl.target_id AND t.active
ON CONFLICT (target_id, variant_id) DO UPDATE SET next_attempt_at = clock_timestamp(), claimed_at = NULL, reason = EXCLUDED.reason;
