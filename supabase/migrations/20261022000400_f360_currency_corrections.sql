-- Fuxia 360 · Corrección comercial auditada de moneda/mercado (Mario 2026-10-10: #2095 es COP 405,000, no USD). STAGING. ADDITIVE.
-- WooCommerce and Commerce Facts keep the SOURCE record (USD 405,000, market ROW, cancelled). A correction is a separate,
-- append-only event (who, when, reason, server-captured evidence; revert = new event). No FX conversion: the amount is read as
-- the corrected currency. The payment state never changes (a correction never makes an order "paid").
-- Consumers that follow the correction (reporting market/currency): Growth War Room (growth_market_block, growth_adjustments via
-- f360.commerce_orders_reporting) and Conciliación (sales_rec_cases). Commerce Facts (técnico), Medición/measurement_sales and the
-- executive dashboard keep showing the source until their own pase (documented).
-- Alert: f360.currency_suspicion() flags orders whose currency disagrees with billing country (MX/CO), a single-currency gateway
-- (ePayco = COP, Mercado Pago México = MXN; PayPal is NOT assumed: staging4 has COP orders completed with PayPal) or price range
-- ("Moneda sospechosa" in Conciliación). It never corrects anything by itself.
-- Depends on 20261021000100, 20261022000100/0200/0300.
-- Rollback: supabase/rollbacks/20261022000400_f360_currency_corrections.down.sql

CREATE TABLE f360.commerce_currency_corrections (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id          uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id       bigint NOT NULL,
  action             text NOT NULL CHECK (action IN ('correct', 'revert')),
  original_currency  text NOT NULL,
  original_market    text NOT NULL,
  corrected_currency text CHECK (corrected_currency IN ('MXN', 'COP', 'USD')),
  corrected_market   text CHECK (corrected_market IN ('MX', 'CO', 'ROW')),
  reason             text NOT NULL CHECK (length(btrim(reason)) BETWEEN 10 AND 1000),
  evidence           jsonb NOT NULL,                 -- captured by the server from Commerce Facts, never sent by the client
  supersedes         bigint UNIQUE REFERENCES f360.commerce_currency_corrections(id),
  decided_by         uuid NOT NULL,
  decided_by_name    text NOT NULL,
  decided_at         timestamptz NOT NULL DEFAULT now(),
  CHECK ((action = 'correct') = (corrected_currency IS NOT NULL AND corrected_market IS NOT NULL)),
  CHECK (corrected_currency IS NULL OR (corrected_currency, corrected_market) IN (('MXN', 'MX'), ('COP', 'CO'), ('USD', 'ROW')))
);
CREATE INDEX commerce_currency_corrections_order_idx ON f360.commerce_currency_corrections (target_id, woo_order_id, id DESC);
ALTER TABLE f360.commerce_currency_corrections ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER commerce_currency_corrections_append_only BEFORE UPDATE OR DELETE ON f360.commerce_currency_corrections
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

CREATE VIEW f360.commerce_currency_scope AS
  SELECT DISTINCT ON (target_id, woo_order_id) id, target_id, woo_order_id, action = 'correct' AS active, original_currency, original_market,
         corrected_currency, corrected_market, reason, decided_by_name, decided_at
  FROM f360.commerce_currency_corrections ORDER BY target_id, woo_order_id, id DESC;

-- Why an order's currency looks wrong (NULL = nothing suspicious). Billing country is only used for MX / CO.
CREATE FUNCTION f360.currency_suspicion(p_target uuid, p_order bigint) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT nullif(concat_ws(' ',
    CASE WHEN o.billing_country IN ('MX', 'CO') AND o.billing_country <> o.market
         THEN format('Factura en %s pero la moneda es %s (mercado %s).', o.billing_country, o.currency, o.market) END,
    CASE WHEN o.payment_method = 'epayco' AND o.currency <> 'COP' THEN format('ePayco cobra en COP pero el pedido está en %s.', o.currency)
         WHEN o.payment_method LIKE 'woo-mercado-pago%' AND o.currency <> 'MXN' THEN format('Mercado Pago (México) cobra en MXN pero el pedido está en %s.', o.currency) END,
    CASE WHEN o.currency = 'USD' AND l.max_unit > 5000 THEN format('Precio por par de %s USD: fuera de rango para dólares.', round(l.max_unit))
         WHEN o.currency = 'MXN' AND l.max_unit > 60000 THEN format('Precio por par de %s MXN: fuera de rango para pesos mexicanos.', round(l.max_unit))
         WHEN o.currency = 'COP' AND l.max_unit > 0 AND l.max_unit < 50000 THEN format('Precio por par de %s COP: fuera de rango para pesos colombianos.', round(l.max_unit)) END), '')
  FROM f360.commerce_woo_orders o
  LEFT JOIN LATERAL (SELECT max(CASE WHEN quantity > 0 THEN subtotal / quantity END) AS max_unit FROM f360.commerce_woo_order_lines x
                     WHERE x.target_id = o.target_id AND x.woo_order_id = o.woo_order_id) l ON true
  WHERE o.target_id = p_target AND o.woo_order_id = p_order;
$$;
REVOKE ALL ON FUNCTION f360.currency_suspicion(uuid, bigint) FROM PUBLIC, anon, authenticated;

-- Commerce Facts + the active correction (reporting fields only; the source fields are unchanged).
CREATE VIEW f360.commerce_orders_reporting AS
  SELECT co.*, coalesce(cc.corrected_market, co.market) AS market_reporting, coalesce(cc.corrected_currency, co.currency_original) AS currency_reporting,
         (cc.id IS NOT NULL) AS currency_corrected
  FROM f360.commerce_orders co
  LEFT JOIN f360.commerce_currency_scope cc ON cc.target_id = co.target_id AND cc.woo_order_id = co.woo_order_id AND cc.active;

REVOKE ALL ON f360.commerce_currency_corrections, f360.commerce_currency_scope, f360.commerce_orders_reporting FROM PUBLIC, anon, authenticated;

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


CREATE OR REPLACE FUNCTION f360.sales_rec_row(c f360.sales_rec_cases_state) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('target_id', c.target_id, 'target_key', c.target_key, 'woo_order_id', c.woo_order_id, 'created_at', c.created_at,
    'market', c.market, 'currency', c.currency, 'order_total', c.order_total, 'refund_total', c.refund_total, 'woo_status', c.woo_status,
    'payment_method', c.payment_method, 'paid_at', c.paid_at, 'ever_paid', c.ever_paid, 'units', c.units, 'status_class', c.status_class,
    'financial_state', c.financial_state, 'flags', c.flags, 'rec_state', c.rec_state, 'conflict', c.conflict,
    'evidence', CASE WHEN c.evidence_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.evidence_id, 'gateway_result', c.gateway_result,
                  'transaction_ref', c.transaction_ref, 'queried_at', c.evidence_at) END,
    'decision', CASE WHEN c.decision_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.decision_id, 'decision', c.decision,
                  'comment', c.decision_comment, 'by', c.decided_by_name, 'at', c.decided_at, 'duplicate_of', c.duplicate_of) END,
    'excluded', coalesce(c.excluded, false),
    'currency_correction', (SELECT jsonb_build_object('id', cc.id, 'woo_currency', cc.original_currency, 'woo_market', cc.original_market,
        'currency', cc.corrected_currency, 'market', cc.corrected_market, 'reason', cc.reason, 'by', cc.decided_by_name, 'at', cc.decided_at)
      FROM f360.commerce_currency_scope cc WHERE cc.target_id = c.target_id AND cc.woo_order_id = c.woo_order_id AND cc.active));
