-- Fuxia 360 · Conciliación de Ventas (Growth 360). Mario 2026-10-10: STAGING only; design SALES_RECONCILIATION_DESIGN.md.
-- ADDITIVE. Reads Commerce Facts (f360.commerce_woo_orders & co.) and NEVER changes them, WooCommerce or any gateway.
-- Five states kept apart (Mario §5):
--   1. Woo status ............ commerce_woo_orders.woo_status (source, untouched)
--   2. Financial evidence .... derived from Commerce Facts + the latest read-only Woo evidence snapshot (sales_rec_evidence)
--   3. Human classification .. sales_rec_decisions (append-only; a newer decision supersedes, history stays)
--   4. Reconciliation state .. derived (pending / reviewed / conflict / changed after review / under investigation)
--   5. Analytics scope ....... sales_rec_exclusions (append-only, separate action with reason; NOT applied to any metric yet)
-- A human "Venta confirmada" never turns an order into a charged sale: financial evidence is computed only from Woo/gateway data.
-- Duplicates are only CANDIDATES (rule + the other order), never confirmed automatically.
-- Access: ONLY f360.customer_pii_viewers (Carolina, Mario) — f360.require_pii_viewer(). Evidence rows are written only by the
-- f360-woo-sync function (service role) after it verified the caller; they hold no card data, no raw notes and no customer data.
-- Depends on 20261021000100 (f360.classify_channel_v1).
-- Rollback: supabase/rollbacks/20261022000100_f360_sales_reconciliation.down.sql

