-- Track C · C3.3 — Ventas (Fuxia 360 Web): a READ model over the authoritative sales already recorded by S0.3 / C3.
-- No second sales model: every row comes from public.offline_sales (created_by_rpc) through f360.store_sale_facts.
-- f360.sales_facts is the ONE place a sales screen reads from, with a `channel` column: today only 'store'.
-- P2.3B will add online orders here (UNION ALL of the Woo sales) — the same screen then shows both, no new dashboard.
-- Not included on purpose: sales written by the old client path (created_by_rpc = false: client-provided prices, no
-- idempotency) and manually reported figures (B4). No returns yet (DW4).
-- Access: owner / operator only (a seller does not need the global admin view).
-- Rollback: supabase/rollbacks/20261004000400_f360_c3_sales_read_model.down.sql

CREATE VIEW f360.sales_facts AS
  SELECT 'store'::text AS channel, f.sale_id, f.source, f.created_at AS occurred_at, f.location_id, f.seller_auth_user_id, f.customer_id,
         f.total, f.units, f.payment_method, f.self_sale, f.points_earned, f.claimed_at, 'completed'::text AS status
  FROM f360.store_sale_facts f;
COMMENT ON VIEW f360.sales_facts IS 'All authoritative sales, one row per sale. channel=store today; P2.3B adds channel=online here.';
REVOKE ALL ON f360.sales_facts FROM PUBLIC, anon, authenticated;

CREATE FUNCTION f360.mask_phone(p text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN p IS NULL OR length(p) < 4 THEN NULL ELSE '•••• ' || right(p, 4) END $$;

-- p_from / p_to are calendar days in Mexico City (inclusive).
CREATE FUNCTION public.f360_list_sales(p_from date DEFAULT NULL, p_to date DEFAULT NULL, p_location_id uuid DEFAULT NULL,
  p_seller_id uuid DEFAULT NULL, p_channel text DEFAULT NULL, p_limit int DEFAULT 200) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_from timestamptz; v_to timestamptz;
BEGIN
  r := f360.require_role('operator');
  v_from := coalesce(p_from, (now() AT TIME ZONE 'America/Mexico_City')::date - 29)::timestamp AT TIME ZONE 'America/Mexico_City';
  v_to := (coalesce(p_to, (now() AT TIME ZONE 'America/Mexico_City')::date) + 1)::timestamp AT TIME ZONE 'America/Mexico_City';
  RETURN (
    WITH f AS (
      SELECT * FROM f360.sales_facts s
      WHERE s.occurred_at >= v_from AND s.occurred_at < v_to
        AND (p_location_id IS NULL OR s.location_id = p_location_id)
        AND (p_seller_id IS NULL OR s.seller_auth_user_id = p_seller_id)
        AND (p_channel IS NULL OR s.channel = p_channel))
    SELECT jsonb_build_object(
      'from', (v_from AT TIME ZONE 'America/Mexico_City')::date, 'to', ((v_to AT TIME ZONE 'America/Mexico_City')::date - 1),
      'summary', (SELECT jsonb_build_object('revenue', coalesce(sum(total), 0), 'sales', count(*), 'pairs', coalesce(sum(units), 0),
                    'avg_ticket', CASE WHEN count(*) > 0 THEN round(sum(total) / count(*), 2) ELSE 0 END) FROM f),
      'items', (SELECT coalesce(jsonb_agg(x ORDER BY x->>'occurred_at' DESC), '[]'::jsonb) FROM (
          SELECT jsonb_build_object('id', f.sale_id, 'occurred_at', f.occurred_at, 'channel', f.channel, 'source', f.source, 'status', f.status,
            'location', l.name, 'seller', coalesce(u.display_name, 'Vendedora'), 'customer', c.name, 'pairs', f.units, 'total', f.total,
            'payment_method', f.payment_method, 'points', f.points_earned, 'self_sale', f.self_sale,
            'claim_pending', f.customer_id IS NULL AND f.claimed_at IS NULL) AS x
          FROM f LEFT JOIN f360.locations l ON l.id = f.location_id LEFT JOIN f360.user_roles u ON u.auth_user_id = f.seller_auth_user_id
          LEFT JOIN public.customers c ON c.id = f.customer_id
          ORDER BY f.occurred_at DESC LIMIT greatest(1, least(coalesce(p_limit, 200), 500))) q),
      'filters', jsonb_build_object(
        'locations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name) ORDER BY l.sort, l.name), '[]'::jsonb)
                      FROM f360.locations l WHERE l.type <> 'transit' AND (l.sellable OR EXISTS (SELECT 1 FROM f360.sales_facts s WHERE s.location_id = l.id))),
        'sellers', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name) ORDER BY x.name), '[]'::jsonb) FROM (
                      SELECT DISTINCT s.seller_auth_user_id AS id, coalesce(u.display_name, 'Vendedora') AS name FROM f360.sales_facts s
                      LEFT JOIN f360.user_roles u ON u.auth_user_id = s.seller_auth_user_id WHERE s.seller_auth_user_id IS NOT NULL) x),
        'channels', jsonb_build_array(jsonb_build_object('key', 'store', 'name', 'Tienda', 'available', true),
                                      jsonb_build_object('key', 'online', 'name', 'En línea', 'available', false)))));