$$;


-- Carolina & Mario only. Evidence is captured here from Commerce Facts (never from the client).
CREATE FUNCTION public.f360_rec_correct_currency(p_target uuid, p_order bigint, p_currency text, p_reason text, p_revert boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); o f360.commerce_woo_orders; cur f360.commerce_currency_scope; rsn text := btrim(coalesce(p_reason, ''));
  mkt text := CASE p_currency WHEN 'MXN' THEN 'MX' WHEN 'COP' THEN 'CO' WHEN 'USD' THEN 'ROW' END; new_id bigint; ev jsonb;
BEGIN
  IF length(rsn) < 10 THEN RAISE EXCEPTION 'Escribe el motivo y la evidencia (mínimo 10 letras).' USING ERRCODE = 'check_violation'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('currency:' || p_target || ':' || p_order, 0));
  SELECT * INTO o FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_order;
  IF o.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  SELECT * INTO cur FROM f360.commerce_currency_scope WHERE target_id = p_target AND woo_order_id = p_order;
  IF coalesce(p_revert, false) THEN
    IF NOT coalesce(cur.active, false) THEN RAISE EXCEPTION 'Ese pedido no tiene una corrección de moneda activa.' USING ERRCODE = 'check_violation'; END IF;
  ELSE
    IF mkt IS NULL THEN RAISE EXCEPTION 'Moneda no válida (MXN, COP o USD).' USING ERRCODE = 'check_violation'; END IF;
    IF p_currency = o.currency AND NOT coalesce(cur.active, false) THEN RAISE EXCEPTION 'El pedido ya está en %: no hay nada que corregir.', p_currency USING ERRCODE = 'check_violation'; END IF;
    IF coalesce(cur.active, false) AND cur.corrected_currency = p_currency THEN RAISE EXCEPTION 'Ya está corregido a %.', p_currency USING ERRCODE = 'check_violation'; END IF;
  END IF;
  ev := jsonb_build_object('woo_currency', o.currency, 'woo_market', o.market, 'market_source', o.market_source, 'billing_country', o.billing_country,
          'payment_method', o.payment_method, 'order_total', o.order_total, 'woo_status', o.woo_status, 'ever_paid', o.ever_paid,
          'economics_hash', o.economics_hash, 'suspicion', f360.currency_suspicion(p_target, p_order),
          'max_unit_price', (SELECT max(CASE WHEN quantity > 0 THEN subtotal / quantity END) FROM f360.commerce_woo_order_lines x WHERE x.target_id = p_target AND x.woo_order_id = p_order));
  INSERT INTO f360.commerce_currency_corrections (target_id, woo_order_id, action, original_currency, original_market, corrected_currency, corrected_market,
                                                  reason, evidence, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, CASE WHEN p_revert THEN 'revert' ELSE 'correct' END, o.currency, o.market,
          CASE WHEN p_revert THEN NULL ELSE p_currency END, CASE WHEN p_revert THEN NULL ELSE mkt END, rsn, ev, cur.id, uid, f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'active', NOT coalesce(p_revert, false), 'woo_currency', o.currency, 'woo_market', o.market,
                            'currency', CASE WHEN p_revert THEN o.currency ELSE p_currency END, 'market', CASE WHEN p_revert THEN o.market ELSE mkt END);