-- ══ 1 · Evidence snapshots (minimal, structured) ══════════════════════════════
CREATE TABLE f360.sales_rec_evidence (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  source          text NOT NULL CHECK (source IN ('woo_rest_order')),
  source_ref      text NOT NULL,                                  -- e.g. woo_staging4:order/5351
  woo_status      text NOT NULL,
  date_paid       timestamptz,
  transaction_ref text CHECK (transaction_ref IS NULL OR length(transaction_ref) <= 100),
  payment_method  text,
  order_total     numeric(14,2),
  currency        text,
  refund_total    numeric(14,2) NOT NULL DEFAULT 0,
  gateway_result  text NOT NULL CHECK (gateway_result IN ('approved', 'rejected', 'pending', 'refunded', 'transaction_only', 'no_evidence', 'order_missing')),
  signals         text[] NOT NULL DEFAULT '{}',                   -- derived codes only (never note text)
  result          text NOT NULL,                                  -- one-line human summary, built server-side
  evidence_hash   text NOT NULL,                                  -- sha256 of the canonical snapshot
  queried_by      uuid NOT NULL,
  queried_by_name text NOT NULL,
  queried_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sales_rec_evidence_order_idx ON f360.sales_rec_evidence (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_evidence ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_evidence_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_evidence
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 2 · Human classification (append-only) ════════════════════════════════════
CREATE TABLE f360.sales_rec_decisions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  decision        text NOT NULL CHECK (decision IN ('venta_confirmada', 'no_se_concreto', 'duplicado', 'prueba', 'reembolso', 'requiere_investigacion')),
  duplicate_of    bigint CHECK (duplicate_of IS NULL OR decision = 'duplicado'),
  comment         text CHECK (comment IS NULL OR length(comment) <= 1000),
  evidence_id     bigint REFERENCES f360.sales_rec_evidence(id),
  woo_status_seen text NOT NULL,                                  -- what the source said when the person decided
  facts_hash_seen text,                                           -- commerce_woo_orders.economics_hash at decision time
  financial_seen  text NOT NULL,                                  -- financial evidence state at decision time
  supersedes      bigint UNIQUE REFERENCES f360.sales_rec_decisions(id),
  decided_by      uuid NOT NULL,
  decided_by_name text NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (decision <> 'duplicado' OR duplicate_of IS NOT NULL)
);
CREATE INDEX sales_rec_decisions_order_idx ON f360.sales_rec_decisions (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_decisions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_decisions_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_decisions
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- ══ 3 · Analytics scope (separate authorized action, append-only) ════════════
CREATE TABLE f360.sales_rec_exclusions (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id       uuid NOT NULL REFERENCES f360.sales_targets(id),
  woo_order_id    bigint NOT NULL,
  action          text NOT NULL CHECK (action IN ('exclude', 'include')),
  reason          text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 1000),
  supersedes      bigint UNIQUE REFERENCES f360.sales_rec_exclusions(id),
  decided_by      uuid NOT NULL,
  decided_by_name text NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sales_rec_exclusions_order_idx ON f360.sales_rec_exclusions (target_id, woo_order_id, id DESC);
ALTER TABLE f360.sales_rec_exclusions ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER sales_rec_exclusions_append_only BEFORE UPDATE OR DELETE ON f360.sales_rec_exclusions
  FOR EACH ROW EXECUTE FUNCTION f360.reject_audit_change();

-- Current analytics scope per order (only orders with an exclusion history appear). Not consumed by any metric yet.
CREATE VIEW f360.sales_rec_analytics_scope AS
  SELECT DISTINCT ON (target_id, woo_order_id) target_id, woo_order_id, action = 'exclude' AS excluded, reason, decided_by_name, decided_at
  FROM f360.sales_rec_exclusions ORDER BY target_id, woo_order_id, id DESC;

-- ══ 4 · Cases: facts + flags + states (derived, nothing stored) ═══════════════
CREATE VIEW f360.sales_rec_cases AS
WITH sig AS (
  SELECT target_id, woo_order_id,
         string_agg(coalesce(nullif(woo_variation_id, 0), woo_product_id)::text || 'x' || quantity, ',' ORDER BY coalesce(nullif(woo_variation_id, 0), woo_product_id), quantity) AS lines_sig
  FROM f360.commerce_woo_order_lines GROUP BY target_id, woo_order_id
), base AS (
  SELECT o.target_id, t.key AS target_key, o.woo_order_id, o.woo_created_at AS created_at, o.market, o.currency, o.order_total,
         o.woo_status, nullif(o.payment_method, '') AS payment_method, o.ever_paid, coalesce(o.first_paid_at, o.paid_at) AS paid_at,
         nullif(o.woo_customer_id, 0) AS woo_customer_id, o.units, o.economics_hash, o.woo_modified_at,
         coalesce(rt.refund_total, 0) AS refund_total, f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class, s.lines_sig
  FROM f360.commerce_woo_orders o
  JOIN f360.sales_targets t ON t.id = o.target_id
  LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
  LEFT JOIN sig s ON s.target_id = o.target_id AND s.woo_order_id = o.woo_order_id
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
             'why', 'Mismos productos y total: la clienta lo volvió a intentar y pagó en el pedido #' || f.retry_paid_order || ' (no es venta perdida).')
      WHERE f.retry_paid_order IS NOT NULL
    UNION ALL
    SELECT jsonb_build_object('code', 'PAGO_Y_CANCELADO', 'kind', 'financiera',
             'why', 'Se registró pago (' || coalesce(to_char(f.paid_at AT TIME ZONE 'America/Mexico_City', 'DD/MM/YYYY HH24:MI'), 'sin fecha') ||
                    ') y hoy está "' || f.woo_status || '", sin reembolso registrado.')
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

CREATE VIEW f360.sales_rec_cases_state AS
  SELECT c.*,
    CASE
      WHEN c.decision IS NULL AND c.has_financial THEN 'pendiente_discrepancia'
      WHEN c.decision IS NULL AND jsonb_array_length(c.flags) > 0 THEN 'pendiente'
      WHEN c.decision IS NULL THEN 'sin_novedad'
      WHEN c.woo_status_seen IS DISTINCT FROM c.woo_status OR c.facts_hash_seen IS DISTINCT FROM c.economics_hash THEN 'cambio_despues'
      WHEN c.decision = 'requiere_investigacion' THEN 'en_investigacion'
      WHEN c.conflict IS NOT NULL THEN 'conflicto'
      ELSE 'revisado'
    END AS rec_state
  FROM f360.sales_rec_cases c;

REVOKE ALL ON f360.sales_rec_evidence, f360.sales_rec_decisions, f360.sales_rec_exclusions, f360.sales_rec_analytics_scope,
  f360.sales_rec_cases, f360.sales_rec_cases_state FROM PUBLIC, anon, authenticated;

-- ══ 5 · RPCs (Carolina & Mario only) ═════════════════════════════════════════
CREATE FUNCTION f360.sales_rec_actor_name(p_uid uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT coalesce((SELECT display_name FROM f360.user_roles WHERE auth_user_id = p_uid), 'Persona autorizada');
$$;
REVOKE ALL ON FUNCTION f360.sales_rec_actor_name(uuid) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.sales_rec_row(c f360.sales_rec_cases_state) RETURNS jsonb
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object('target_id', c.target_id, 'target_key', c.target_key, 'woo_order_id', c.woo_order_id, 'created_at', c.created_at,
    'market', c.market, 'currency', c.currency, 'order_total', c.order_total, 'refund_total', c.refund_total, 'woo_status', c.woo_status,
    'payment_method', c.payment_method, 'paid_at', c.paid_at, 'ever_paid', c.ever_paid, 'units', c.units, 'status_class', c.status_class,
    'financial_state', c.financial_state, 'flags', c.flags, 'rec_state', c.rec_state, 'conflict', c.conflict,
    'evidence', CASE WHEN c.evidence_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.evidence_id, 'gateway_result', c.gateway_result,
                  'transaction_ref', c.transaction_ref, 'queried_at', c.evidence_at) END,
    'decision', CASE WHEN c.decision_id IS NULL THEN NULL ELSE jsonb_build_object('id', c.decision_id, 'decision', c.decision,
                  'comment', c.decision_comment, 'by', c.decided_by_name, 'at', c.decided_at, 'duplicate_of', c.duplicate_of) END,
    'excluded', coalesce(c.excluded, false));
$$;
REVOKE ALL ON FUNCTION f360.sales_rec_row(f360.sales_rec_cases_state) FROM PUBLIC, anon, authenticated;

-- Used by f360-woo-sync with the caller's own token BEFORE it reads WooCommerce.
CREATE FUNCTION public.f360_rec_can_view() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN PERFORM f360.require_pii_viewer(); RETURN true; END $$;

CREATE FUNCTION public.f360_rec_list(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_market text DEFAULT NULL, p_woo_status text DEFAULT NULL,
  p_method text DEFAULT NULL, p_flag text DEFAULT NULL, p_state text DEFAULT NULL, p_decision text DEFAULT NULL,
  p_limit int DEFAULT 100, p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); r jsonb; n int;
  t_from timestamptz := CASE WHEN p_from IS NULL THEN NULL ELSE p_from::timestamp AT TIME ZONE 'America/Mexico_City' END;
  t_to   timestamptz := CASE WHEN p_to   IS NULL THEN NULL ELSE (p_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City' END;
BEGIN
  IF p_from IS NOT NULL AND p_to IS NOT NULL AND p_to < p_from THEN RAISE EXCEPTION 'La fecha final es anterior a la inicial.'; END IF;
  WITH m AS (
    SELECT c FROM f360.sales_rec_cases_state c
    WHERE (t_from IS NULL OR c.created_at >= t_from) AND (t_to IS NULL OR c.created_at < t_to)
      AND (p_market IS NULL OR c.market = p_market) AND (p_woo_status IS NULL OR c.woo_status = p_woo_status)
      AND (p_method IS NULL OR coalesce(c.payment_method, 'sin_metodo') = p_method)
      AND (p_flag IS NULL OR (p_flag = 'financiera' AND c.has_financial) OR c.flags @> jsonb_build_array(jsonb_build_object('code', p_flag)))
      AND (p_state IS NULL OR c.rec_state = p_state OR (p_state = 'pendientes' AND c.rec_state IN ('pendiente', 'pendiente_discrepancia', 'cambio_despues')))
      AND (p_decision IS NULL OR c.decision = p_decision OR (p_decision = 'sin_decision' AND c.decision IS NULL)))
  SELECT count(*), coalesce((SELECT jsonb_agg(f360.sales_rec_row(x.c) ORDER BY (x.c).created_at DESC, (x.c).woo_order_id DESC) FROM (
           SELECT c FROM m ORDER BY (c).created_at DESC, (c).woo_order_id DESC
           LIMIT least(greatest(coalesce(p_limit, 100), 1), 200) OFFSET greatest(coalesce(p_offset, 0), 0)) x), '[]')
    INTO n, r FROM m;
  RETURN jsonb_build_object('total', n, 'rows', r);
END $$;

CREATE FUNCTION public.f360_rec_summary(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_market text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); r jsonb;
  t_from timestamptz := CASE WHEN p_from IS NULL THEN NULL ELSE p_from::timestamp AT TIME ZONE 'America/Mexico_City' END;
  t_to   timestamptz := CASE WHEN p_to   IS NULL THEN NULL ELSE (p_to + 1)::timestamp AT TIME ZONE 'America/Mexico_City' END;
BEGIN
  WITH m AS (SELECT * FROM f360.sales_rec_cases_state c WHERE (t_from IS NULL OR c.created_at >= t_from) AND (t_to IS NULL OR c.created_at < t_to)
                AND (p_market IS NULL OR c.market = p_market))
  SELECT jsonb_build_object(
    'by_market', coalesce((SELECT jsonb_agg(jsonb_build_object('market', market, 'currency', currency, 'orders', n, 'pending', pend,
                   'financial_open', fin_open, 'not_completed', nc, 'duplicate_candidates', dupc, 'reviewed', rev, 'conflicts', conf,
                   'investigating', inv, 'changed', chg, 'no_issue', ok, 'excluded', exc) ORDER BY market) FROM (
        SELECT market, currency, count(*) n,
          count(*) FILTER (WHERE rec_state IN ('pendiente', 'pendiente_discrepancia', 'cambio_despues')) pend,
          count(*) FILTER (WHERE has_financial AND rec_state IN ('pendiente_discrepancia', 'cambio_despues', 'en_investigacion', 'conflicto')) fin_open,
          count(*) FILTER (WHERE flags @> '[{"code":"NO_CONCRETADO"}]') nc,
          count(*) FILTER (WHERE flags @> '[{"code":"POSIBLE_DUPLICADO"}]' AND decision IS NULL) dupc,
          count(*) FILTER (WHERE rec_state = 'revisado') rev, count(*) FILTER (WHERE rec_state = 'conflicto') conf,
          count(*) FILTER (WHERE rec_state = 'en_investigacion') inv, count(*) FILTER (WHERE rec_state = 'cambio_despues') chg,
          count(*) FILTER (WHERE rec_state = 'sin_novedad') ok, count(*) FILTER (WHERE excluded) exc
        FROM m GROUP BY market, currency) q), '[]'),
    'methods', coalesce((SELECT jsonb_agg(DISTINCT coalesce(payment_method, 'sin_metodo')) FROM m), '[]'),
    'statuses', coalesce((SELECT jsonb_agg(DISTINCT woo_status) FROM m), '[]'),
    'generated_at', now()) INTO r;
  RETURN r;
END $$;

CREATE FUNCTION public.f360_rec_case(p_target uuid, p_order bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); c f360.sales_rec_cases_state;
BEGIN
  SELECT * INTO c FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  IF c.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN f360.sales_rec_row(c) || jsonb_build_object(
    'facts', (SELECT jsonb_build_object('created_via', o.created_via, 'business_origin', o.business_origin, 'items_subtotal', o.items_subtotal,
               'discount_total', o.discount_total, 'shipping_total', o.shipping_total, 'total_tax', o.total_tax, 'woo_modified_at', o.woo_modified_at,
               'completed_at', o.completed_at, 'billing_country', o.billing_country, 'last_captured_via', o.last_captured_via,
               'last_changed_at', o.last_changed_at, 'source', 'Commerce Facts · ' || c.target_key || ' · pedido ' || o.woo_order_id)
              FROM f360.commerce_woo_orders o WHERE o.target_id = p_target AND o.woo_order_id = p_order),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object('product', nm.name, 'sku', l.sku, 'quantity', l.quantity, 'total', l.total) ORDER BY l.woo_line_id), '[]')
              FROM f360.commerce_woo_order_lines l
              CROSS JOIN LATERAL (SELECT coalesce(
                (SELECT p.name FROM f360.woo_product_links wl JOIN f360.products p ON p.id = wl.product_id WHERE wl.woo_product_id = l.woo_product_id LIMIT 1),
                (SELECT p.name FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id WHERE v.sku = l.sku LIMIT 1),
                (SELECT m.woo_product_name FROM f360.legacy_woo_map m WHERE m.woo_product_id = l.woo_product_id AND m.woo_product_name IS NOT NULL LIMIT 1),
                'SKU ' || coalesce(l.sku, '?')) AS name) nm
              WHERE l.target_id = p_target AND l.woo_order_id = p_order),
    'origin', (SELECT jsonb_build_object('channel', f360.classify_channel_v1(a.source_type, a.utm_source, a.utm_medium, a.referrer_host),
               'utm_source', a.utm_source, 'utm_campaign', a.utm_campaign, 'device', a.device_type)
               FROM f360.commerce_woo_attribution a WHERE a.target_id = p_target AND a.woo_order_id = p_order),
    'duplicates', (SELECT coalesce(jsonb_agg(f360.sales_rec_row(d) ORDER BY d.woo_order_id), '[]') FROM f360.sales_rec_cases_state d
                   WHERE d.target_id = p_target AND d.woo_order_id = ANY (coalesce(c.duplicate_candidates, '{}'))),
    'evidence_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'source', e.source, 'source_ref', e.source_ref, 'woo_status', e.woo_status,
               'date_paid', e.date_paid, 'transaction_ref', e.transaction_ref, 'payment_method', e.payment_method, 'order_total', e.order_total,
               'currency', e.currency, 'refund_total', e.refund_total, 'gateway_result', e.gateway_result, 'signals', e.signals, 'result', e.result,
               'hash', e.evidence_hash, 'by', e.queried_by_name, 'at', e.queried_at) ORDER BY e.id DESC), '[]')
               FROM f360.sales_rec_evidence e WHERE e.target_id = p_target AND e.woo_order_id = p_order),
    'decision_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'decision', d.decision, 'comment', d.comment, 'duplicate_of', d.duplicate_of,
               'evidence_id', d.evidence_id, 'woo_status_seen', d.woo_status_seen, 'financial_seen', d.financial_seen, 'supersedes', d.supersedes,
               'by', d.decided_by_name, 'at', d.decided_at) ORDER BY d.id DESC), '[]')
               FROM f360.sales_rec_decisions d WHERE d.target_id = p_target AND d.woo_order_id = p_order),
    'exclusion_history', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'action', x.action, 'reason', x.reason, 'by', x.decided_by_name,
               'at', x.decided_at) ORDER BY x.id DESC), '[]')
               FROM f360.sales_rec_exclusions x WHERE x.target_id = p_target AND x.woo_order_id = p_order));
