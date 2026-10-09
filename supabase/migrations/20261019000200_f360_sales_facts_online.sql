-- Fuxia 360 · Ventas / Inicio / Mapa del negocio count ONLINE sales too (Mario 2026-10-08: "¿por qué en línea me aparece 0?").
-- f360.sales_facts (read by f360_list_sales → Ventas, Inicio, Mapa del negocio) only had store sales, so "En línea" was always 0.
-- Now (same columns and types):
--   · store sales keep everything, but a sale marked as sold at a distance (f360.sale_channel_overrides) shows channel 'online';
--   · f360.remote_sales (paid, not voided) → channel 'online', source 'remote';
--   · paid online-store orders (commerce_status_class = 'countable', MXN only — this list sums MXN; COP/USD orders stay in
--     Growth → Medición, per currency) → channel 'online', source 'woo', id = a stable uuid derived from target + order number.
-- f360_list_sales: "En línea" becomes selectable; rows without a seller show "En línea" instead of "Vendedora". Nothing else changes.
-- Rollback: supabase/rollbacks/20261019000200_f360_sales_facts_online.down.sql
CREATE OR REPLACE VIEW f360.sales_facts AS
 SELECT COALESCE(ov.channel, 'store'::text) AS channel,
    f.sale_id, f.source, f.created_at AS occurred_at, f.location_id, f.seller_auth_user_id, f.customer_id, f.total, f.units,
    f.payment_method, f.self_sale, f.points_earned, f.claimed_at, 'completed'::text AS status
   FROM f360.store_sale_facts f
     LEFT JOIN f360.sale_channel_overrides ov ON ov.store_sale_id = f.sale_id
UNION ALL
 SELECT 'online'::text, r.id, 'remote'::text, r.paid_at, NULL::uuid, NULL::uuid, r.customer_id, (r.unit_price * r.quantity)::numeric(10,2),
    r.quantity::bigint, r.payment_method, false, 0, NULL::timestamptz, 'completed'::text
   FROM f360.remote_sales r
  WHERE r.voided_at IS NULL AND r.currency = 'MXN'
UNION ALL
 SELECT 'online'::text, md5('woo:' || o.target_id || ':' || o.woo_order_id)::uuid, 'woo'::text, COALESCE(o.first_paid_at, o.paid_at, o.woo_created_at),
    NULL::uuid, NULL::uuid, NULL::uuid, o.order_total::numeric(10,2), o.units::bigint, o.payment_method, false, 0, NULL::timestamptz, o.woo_status
   FROM f360.commerce_woo_orders o
     JOIN f360.sales_targets t ON t.id = o.target_id AND t.is_production
  WHERE f360.commerce_status_class(o.woo_status, o.ever_paid) = 'countable' AND upper(coalesce(o.currency, 'MXN')) = 'MXN';

CREATE OR REPLACE FUNCTION public.f360_list_sales(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_location_id uuid DEFAULT NULL::uuid,
  p_seller_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT NULL::text, p_limit integer DEFAULT 200) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$

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
            'location', l.name, 'seller', coalesce(u.display_name, CASE WHEN f.seller_auth_user_id IS NULL THEN 'En línea' ELSE 'Vendedora' END), 'customer', c.name, 'pairs', f.units, 'total', f.total,
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
                                      jsonb_build_object('key', 'online', 'name', 'En línea', 'available', true)))));
END 
$fn$;
