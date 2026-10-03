-- Rollback of 20261007001300_f360_reservations_app.sql: restores f360_shift_catalog (20261004000100) and f360_reservations (20261007001100).
SELECT cron.unschedule('f360-push-retry');
DROP TRIGGER IF EXISTS reservations_notify ON f360.reservations;
DROP FUNCTION IF EXISTS f360.notify_reservation();
DROP FUNCTION IF EXISTS public.f360_push_claim(int);
DROP FUNCTION IF EXISTS public.f360_push_result(jsonb);
DROP FUNCTION IF EXISTS public.f360_shift_reservations(text);
DROP FUNCTION IF EXISTS public.f360_shift_reservation_separate(text, uuid);
DROP FUNCTION IF EXISTS f360.push_tick();
DROP FUNCTION IF EXISTS f360.location_team(uuid);
DROP TABLE IF EXISTS f360.push_outbox;
CREATE OR REPLACE FUNCTION public.f360_shift_catalog(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE s f360.seller_sessions; l f360.locations;
BEGIN
  s := f360.require_seller_session(p_token);
  SELECT * INTO l FROM f360.locations WHERE id = s.location_id;
  IF l.ledger_authority = 'f360' THEN
    RETURN jsonb_build_object('location', l.name, 'ledger', 'f360', 'in_cutover', false, 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'variant_id', v.id, 'product_name', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
        'price', coalesce(p.sale_price, p.regular_price), 'available', b.on_hand) ORDER BY p.name, c.sort, v.size_label), '[]'::jsonb)
      FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id WHERE b.location_id = l.id AND b.on_hand > 0));
  END IF;
  RETURN jsonb_build_object('location', l.name, 'ledger', 'legacy', 'in_cutover', f360.location_in_cutover(l.id), 'items', (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'channel_inventory_id', ci.id, 'product_name', ci.product_name, 'color', ci.color, 'size', ci.size, 'sku', ci.sku, 'price', ci.price,
      'available', greatest(coalesce(ci.stock, 0) - coalesce(ci.sold, 0), 0)) ORDER BY ci.product_name, ci.color, ci.size), '[]'::jsonb)
    FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id AND coalesce(ci.stock, 0) - coalesce(ci.sold, 0) > 0));
END $$;
CREATE OR REPLACE FUNCTION public.f360_reservations(p_location_id uuid DEFAULT NULL, p_days int DEFAULT 7) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'location_id', r.location_id, 'store', l.name,
      'variant_id', r.variant_id, 'product', p.name, 'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku,
      'customer', cu.name, 'phone_last4', right(regexp_replace(cu.phone, '\D', '', 'g'), 4), 'channel', r.channel,
      'status', CASE WHEN r.status = 'activa' AND r.expires_at <= clock_timestamp() THEN 'vencida' ELSE r.status END,
      'created_at', r.created_at, 'expires_at', r.expires_at, 'closed_at', r.closed_at, 'closed_by', r.closed_by, 'closed_reason', r.closed_reason)
      ORDER BY (r.status = 'activa' AND r.expires_at > clock_timestamp()) DESC, r.created_at DESC), '[]')
    FROM f360.reservations r JOIN f360.locations l ON l.id = r.location_id JOIN f360.product_variants v ON v.id = r.variant_id
    JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id JOIN public.customers cu ON cu.id = r.customer_id
    WHERE (p_location_id IS NULL OR r.location_id = p_location_id) AND r.created_at > now() - make_interval(days => greatest(1, least(p_days, 90))));
END $$;
ALTER TABLE f360.reservations DROP COLUMN IF EXISTS separated_at, DROP COLUMN IF EXISTS separated_by;
