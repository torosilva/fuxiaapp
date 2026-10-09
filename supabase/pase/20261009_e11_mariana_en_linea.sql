-- Fuxia 360 · pase E11 (2026-10-08) — Mario: Mariana Cantú (San Pedro Garza García) compró los dos pares "de la web"; la tienda
-- en línea no le funcionó y pagó a Carolina por WhatsApp → "aunque no haya podido pagar, ponlo en línea".
-- 1 · migration 20261019000100 (ventas a distancia: sale_channel_overrides + remote_sales + commerce_orders).
-- 2 · Canutillos Dorado 38 (store sale c30d6b65…, Polanco, $2,800, pase D9): counts as ONLINE / remote_whatsapp. Stock stays at Polanco.
-- 3 · Loafers animal print 38 ($2,800, paid, ordered from Colombia, arriving next week; custom request 69d55775…): a remote sale,
--     ONLINE, no inventory movement. Loyalty points of the Loafers: NOT granted here (pending Mario's decision).
-- Apply ONLY with scripts/f360/prod_sql.sh.
BEGIN;
-- Fuxia 360 · ventas a distancia (Mario 2026-10-08: Mariana Cantú, San Pedro Garza García — "aunque no haya podido pagar
-- [en la tienda en línea] ponlo en línea"). ADDITIVE. Two auditable ways to count a sale made at a distance as ONLINE:
--   · f360.sale_channel_overrides: a STORE sale (public.offline_sales, created by the store-sale RPC) that was really sold at a
--     distance keeps its stock movement at its store, but counts as channel 'online' / business_origin 'remote_whatsapp'.
--     One row per sale; never edited (who, when, why). Nothing in offline_sales changes.
--   · f360.remote_sales: a PAID sale with no inventory movement (e.g. a made-to-order pair still on its way: not in the
--     catalog, not in stock). Counts as channel 'online', data_quality PARTIAL ('manual_remote_sale', 'no_inventory_movement').
--     Never edited; a mistake is voided once (voided_at + void_reason).
--   · f360.commerce_orders (and through it f360.measurement_sales) gains both; same columns, same order, same types.
-- Loyalty points of a remote sale are NOT granted here (separate decision).
-- Rollback: supabase/rollbacks/20261019000100_f360_remote_sales.down.sql

CREATE TABLE f360.sale_channel_overrides (
  store_sale_id   uuid PRIMARY KEY REFERENCES public.offline_sales(id) ON DELETE RESTRICT,
  channel         text NOT NULL CHECK (channel IN ('online')),
  business_origin text NOT NULL CHECK (business_origin IN ('remote_whatsapp', 'remote_instagram', 'remote_other')),
  reason          text NOT NULL CHECK (length(btrim(reason)) >= 5),
  set_by_name     text NOT NULL,
  set_at          timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE f360.remote_sales (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id       uuid REFERENCES public.customers(id) ON DELETE RESTRICT,
  custom_request_id uuid REFERENCES f360.custom_requests(id) ON DELETE RESTRICT,
  product_name      text NOT NULL,
  color             text,
  size              text,
  quantity          int NOT NULL CHECK (quantity BETWEEN 1 AND 99),
  unit_price        numeric NOT NULL CHECK (unit_price > 0),
  currency          text NOT NULL DEFAULT 'MXN' CHECK (currency IN ('MXN', 'COP', 'USD')),
  market            text NOT NULL DEFAULT 'MX' CHECK (market IN ('MX', 'CO', 'US')),
  payment_method    text NOT NULL CHECK (payment_method IN ('cash', 'card', 'transfer', 'other')),
  business_origin   text NOT NULL CHECK (business_origin IN ('remote_whatsapp', 'remote_instagram', 'remote_other')),
  paid_at           timestamptz NOT NULL,
  note              text,
  created_by_name   text NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now(),
  voided_at         timestamptz,
  void_reason       text,
  CHECK ((voided_at IS NULL) = (void_reason IS NULL))
);
-- never deleted; overrides never change; a remote sale can only be voided, once
CREATE FUNCTION f360.remote_sales_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'No se borra: se anula con motivo.'; END IF;
  IF TG_TABLE_NAME = 'sale_channel_overrides' THEN RAISE EXCEPTION 'Este registro no se edita.'; END IF;
  IF OLD.voided_at IS NOT NULL OR NEW.voided_at IS NULL
     OR (to_jsonb(NEW) - 'voided_at' - 'void_reason') <> (to_jsonb(OLD) - 'voided_at' - 'void_reason') THEN
    RAISE EXCEPTION 'Una venta a distancia solo se puede anular (con motivo), una vez.';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER sale_channel_overrides_guard BEFORE UPDATE OR DELETE ON f360.sale_channel_overrides FOR EACH ROW EXECUTE FUNCTION f360.remote_sales_guard();
CREATE TRIGGER remote_sales_guard BEFORE UPDATE OR DELETE ON f360.remote_sales FOR EACH ROW EXECUTE FUNCTION f360.remote_sales_guard();
ALTER TABLE f360.sale_channel_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE f360.remote_sales ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON f360.sale_channel_overrides, f360.remote_sales FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.sale_channel_overrides, f360.remote_sales TO service_role;

CREATE OR REPLACE VIEW f360.commerce_orders AS
 SELECT 'woo'::text AS source_system,
    o.business_origin,
    o.created_via,
    'online'::text AS channel,
    (t.key || ':'::text) || o.woo_order_id AS external_ref,
    o.target_id,
    o.woo_order_id,
    NULL::uuid AS store_sale_id,
    NULL::uuid AS location_id,
    o.woo_created_at AS occurred_at,
    COALESCE(o.first_paid_at, o.paid_at) AS paid_at,
    o.woo_status AS status,
    f360.commerce_status_class(o.woo_status, o.ever_paid) AS status_class,
        CASE
            WHEN NOT o.ever_paid THEN 'never_paid'::text
            WHEN o.woo_status = 'cancelled'::text THEN 'paid_cancelled'::text
            WHEN o.woo_status = 'refunded'::text OR COALESCE(rt.refund_total, 0::numeric) >= COALESCE(o.paid_order_total, o.order_total) AND COALESCE(rt.refund_total, 0::numeric) > 0::numeric THEN 'paid_refunded_full'::text
            WHEN COALESCE(rt.refund_total, 0::numeric) > 0::numeric THEN 'paid_refunded_partial'::text
            ELSE 'paid'::text
        END AS payment_state,
    o.market,
    o.currency AS currency_original,
    o.payment_method,
    o.payment_category,
    o.woo_customer_id,
    tx.customer_id AS loyalty_customer_id,
        CASE
            WHEN tx.customer_id IS NOT NULL THEN 'loyalty_member'::text
            WHEN o.woo_customer_id IS NOT NULL THEN 'registered'::text
            ELSE 'guest'::text
        END AS customer_link_status,
    o.units,
    o.items_subtotal AS product_gross,
    o.discount_total AS discount,
    o.items_total AS product_net,
    o.shipping_total AS shipping,
    o.total_tax AS tax,
    o.fees_total + o.fees_tax AS fees,
    o.order_total,
    COALESCE(rt.refund_total, 0::numeric) AS refund_total,
    COALESCE(rt.refund_product, 0::numeric) AS refund_product,
    o.items_total - LEAST(COALESCE(rt.refund_product, 0::numeric), o.items_total) AS net_product,
    o.order_total - LEAST(COALESCE(rt.refund_total, 0::numeric), o.order_total) AS net_order_total,
    o.paid_items_total,
    o.paid_order_total,
        CASE
            WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 OR abs(o.items_subtotal - o.items_total - o.discount_total) > 0.01 THEN 'UNVERIFIED'::text
            WHEN COALESCE(rt.has_header_only, false) OR o.market_conflict OR o.business_origin = 'unknown'::text OR o.ever_paid AND o.woo_status = 'cancelled'::text AND o.paid_order_total IS NULL THEN 'PARTIAL'::text
            ELSE 'VERIFIED'::text
        END AS data_quality,
    array_remove(ARRAY[
        CASE
            WHEN abs(o.order_total - (o.items_total + o.cart_tax + o.shipping_total + o.shipping_tax + o.fees_total + o.fees_tax)) > 0.01 THEN 'total_does_not_reconcile'::text
            ELSE NULL::text
        END,
        CASE
            WHEN abs(o.items_subtotal - o.items_total - o.discount_total) > 0.01 THEN 'discount_does_not_reconcile'::text
            ELSE NULL::text
        END,
        CASE
            WHEN COALESCE(rt.has_header_only, false) THEN 'refund_without_line_detail'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.market_conflict THEN 'market_conflict_currency_vs_path'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.business_origin = 'unknown'::text THEN 'origin_unknown'::text
            ELSE NULL::text
        END,
        CASE
            WHEN o.ever_paid AND o.woo_status = 'cancelled'::text AND o.paid_order_total IS NULL THEN 'paid_value_unknown'::text
            ELSE NULL::text
        END], NULL::text) AS data_quality_reasons,
    'woo_order:'::text || o.last_captured_via AS provenance
   FROM f360.commerce_woo_orders o
     JOIN f360.sales_targets t ON t.id = o.target_id
     LEFT JOIN f360.commerce_woo_refund_totals rt ON rt.target_id = o.target_id AND rt.woo_order_id = o.woo_order_id
     LEFT JOIN LATERAL ( SELECT lc.customer_id
           FROM transactions x
             JOIN loyalty_cards lc ON lc.id = x.loyalty_card_id
          WHERE x.wc_order_id = o.woo_order_id
          ORDER BY x.created_at
         LIMIT 1) tx ON true
UNION ALL
 SELECT 'f360_store'::text AS source_system,
    COALESCE(ov.business_origin, 'physical_store'::text) AS business_origin,
    'f360_rpc'::text AS created_via,
    COALESCE(ov.channel, 'store'::text) AS channel,
    'store_sale:'::text || s.id AS external_ref,
    NULL::uuid AS target_id,
    NULL::bigint AS woo_order_id,
    s.id AS store_sale_id,
    s.location_id,
    s.created_at AS occurred_at,
    s.created_at AS paid_at,
    'completed'::text AS status,
    'countable'::text AS status_class,
    'paid'::text AS payment_state,
    'MX'::text AS market,
    'MXN'::text AS currency_original,
    s.payment_method,
        CASE s.payment_method
            WHEN 'cash'::text THEN 'cash'::text
            WHEN 'card'::text THEN 'card'::text
            WHEN 'transfer'::text THEN 'transfer'::text
            ELSE 'other'::text
        END AS payment_category,
    NULL::bigint AS woo_customer_id,
    s.customer_id AS loyalty_customer_id,
        CASE
            WHEN s.customer_id IS NOT NULL THEN 'loyalty_member'::text
            ELSE 'anonymous'::text
        END AS customer_link_status,
    li.units,
    li.gross AS product_gross,
    0 AS discount,
    li.gross AS product_net,
    0 AS shipping,
    0 AS tax,
    0 AS fees,
    s.total AS order_total,
    0 AS refund_total,
    0 AS refund_product,
    li.gross AS net_product,
    s.total AS net_order_total,
    li.gross AS paid_items_total,
    s.total AS paid_order_total,
        CASE
            WHEN abs(s.total - li.gross) > 0.01 THEN 'UNVERIFIED'::text
            ELSE 'VERIFIED'::text
        END AS data_quality,
    array_remove(ARRAY[
        CASE
            WHEN abs(s.total - li.gross) > 0.01 THEN 'total_does_not_match_lines'::text
            ELSE NULL::text
        END, 'currency_implied_mxn'::text], NULL::text) AS data_quality_reasons,
    'offline_sales:created_by_rpc'::text AS provenance
   FROM offline_sales s
     JOIN LATERAL ( SELECT COALESCE(sum(i.quantity), 0::bigint)::integer AS units,
            COALESCE(sum(i.line_total), 0::numeric) AS gross
           FROM offline_sale_items i
          WHERE i.sale_id = s.id) li ON true
     LEFT JOIN f360.sale_channel_overrides ov ON ov.store_sale_id = s.id
  WHERE s.created_by_rpc
UNION ALL
 SELECT 'f360_remote'::text AS source_system,
    r.business_origin,
    'f360_remote_sale'::text AS created_via,
    'online'::text AS channel,
    'remote_sale:'::text || r.id AS external_ref,
    NULL::uuid AS target_id,
    NULL::bigint AS woo_order_id,
    NULL::uuid AS store_sale_id,
    NULL::uuid AS location_id,
    r.paid_at AS occurred_at,
    r.paid_at,
    'completed'::text AS status,
    'countable'::text AS status_class,
    'paid'::text AS payment_state,
    r.market,
    r.currency AS currency_original,
    r.payment_method,
        CASE r.payment_method
            WHEN 'cash'::text THEN 'cash'::text
            WHEN 'card'::text THEN 'card'::text
            WHEN 'transfer'::text THEN 'transfer'::text
            ELSE 'other'::text
        END AS payment_category,
    NULL::bigint AS woo_customer_id,
    r.customer_id AS loyalty_customer_id,
        CASE
            WHEN r.customer_id IS NOT NULL THEN 'loyalty_member'::text
            ELSE 'anonymous'::text
        END AS customer_link_status,
    r.quantity AS units,
    r.unit_price * r.quantity::numeric AS product_gross,
    0 AS discount,
    r.unit_price * r.quantity::numeric AS product_net,
    0 AS shipping,
    0 AS tax,
    0 AS fees,
    r.unit_price * r.quantity::numeric AS order_total,
    0 AS refund_total,
    0 AS refund_product,
    r.unit_price * r.quantity::numeric AS net_product,
    r.unit_price * r.quantity::numeric AS net_order_total,
    r.unit_price * r.quantity::numeric AS paid_items_total,
    r.unit_price * r.quantity::numeric AS paid_order_total,
    'PARTIAL'::text AS data_quality,
    ARRAY['manual_remote_sale'::text, 'no_inventory_movement'::text] AS data_quality_reasons,
    'f360.remote_sales'::text AS provenance
   FROM f360.remote_sales r
  WHERE r.voided_at IS NULL;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements) VALUES ('20261019000100', 'f360_remote_sales', '{}');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE id = 'c30d6b65-f542-471c-a77e-c4ef027ad294' AND customer_id = '353aaa2a-8be1-470c-8450-4e69a236138b' AND created_by_rpc) THEN
    RAISE EXCEPTION 'ABORT: venta de Mariana (c30d6b65) no encontrada';
  END IF;
END $$;
INSERT INTO f360.sale_channel_overrides (store_sale_id, channel, business_origin, reason, set_by_name)
  VALUES ('c30d6b65-f542-471c-a77e-c4ef027ad294', 'online', 'remote_whatsapp',
          'Mariana Cantú compró en la web; la tienda en línea no le funcionó y pagó a Carolina por WhatsApp (Mario 2026-10-08)', 'Mario Silva');
INSERT INTO f360.remote_sales (customer_id, custom_request_id, product_name, color, size, quantity, unit_price, payment_method, business_origin, paid_at, note, created_by_name)
  VALUES ('353aaa2a-8be1-470c-8450-4e69a236138b', '69d55775-8380-4191-aa13-1abe2f708d62', 'Loafers animal print', 'Animal print', '38', 1, 2800, 'other',
          'remote_whatsapp', '2026-10-08T14:37:20Z', 'Pagado a Carolina por WhatsApp; pedido a Colombia, llega la próxima semana; se envía junto con el Canutillos', 'Mario Silva');
SELECT jsonb_build_object('mariana_online', (SELECT jsonb_agg(jsonb_build_object('ref', external_ref, 'channel', channel, 'net', net_product)) FROM f360.commerce_orders WHERE loyalty_customer_id = '353aaa2a-8be1-470c-8450-4e69a236138b'));
COMMIT;