END $$;

CREATE FUNCTION public.f360_rec_decide(p_target uuid, p_order bigint, p_decision text, p_comment text DEFAULT NULL,
  p_evidence_id bigint DEFAULT NULL, p_duplicate_of bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); c f360.sales_rec_cases_state; prev bigint; cmt text := nullif(btrim(coalesce(p_comment, '')), '');
  new_id bigint; after f360.sales_rec_cases_state;
BEGIN
  IF p_decision NOT IN ('venta_confirmada', 'no_se_concreto', 'duplicado', 'prueba', 'reembolso', 'requiere_investigacion') THEN
    RAISE EXCEPTION 'Decisión no válida.' USING ERRCODE = 'check_violation';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('sales_rec:' || p_target || ':' || p_order, 0));
  SELECT * INTO c FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  IF c.target_id IS NULL THEN RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found'; END IF;
  prev := c.decision_id;
  IF p_decision IN ('duplicado', 'prueba', 'requiere_investigacion') AND (cmt IS NULL OR length(cmt) < 5) THEN
    RAISE EXCEPTION 'Escribe un comentario (por qué es %).', replace(p_decision, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  IF prev IS NOT NULL AND (cmt IS NULL OR length(cmt) < 5) THEN
    RAISE EXCEPTION 'Para corregir una decisión anterior escribe el motivo.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision = 'duplicado' THEN
    IF p_duplicate_of IS NULL OR p_duplicate_of = p_order
       OR NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_duplicate_of) THEN
      RAISE EXCEPTION 'Indica de qué pedido es duplicado (otro pedido de la misma tienda).' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF p_duplicate_of IS NOT NULL THEN
    RAISE EXCEPTION 'Solo un duplicado lleva "duplicado de".' USING ERRCODE = 'check_violation';
  END IF;
  IF p_evidence_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.sales_rec_evidence WHERE id = p_evidence_id AND target_id = p_target AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Esa evidencia no es de este pedido.' USING ERRCODE = 'check_violation';
  END IF;
  IF p_decision IN ('venta_confirmada', 'reembolso') AND p_evidence_id IS NULL THEN
    RAISE EXCEPTION 'Consulta la evidencia de WooCommerce antes de confirmar (botón "Consultar evidencia").' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO f360.sales_rec_decisions (target_id, woo_order_id, decision, duplicate_of, comment, evidence_id, woo_status_seen, facts_hash_seen,
                                        financial_seen, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, p_decision, p_duplicate_of, cmt, p_evidence_id, c.woo_status, c.economics_hash, c.financial_state, prev, uid,
          f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  SELECT * INTO after FROM f360.sales_rec_cases_state WHERE target_id = p_target AND woo_order_id = p_order;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'supersedes', prev, 'rec_state', after.rec_state, 'conflict', after.conflict,
                            'financial_state', after.financial_state);