END $$;
REVOKE ALL ON FUNCTION public.f360_rec_correct_currency(uuid, bigint, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_rec_correct_currency(uuid, bigint, text, text, boolean) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION f360.growth_market_block(p_market text, p_from timestamptz, p_to timestamptz, p_pfrom timestamptz, p_pto timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE cur text := CASE p_market WHEN 'CO' THEN 'COP' WHEN 'ROW' THEN 'USD' ELSE 'MXN' END;
  rev numeric; rev_p numeric; paid int; paid_p int; created int; created_p int; never int; n_units int;
  sp numeric; sp_p numeric; imp bigint; clk bigint; sp_cur_ok boolean; attributed int;
  ga4 text := (SELECT config_status FROM f360.measurement_sources WHERE key = 'ga4');
  k jsonb := '{}'; spend_status text; ga4_status text;
BEGIN
  SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0), count(*) FILTER (WHERE status_class = 'countable'),
         count(*), count(*) FILTER (WHERE payment_state = 'never_paid'), coalesce(sum(units) FILTER (WHERE status_class = 'countable'), 0)
    INTO rev, paid, created, never, n_units
    FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_from AND occurred_at < p_to;
  SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0), count(*) FILTER (WHERE status_class = 'countable'), count(*)
    INTO rev_p, paid_p, created_p
    FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_pfrom AND occurred_at < p_pto;
  SELECT sum(spend), sum(impressions), sum(clicks), bool_and(currency = cur) INTO sp, imp, clk, sp_cur_ok
    FROM f360.marketing_spend_daily WHERE market = p_market AND date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND date < (p_to AT TIME ZONE 'America/Mexico_City')::date;
  SELECT sum(spend) INTO sp_p FROM f360.marketing_spend_daily
    WHERE market = p_market AND date >= (p_pfrom AT TIME ZONE 'America/Mexico_City')::date AND date < (p_pto AT TIME ZONE 'America/Mexico_City')::date;
  spend_status := CASE WHEN sp IS NULL THEN 'NOT_CONFIGURED' WHEN NOT sp_cur_ok THEN 'DATA_INCOMPLETE' ELSE 'OK' END;
  ga4_status := CASE WHEN ga4 IN ('HEALTHY', 'CONFIGURED') THEN 'DATA_INCOMPLETE' ELSE 'NOT_CONFIGURED' END;   -- ingestion arrives in S-G2
  SELECT count(*) INTO attributed FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
    WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.source_type IS NOT NULL;

  k := jsonb_build_object(
    'revenue', jsonb_build_object('value', rev, 'prev', rev_p, 'currency', cur, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados (venta neta de producto)'),
    'paid_orders', jsonb_build_object('value', paid, 'prev', paid_p, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados'),
    'aov', jsonb_build_object('value', CASE WHEN paid > 0 THEN round(rev / paid, 2) END, 'prev', CASE WHEN paid_p > 0 THEN round(rev_p / paid_p, 2) END,
                              'currency', cur, 'status', CASE WHEN paid > 0 THEN 'OK' ELSE 'DATA_INCOMPLETE' END, 'source', 'ingresos ÷ pedidos pagados',
                              'note', CASE WHEN paid = 0 THEN 'Sin pedidos pagados en el periodo' END),
    'units', jsonb_build_object('value', n_units, 'status', 'OK', 'source', 'Commerce Facts · pares pagados'),
    'cvr_session', jsonb_build_object('value', NULL, 'status', ga4_status, 'source', 'pedidos pagados ÷ sesiones (GA4)', 'note', 'Requiere sesiones de GA4'),
    'cvr_click', jsonb_build_object('value', CASE WHEN clk > 0 THEN round(paid::numeric / clk * 100, 2) END,
                              'status', CASE WHEN clk IS NULL THEN 'NOT_CONFIGURED' WHEN clk = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'pedidos pagados ÷ clics de anuncios', 'note', 'Conversión por clic, no por sesión'),
    'spend', jsonb_build_object('value', sp, 'prev', sp_p, 'currency', cur, 'status', spend_status, 'source', 'Gasto publicitario (CSV / API)',
                              'note', CASE spend_status WHEN 'NOT_CONFIGURED' THEN 'Sin gasto cargado para este mercado y periodo' WHEN 'DATA_INCOMPLETE' THEN 'Gasto en otra moneda: falta tipo de cambio aprobado' END),
    'cpc', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND clk > 0 THEN round(sp / clk, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(clk, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'gasto ÷ clics'),
    'ctr', jsonb_build_object('value', CASE WHEN imp > 0 THEN round(clk::numeric / imp * 100, 2) END,
                              'status', CASE WHEN imp IS NULL THEN 'NOT_CONFIGURED' WHEN imp = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'clics ÷ impresiones'),
    'cpm', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND imp > 0 THEN round(sp / imp * 1000, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(imp, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END, 'source', 'gasto ÷ impresiones × 1000'),
    'cpa', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND paid > 0 THEN round(sp / paid, 2) END, 'currency', cur,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN paid = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'gasto ÷ pedidos pagados (todos los canales)'),
    'roas', jsonb_build_object('value', NULL, 'status', CASE WHEN spend_status <> 'OK' THEN spend_status ELSE 'DATA_INCOMPLETE' END,
                              'source', 'ingresos atribuidos a anuncios ÷ gasto',
                              'note', 'Requiere unir campañas del gasto con la atribución de pedidos (S-G2)'),
    'mer', jsonb_build_object('value', CASE WHEN spend_status = 'OK' AND sp > 0 THEN round(rev / sp, 2) END,
                              'status', CASE WHEN spend_status <> 'OK' THEN spend_status WHEN coalesce(sp, 0) = 0 THEN 'DATA_INCOMPLETE' ELSE 'OK' END,
                              'source', 'ingresos pagados totales ÷ gasto total'));

  RETURN jsonb_build_object('market', p_market, 'currency', cur, 'kpis', k,
    'attribution_coverage', jsonb_build_object('attributed', attributed, 'paid', paid),
    'funnel', jsonb_build_array(
      jsonb_build_object('stage', 'Sesiones', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Vieron un producto', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Agregaron al carrito', 'value', NULL, 'status', ga4_status, 'source', 'GA4'),
      jsonb_build_object('stage', 'Hicieron pedido (checkout enviado)', 'value', created, 'status', 'OK', 'source', 'WooCommerce · pedidos creados'),
      jsonb_build_object('stage', 'Pagaron', 'value', paid, 'status', 'OK', 'source', 'Commerce Facts · pedidos pagados')),
    'checkout', jsonb_build_object('created', created, 'paid', paid, 'never_paid', never,
      'by_payment', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'created' DESC), '[]') FROM (
        SELECT jsonb_build_object('method', coalesce(nullif(payment_method, ''), 'sin método'), 'created', count(*),
                 'paid', count(*) FILTER (WHERE status_class = 'countable'), 'never_paid', count(*) FILTER (WHERE payment_state = 'never_paid')) x
        FROM f360.commerce_orders_reporting WHERE source_system = 'woo' AND market_reporting = p_market AND occurred_at >= p_from AND occurred_at < p_to
        GROUP BY coalesce(nullif(payment_method, ''), 'sin método')) q)),
    'by_channel', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('channel', f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host),
                 'orders_created', count(*), 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0)) x
        FROM f360.commerce_orders_reporting o LEFT JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host)) q),
    'by_campaign', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('campaign', a.utm_campaign, 'source', a.utm_source, 'orders_created', count(*),
                 'paid_orders', count(*) FILTER (WHERE o.status_class = 'countable'),
                 'revenue', coalesce(sum(o.net_product) FILTER (WHERE o.status_class = 'countable'), 0),
                 'spend', (SELECT sum(d.spend) FROM f360.marketing_spend_daily d WHERE d.market = p_market AND d.campaign_id = a.utm_campaign
                            AND d.date >= (p_from AT TIME ZONE 'America/Mexico_City')::date AND d.date < (p_to AT TIME ZONE 'America/Mexico_City')::date)) x
        FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_attribution a ON a.target_id = o.target_id AND a.woo_order_id = o.woo_order_id
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.occurred_at >= p_from AND o.occurred_at < p_to AND a.utm_campaign IS NOT NULL
        GROUP BY a.utm_campaign, a.utm_source) q),
    'by_product', (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'revenue')::numeric DESC), '[]') FROM (
        SELECT jsonb_build_object('product', nm.name, 'paid_units', sum(l.quantity), 'revenue', sum(l.total)) x
        FROM f360.commerce_orders_reporting o JOIN f360.commerce_woo_order_lines l ON l.target_id = o.target_id AND l.woo_order_id = o.woo_order_id
        CROSS JOIN LATERAL (SELECT coalesce(
            (SELECT p.name FROM f360.woo_product_links wl JOIN f360.products p ON p.id = wl.product_id WHERE wl.woo_product_id = l.woo_product_id LIMIT 1),
            (SELECT p.name FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.sku = l.sku LIMIT 1),
            (SELECT m.woo_product_name FROM f360.legacy_woo_map m WHERE m.woo_product_id = l.woo_product_id AND m.woo_product_name IS NOT NULL LIMIT 1),
            'SKU ' || coalesce(l.sku, '?')) AS name) nm
        WHERE o.source_system = 'woo' AND o.market_reporting = p_market AND o.status_class = 'countable' AND o.occurred_at >= p_from AND o.occurred_at < p_to
        GROUP BY nm.name LIMIT 15) q));
