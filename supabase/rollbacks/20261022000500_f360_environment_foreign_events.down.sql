-- Rollback of 20261022000500: restores the 20261022000400 view text, then drops the marks table (and its rows).
CREATE OR REPLACE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at,
         coalesce(cc.corrected_market, o.market) AS market, coalesce(cc.corrected_currency, o.currency) AS currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
  LEFT JOIN f360.commerce_currency_scope cc ON cc.target_id = o.target_id AND cc.woo_order_id = o.woo_order_id AND cc.active
), enriched AS (
  SELECT b.*, ev.id AS evidence_id, ev.gateway_result, ev.transaction_ref, ev.queried_at AS evidence_at, ev.woo_status AS evidence_woo_status,
         d.id AS decision_id, d.decision, d.comment AS decision_comment, d.decided_by_name, d.decided_at, d.duplicate_of,
         d.woo_status_seen, d.facts_hash_seen,
         x.excluded, x.reason AS exclusion_reason,
         dup.candidates AS duplicate_candidates, rtr.retry_paid_order
  FROM base b
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_evidence e WHERE e.target_id = b.target_id AND e.woo_order_id = b.woo_order_id ORDER BY e.id DESC LIMIT 1) ev ON true
  LEFT JOIN LATERAL (SELECT * FROM f360.sales_rec_decisions d WHERE d.target_id = b.target_id AND d.woo_order_id = b.woo_order_id ORDER BY d.id DESC LIMIT 1) d ON true
  LEFT JOIN f360.sales_rec_analytics_scope x ON x.target_id = b.target_id AND x.woo_order_id = b.woo_order_id
  LEFT JOIN LATERAL (
    SELECT array_agg(b2.woo_order_id ORDER BY b2.woo_order_id) AS candidates FROM base b2
    WHERE b2.target_id = b.target_id AND b2.woo_order_id <> b.woo_order_id AND b2.market = b.market AND b2.currency = b.currency
      AND b2.order_total = b.order_total AND b.order_total > 0
      AND b2.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND abs(extract(epoch FROM b2.created_at - b.created_at)) <= 48 * 3600
      AND b.ever_paid AND b2.ever_paid                                  -- a duplicate matters only when both were paid
      AND (b.woo_customer_id IS NULL OR b2.woo_customer_id IS NULL OR b.woo_customer_id = b2.woo_customer_id)) dup ON true
  LEFT JOIN LATERAL (                                                   -- unpaid attempt followed by a paid one = retry, not duplicate
    SELECT min(b3.woo_order_id) AS retry_paid_order FROM base b3
    WHERE NOT b.ever_paid AND b3.ever_paid AND b3.target_id = b.target_id AND b3.market = b.market AND b3.currency = b.currency
      AND b3.lines_sig IS NOT DISTINCT FROM b.lines_sig AND b.lines_sig IS NOT NULL
      AND b3.created_at > b.created_at AND b3.created_at - b.created_at <= interval '48 hours'
      AND (b.woo_customer_id IS NULL OR b3.woo_customer_id IS NULL OR b.woo_customer_id = b3.woo_customer_id)) rtr ON true
), fin AS (
  SELECT e.*,
    CASE
      WHEN NOT e.ever_paid AND e.gateway_result = 'approved' THEN 'CONTRADICTORIA'
      WHEN NOT e.ever_paid THEN 'SIN_COBRO'
      WHEN e.gateway_result = 'order_missing' THEN 'NO_EXISTE_EN_WOO'
      WHEN e.woo_status = 'refunded' OR (e.refund_total > 0 AND e.refund_total >= e.order_total) THEN 'REEMBOLSADO'
      WHEN e.refund_total > 0 THEN 'REEMBOLSO_PARCIAL'
      WHEN e.gateway_result = 'rejected' THEN 'CONTRADICTORIA'
      WHEN e.evidence_id IS NOT NULL AND e.transaction_ref IS NOT NULL AND e.gateway_result IN ('approved', 'transaction_only') THEN 'COBRO_CON_TRANSACCION'
      WHEN e.evidence_id IS NOT NULL THEN 'PAGO_SIN_TRANSACCION'
      ELSE 'PAGO_REGISTRADO_WOO'
    END AS financial_state
  FROM enriched e
), flagged AS (
  SELECT f.*, coalesce((SELECT jsonb_agg(fl) FROM (
    SELECT jsonb_build_object('code', 'NO_CONCRETADO', 'kind', 'no_concretado',
             'why', 'Nunca se registró pago. Estado en WooCommerce: ' || f.woo_status || '.') fl WHERE NOT f.ever_paid
    UNION ALL
    SELECT jsonb_build_object('code', 'REINTENTO_PAGADO', 'kind', 'info', 'paid_order', f.retry_paid_order,
             'why', 'Posible reintento: el pedido #' || f.retry_paid_order || ' se pagó con los mismos productos y el mismo total en menos de 48 h. ' ||
                    'No se da por hecho que sea la misma compra: confírmalo con la evidencia (misma clienta) antes de clasificarlo.')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está ' || CASE f.woo_status WHEN 'cancelled' THEN 'cancelado' WHEN 'failed' THEN 'fallido' ELSE f.woo_status END || ', sin reembolso registrado.')
      WHERE f.ever_paid AND f.woo_status IN ('cancelled', 'failed') AND f.refund_total = 0
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGADO_SIN_EVIDENCIA', 'kind', 'financiera', 'why',
             CASE WHEN f.paid_at IS NULL THEN 'Woo lo marca pagado (' || f.woo_status || ') pero no tiene fecha de pago.'
                  WHEN f.payment_method IS NULL THEN 'Pagado sin método de pago registrado.'
                  ELSE 'Consultado en WooCommerce: pagado sin número de transacción de la pasarela.' END)
      WHERE f.ever_paid AND f.woo_status IN ('processing', 'completed', 'on-hold')
        AND (f.paid_at IS NULL OR f.payment_method IS NULL OR f.financial_state = 'PAGO_SIN_TRANSACCION')
    UNION ALL
    SELECT jsonb_build_object('code', 'EVIDENCIA_CONTRADICE', 'kind', 'financiera', 'why',
             CASE WHEN f.ever_paid THEN 'Woo lo tiene como pagado pero la nota de la pasarela dice rechazado.'
                  ELSE 'La nota de la pasarela dice aprobado pero Woo no registró el pago.' END)
      WHERE f.financial_state = 'CONTRADICTORIA'
    UNION ALL
    SELECT jsonb_build_object('code', 'NO_EXISTE_EN_WOO', 'kind', CASE WHEN f.ever_paid THEN 'financiera' ELSE 'info' END,
             'why', 'Al consultarlo (' || to_char(f.evidence_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI') ||
                    ') WooCommerce ya no tenía este pedido' || CASE WHEN f.ever_paid THEN ', y Fuxia 360 lo capturó con pago registrado.' ELSE '.' END)
      WHERE f.gateway_result = 'order_missing'
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_PRUEBA', 'kind', 'revision', 'why',
             CASE WHEN f.payment_method ~* '(prueba|test|sandbox)' THEN 'Método de pago de prueba: ' || f.payment_method || '.'
                  ELSE 'Pedido pagado por 0.' END)
      WHERE f.payment_method ~* '(prueba|test|sandbox)' OR (f.ever_paid AND f.order_total = 0)
    UNION ALL
    SELECT jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'kind', 'revision', 'candidates', to_jsonb(f.duplicate_candidates),
             'why', 'Dos pedidos PAGADOS con el mismo total y los mismos productos, misma clienta (o sin cuenta), en menos de 48 h: #' ||
                    array_to_string(f.duplicate_candidates, ', #') || '. Es un candidato: confirma o descarta.')
      WHERE f.duplicate_candidates IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_CORREGIDA', 'kind', 'info', 'why',
             'WooCommerce registra ' || cc.original_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (mercado ' || cc.original_market ||
             '). Corrección comercial: ' || cc.corrected_currency || ' ' || to_char(f.order_total, 'FM999,999,999,990.00') || ' (' || cc.corrected_market ||
             ') · ' || cc.decided_by_name || ': "' || cc.reason || '". Sin conversión cambiaria; no cambia el estado de pago.')
      FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active
    UNION ALL
    SELECT jsonb_build_object('code', 'MONEDA_SOSPECHOSA', 'kind', 'revision', 'why', sus.why || ' Confírmalo y, si aplica, registra la corrección de moneda.')
      FROM (SELECT f360.currency_suspicion(f.target_id, f.woo_order_id) AS why) sus
      WHERE sus.why IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM f360.commerce_currency_scope cc WHERE cc.target_id = f.target_id AND cc.woo_order_id = f.woo_order_id AND cc.active)
    UNION ALL
    SELECT jsonb_build_object('code', 'REEMBOLSO', 'kind', 'reembolso',
             'why', 'Reembolso registrado en WooCommerce por ' || f.refund_total || ' ' || f.currency || '.')
      WHERE f.refund_total > 0 OR f.woo_status = 'refunded'
  ) q), '[]'::jsonb) AS flags
  FROM fin f
)
SELECT g.*,
  EXISTS (SELECT 1 FROM jsonb_array_elements(g.flags) z WHERE z->>'kind' = 'financiera') AS has_financial,
  CASE
    WHEN g.decision IS NULL THEN NULL
    WHEN g.decision = 'venta_confirmada' AND g.financial_state IN ('SIN_COBRO', 'CONTRADICTORIA', 'REEMBOLSADO', 'PAGO_SIN_TRANSACCION', 'NO_EXISTE_EN_WOO')
      THEN 'Confirmada como venta, pero la evidencia financiera dice: ' || g.financial_state || '. No cuenta como cobro.'
    WHEN g.decision = 'no_se_concreto' AND g.financial_state IN ('COBRO_CON_TRANSACCION', 'PAGO_REGISTRADO_WOO')
      THEN 'Marcada "no se concretó", pero hay pago registrado y ningún reembolso.'
    WHEN g.decision IN ('duplicado', 'prueba') AND g.ever_paid AND g.refund_total = 0 AND g.woo_status NOT IN ('cancelled', 'failed', 'refunded')
      THEN 'Marcada "' || g.decision || '", pero tiene pago registrado y ningún reembolso.'
    WHEN g.decision = 'reembolso' AND g.refund_total = 0 AND g.woo_status <> 'refunded'
      THEN 'Marcada "reembolso", pero WooCommerce no tiene ningún reembolso registrado.'
  END AS conflict
FROM flagged g;


DROP TABLE IF EXISTS f360.environment_foreign_events;