END $$;

CREATE FUNCTION public.f360_rec_set_analytics(p_target uuid, p_order bigint, p_exclude boolean, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE uid uuid := f360.require_pii_viewer(); cur f360.sales_rec_exclusions; rsn text := btrim(coalesce(p_reason, '')); new_id bigint;
BEGIN
  IF p_exclude IS NULL THEN RAISE EXCEPTION 'Indica si se excluye o se vuelve a incluir.'; END IF;
  IF length(rsn) < 5 THEN RAISE EXCEPTION 'Escribe el motivo (mínimo 5 letras).' USING ERRCODE = 'check_violation'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('sales_rec_x:' || p_target || ':' || p_order, 0));
  IF NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = p_target AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found';
  END IF;
  SELECT * INTO cur FROM f360.sales_rec_exclusions WHERE target_id = p_target AND woo_order_id = p_order ORDER BY id DESC LIMIT 1;
  IF p_exclude AND cur.action = 'exclude' THEN RAISE EXCEPTION 'Ese pedido ya está excluido de las métricas.'; END IF;
  IF NOT p_exclude AND coalesce(cur.action, 'include') = 'include' THEN RAISE EXCEPTION 'Ese pedido ya está incluido en las métricas.'; END IF;
  INSERT INTO f360.sales_rec_exclusions (target_id, woo_order_id, action, reason, supersedes, decided_by, decided_by_name)
  VALUES (p_target, p_order, CASE WHEN p_exclude THEN 'exclude' ELSE 'include' END, rsn, cur.id, uid, f360.sales_rec_actor_name(uid))
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('ok', true, 'id', new_id, 'excluded', p_exclude);
END $$;