END $$;

-- One sale, everything support needs. Loyalty: credited, or the exact reason it did not apply.
CREATE FUNCTION public.f360_get_sale(p_sale_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; s public.offline_sales; tx public.transactions; loyalty jsonb;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO s FROM public.offline_sales WHERE id = p_sale_id AND created_by_rpc;
  IF s.id IS NULL THEN RAISE EXCEPTION 'Venta no encontrada.'; END IF;
  SELECT * INTO tx FROM public.transactions WHERE id = s.loyalty_transaction_id;
  loyalty := CASE
    WHEN tx.id IS NOT NULL THEN jsonb_build_object('state', 'credited', 'points', tx.points_earned, 'pairs', tx.pairs_in_order, 'transaction_id', tx.id,
      'text', format('Se acreditaron %s puntos (%s pares × 100).', tx.points_earned, tx.pairs_in_order))
    WHEN s.self_sale THEN jsonb_build_object('state', 'self_sale', 'points', 0, 'text', 'Venta a la propia vendedora: no genera puntos (queda auditada).')
    WHEN s.customer_id IS NULL AND s.claimed_at IS NULL THEN jsonb_build_object('state', 'pending_claim', 'points', 0, 'code', s.code,
      'text', format('Sin clienta identificada. La clienta puede reclamar los puntos con el código %s.', s.code))
    ELSE jsonb_build_object('state', 'none', 'points', coalesce(s.points_earned, 0), 'text', 'No se acreditaron puntos.') END
    || jsonb_build_object('audit', (SELECT coalesce(jsonb_agg(jsonb_build_object('result', a.result, 'points', a.points, 'at', a.at) ORDER BY a.id), '[]'::jsonb)
                                    FROM public.loyalty_apply_audit a WHERE a.idempotency_key = 'offline_sale:' || s.id));
  RETURN jsonb_build_object(
    'id', s.id, 'occurred_at', s.created_at, 'channel', 'store', 'status', 'completed',
    'ledger', CASE WHEN s.sale_event_id IS NOT NULL THEN 'f360' ELSE 'legacy' END,
    'location', (SELECT jsonb_build_object('id', l.id, 'name', l.name) FROM f360.locations l WHERE l.id = s.location_id),
    'seller', coalesce((SELECT display_name FROM f360.user_roles WHERE auth_user_id = s.seller_auth_user_id), 'Vendedora'),
    'customer', (SELECT jsonb_build_object('name', c.name, 'phone', f360.mask_phone(c.phone)) FROM public.customers c WHERE c.id = s.customer_id),
    'total', s.total, 'payment_method', s.payment_method, 'payment_reference', s.payment_reference, 'price_source', s.price_source,
    'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('line', i.line_no, 'product_name', i.product_name, 'color', i.color, 'size', i.size, 'sku', i.sku,
                'quantity', i.quantity, 'unit_price', i.unit_price, 'line_total', i.line_total, 'price_source', i.price_source) ORDER BY i.line_no), '[]'::jsonb)
              FROM public.offline_sale_items i WHERE i.sale_id = s.id),
    'inventory', CASE WHEN s.sale_event_id IS NOT NULL THEN jsonb_build_object('kind', 'f360', 'event', f360.event_json(s.sale_event_id))
                      ELSE jsonb_build_object('kind', 'legacy', 'text', 'Descontado del inventario del sistema anterior de la tienda (antes de su migración).') END,
    'loyalty', loyalty,
    'support', jsonb_build_object('sale_id', s.id, 'idempotency_key', s.idempotency_key, 'claim_code', s.code, 'session_id', s.session_id,
      'sale_event_id', s.sale_event_id, 'loyalty_transaction_id', s.loyalty_transaction_id, 'seller_auth_user_id', s.seller_auth_user_id,
      'recorded_at', s.created_at, 'claimed_at', s.claimed_at));
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_list_sales(date, date, uuid, uuid, text, int), public.f360_get_sale(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_list_sales(date, date, uuid, uuid, text, int), public.f360_get_sale(uuid) TO authenticated, service_role;
