-- Rollback of 20261019000200: previous f360.sales_facts (store only) and f360_list_sales (online not available).
CREATE OR REPLACE VIEW f360.sales_facts AS
 SELECT 'store'::text AS channel,
    sale_id,
    source,
    created_at AS occurred_at,
    location_id,
    seller_auth_user_id,
    customer_id,
    total,
    units,
    payment_method,
    self_sale,
    points_earned,
    claimed_at,
    'completed'::text AS status
   FROM f360.store_sale_facts f;
CREATE OR REPLACE FUNCTION public.f360_list_sales(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_location_id uuid DEFAULT NULL::uuid, p_seller_id uuid DEFAULT NULL::uuid, p_channel text DEFAULT NULL::text, p_limit integer DEFAULT 200) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$

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
END 
$fn$;