-- Service role only (f360-woo-sync): stores the minimal snapshot it read from WooCommerce for a verified viewer.
CREATE FUNCTION public.f360_rec_evidence_record(p_actor uuid, p_target_key text, p_order bigint, p_ev jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE tid uuid; tx text := nullif(btrim(coalesce(p_ev->>'transaction_ref', '')), ''); sigs text[]; res text; gw text := p_ev->>'gateway_result';
  snap jsonb; h text; new_id bigint; digits text;
BEGIN
  IF p_actor IS NULL OR NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers WHERE auth_user_id = p_actor) THEN
    RAISE EXCEPTION 'Solo las personas autorizadas pueden consultar evidencia.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  SELECT id INTO tid FROM f360.sales_targets WHERE key = p_target_key;
  IF tid IS NULL OR NOT EXISTS (SELECT 1 FROM f360.commerce_woo_orders WHERE target_id = tid AND woo_order_id = p_order) THEN
    RAISE EXCEPTION 'Ese pedido no está en Fuxia 360.' USING ERRCODE = 'no_data_found';
  END IF;
  IF gw IS NULL OR gw NOT IN ('approved', 'rejected', 'pending', 'refunded', 'transaction_only', 'no_evidence', 'order_missing') THEN
    RAISE EXCEPTION 'Resultado de pasarela no válido.';
  END IF;
  -- Never store anything that looks like a card number (13–19 digits); a gateway transaction id is never one.
  digits := regexp_replace(coalesce(tx, ''), '[\s-]', '', 'g');
  IF tx IS NOT NULL AND (digits ~ '^\d{13,19}$' OR length(tx) > 100) THEN tx := NULL; sigs := ARRAY['tx_redacted']; END IF;
  sigs := coalesce(sigs, '{}') || coalesce((SELECT array_agg(s) FROM jsonb_array_elements_text(coalesce(p_ev->'signals', '[]')) s
            WHERE s IN ('tx_present', 'tx_field', 'tx_meta_mercadopago', 'tx_meta_other', 'date_paid', 'note_approved', 'note_rejected', 'note_pending', 'note_refunded', 'refund_records',
                        'status_paid', 'status_unpaid', 'no_gateway_notes')), '{}');
  res := CASE gw
    WHEN 'approved' THEN 'La pasarela registró el pago como aprobado en WooCommerce'
    WHEN 'rejected' THEN 'La pasarela registró el pago como rechazado en WooCommerce'
    WHEN 'pending' THEN 'La pasarela dejó el pago pendiente en WooCommerce'
    WHEN 'refunded' THEN 'Hay reembolso registrado en WooCommerce'
    WHEN 'order_missing' THEN 'WooCommerce ya no tiene este pedido (no existe o fue borrado)'
    WHEN 'transaction_only' THEN 'WooCommerce tiene número de transacción pero no nota de la pasarela'
    ELSE 'WooCommerce no tiene número de transacción ni nota de la pasarela' END
    || CASE WHEN tx IS NOT NULL THEN ' · transacción ' || tx ELSE '' END || '.';
  snap := jsonb_build_object('source', 'woo_rest_order', 'source_ref', p_target_key || ':order/' || p_order, 'woo_status', p_ev->>'woo_status',
            'date_paid', p_ev->>'date_paid', 'transaction_ref', tx, 'payment_method', p_ev->>'payment_method', 'order_total', p_ev->>'order_total',
            'currency', p_ev->>'currency', 'refund_total', coalesce(p_ev->>'refund_total', '0'), 'gateway_result', gw, 'signals', to_jsonb(sigs),
            'queried_by', p_actor, 'queried_at', now());
  h := encode(extensions.digest(snap::text, 'sha256'), 'hex');
  INSERT INTO f360.sales_rec_evidence (target_id, woo_order_id, source, source_ref, woo_status, date_paid, transaction_ref, payment_method, order_total,
    currency, refund_total, gateway_result, signals, result, evidence_hash, queried_by, queried_by_name, queried_at)
  VALUES (tid, p_order, 'woo_rest_order', p_target_key || ':order/' || p_order, coalesce(p_ev->>'woo_status', '?'), (p_ev->>'date_paid')::timestamptz, tx,
    nullif(p_ev->>'payment_method', ''), (p_ev->>'order_total')::numeric, p_ev->>'currency', coalesce((p_ev->>'refund_total')::numeric, 0), gw, sigs, res,
    h, p_actor, f360.sales_rec_actor_name(p_actor), (snap->>'queried_at')::timestamptz)
  RETURNING id INTO new_id;
  RETURN jsonb_build_object('id', new_id, 'hash', h, 'result', res, 'transaction_ref', tx, 'gateway_result', gw, 'signals', to_jsonb(sigs));
END $$;

REVOKE ALL ON FUNCTION public.f360_rec_can_view(), public.f360_rec_list(date, date, text, text, text, text, text, text, int, int),
  public.f360_rec_summary(date, date, text), public.f360_rec_case(uuid, bigint), public.f360_rec_decide(uuid, bigint, text, text, bigint, bigint),
  public.f360_rec_set_analytics(uuid, bigint, boolean, text), public.f360_rec_evidence_record(uuid, text, bigint, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_rec_can_view(), public.f360_rec_list(date, date, text, text, text, text, text, text, int, int),
  public.f360_rec_summary(date, date, text), public.f360_rec_case(uuid, bigint), public.f360_rec_decide(uuid, bigint, text, text, bigint, bigint),
  public.f360_rec_set_analytics(uuid, bigint, boolean, text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.f360_rec_evidence_record(uuid, text, bigint, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.f360_rec_evidence_record(uuid, text, bigint, jsonb) TO service_role;