END $$;

CREATE OR REPLACE FUNCTION f360.growth_adjustments(p_market text, p_from timestamptz, p_to timestamptz, p_detail boolean) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  WITH o AS (
    SELECT co.target_id, co.woo_order_id, co.status_class, co.net_product, co.units, co.payment_state, co.currency_corrected, co.currency_original, co.market AS market_original, co.order_total
    FROM f360.commerce_orders_reporting co WHERE co.source_system = 'woo' AND co.market_reporting = p_market AND co.occurred_at >= p_from AND co.occurred_at < p_to
  ), orig AS (
    SELECT coalesce(sum(net_product) FILTER (WHERE status_class = 'countable'), 0) AS revenue,
           count(*) FILTER (WHERE status_class = 'countable') AS orders, coalesce(sum(units) FILTER (WHERE status_class = 'countable'), 0) AS units FROM o
  ), x AS (
    SELECT o.*, s.reason, s.decided_by_name, s.decided_at, (o.status_class = 'countable') AS effective
    FROM o JOIN f360.sales_rec_analytics_scope s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id WHERE s.excluded
  ), eff AS (
    SELECT coalesce(sum(net_product) FILTER (WHERE effective), 0) AS revenue, count(*) FILTER (WHERE effective) AS orders,
           coalesce(sum(units) FILTER (WHERE effective), 0) AS units, count(*) FILTER (WHERE NOT effective) AS no_effect FROM x
  ), cls AS (   -- classified as test / duplicate but NOT excluded: they still count (transparency, never silent)
    SELECT count(*) AS n FROM o JOIN LATERAL (SELECT d.decision FROM f360.sales_rec_decisions d WHERE d.target_id = o.target_id AND d.woo_order_id = o.woo_order_id
             ORDER BY d.id DESC LIMIT 1) d ON true
    WHERE d.decision IN ('prueba', 'duplicado') AND o.status_class = 'countable'
      AND NOT EXISTS (SELECT 1 FROM f360.sales_rec_analytics_scope s WHERE s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id AND s.excluded)
  )
  SELECT jsonb_build_object(
    'original', jsonb_build_object('revenue', orig.revenue, 'paid_orders', orig.orders, 'units', orig.units,
                                   'aov', CASE WHEN orig.orders > 0 THEN round(orig.revenue / orig.orders, 2) END),
    'excluded', jsonb_build_object('revenue', eff.revenue, 'paid_orders', eff.orders, 'units', eff.units, 'without_effect', eff.no_effect),
    'adjusted', jsonb_build_object('revenue', orig.revenue - eff.revenue, 'paid_orders', orig.orders - eff.orders, 'units', orig.units - eff.units,
                                   'aov', CASE WHEN orig.orders - eff.orders > 0 THEN round((orig.revenue - eff.revenue) / (orig.orders - eff.orders), 2) END),
    'classified_not_excluded', cls.n,
    'detail', CASE WHEN p_detail THEN (SELECT coalesce(jsonb_agg(jsonb_build_object('target_id', x.target_id, 'woo_order_id', x.woo_order_id,
                 'status_class', x.status_class, 'payment_state', x.payment_state, 'effective', x.effective,
                 'revenue_effect', CASE WHEN x.effective THEN x.net_product ELSE 0 END, 'units_effect', CASE WHEN x.effective THEN x.units ELSE 0 END,
                 'why_no_effect', CASE WHEN x.effective THEN NULL WHEN x.payment_state = 'never_paid' THEN 'Nunca se pagó: no contaba'
                                       ELSE 'Cancelado o reembolsado después del pago: ya no contaba' END,
                 'reason', x.reason, 'by', x.decided_by_name, 'at', x.decided_at) ORDER BY x.woo_order_id), '[]') FROM x) END,
    'currency_corrections', (SELECT jsonb_build_object('count', count(*), 'detail', CASE WHEN p_detail THEN coalesce(jsonb_agg(jsonb_build_object(
        'woo_order_id', o.woo_order_id, 'woo_currency', o.currency_original, 'woo_market', o.market_original, 'amount', o.order_total,
        'status_class', o.status_class)), '[]') END) FROM o WHERE o.currency_corrected),
    'source', 'Conciliación de Ventas · exclusiones autorizadas (registro inmutable)')
  FROM orig, eff, cls;
$$;
