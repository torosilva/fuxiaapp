-- STAGING ONLY data: production orders #5347 / #5351 received on 2026-10-08 13:56–15:11 UTC through production webhooks #3/#4
-- (copied from staging4, paused 2026-10-10 21:21 UTC). Kept as evidence (Mario 2026-10-10). Idempotent; refuses any other DB.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_staging4' AND active) OR EXISTS (SELECT 1 FROM f360.sales_targets WHERE key = 'woo_production' AND orders_mode = 'on') THEN
    RAISE EXCEPTION 'ABORT: esta base no es staging';
  END IF;
END $$;
INSERT INTO f360.environment_foreign_events (target_id, woo_order_id, source_env, source_store, note, evidence, noted_by)
SELECT t.id, x.id, 'production', 'fuxiaballerinas.com',
       'Recibido indebidamente por los webhooks #3/#4 de producción (copiados de staging4); pausados el 2026-10-10 21:21 UTC.',
       jsonb_build_object('deliveries', (SELECT jsonb_agg(jsonb_build_object('id', d.id, 'topic', d.topic, 'status', d.woo_status, 'result', d.result, 'received_at', d.received_at) ORDER BY d.id)
                                         FROM f360.woo_webhook_deliveries d WHERE d.target_id = t.id AND d.woo_order_id = x.id),
                          'woo_webhooks', '[3, 4]', 'diagnosis', 'docs/fuxia360/ISOLATION_DIAGNOSIS_2026-10-10.md'),
       'Mario (decisión 2026-10-10) · registrado por Claude'
FROM f360.sales_targets t CROSS JOIN (VALUES (5347::bigint), (5351::bigint)) x(id)
WHERE t.key = 'woo_staging4'
ON CONFLICT (target_id, woo_order_id) DO NOTHING;
SELECT woo_order_id, source_env, jsonb_array_length(evidence->'deliveries') AS deliveries FROM f360.environment_foreign_events ORDER BY 1;
COMMIT;
