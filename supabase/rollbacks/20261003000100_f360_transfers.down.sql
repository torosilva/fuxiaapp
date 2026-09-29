-- ROLLBACK for 20261003000100_f360_transfers.sql (STAGING).
-- Refuses to run if any transfer or "En camino" movement exists: history is never deleted by a rollback.
-- Restores the exact pre-transfer definitions (dumped from staging before the migration was applied).
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM f360.transfers) OR EXISTS (SELECT 1 FROM f360.inventory_movements m JOIN f360.locations l ON l.id IN (m.from_location_id, m.to_location_id) WHERE l.type = 'transit') THEN
    RAISE EXCEPTION 'Rollback refused: transfers / "En camino" movements exist. Resolve them explicitly first.';
  END IF;
END $$;

DROP FUNCTION public.f360_request_transfer(uuid, uuid, uuid, jsonb, text, boolean), public.f360_cancel_transfer(uuid, uuid, text),
  public.f360_send_transfer(uuid, uuid, jsonb), public.f360_receive_transfer(uuid, uuid, jsonb),
  public.f360_resolve_transfer_difference(uuid, uuid, jsonb, text), public.f360_list_transfers(text, int), public.f360_get_transfer(uuid),
  public.f360_transfer_locations();
DROP FUNCTION f360.transfer_do_send(uuid, uuid, jsonb, f360.user_roles), f360.transfer_qty_lines(jsonb, boolean),
  f360.transfer_audit(f360.transfers, uuid, text, text, jsonb, text, uuid[], f360.user_roles),
  f360.transfer_replay(uuid, uuid, text, f360.user_roles), f360.transfer_json(uuid, f360.user_roles),
  f360.can_see_transfer(f360.user_roles, f360.transfers), f360.ledger_move(uuid, uuid, uuid, uuid, int);
DROP TABLE f360.transfer_changes, f360.transfer_lines, f360.transfers;
DROP FUNCTION f360.guard_transfer(), f360.guard_transfer_line();
DROP SEQUENCE f360.transfer_number_seq;
DROP TRIGGER location_assignments_no_transit ON f360.location_assignments;
DROP FUNCTION f360.reject_transit_assignment();

CREATE OR REPLACE FUNCTION f360.assert_ledger_location(p_location uuid)
 RETURNS f360.locations
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE l f360.locations;
BEGIN
  SELECT * INTO l FROM f360.locations WHERE id = p_location AND status = 'active';
  IF l.id IS NULL THEN RAISE EXCEPTION 'Elige una ubicación válida.'; END IF;
  IF l.ledger_authority <> 'f360' THEN
    RAISE EXCEPTION '% todavía lleva su inventario en el sistema anterior. Se podrá operar aquí cuando se migre.', l.name;
  END IF;
  RETURN l;
END $function$
;

CREATE OR REPLACE FUNCTION f360.require_location(p_location uuid)
 RETURNS f360.user_roles
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location AND status = 'active') THEN RAISE EXCEPTION 'Ubicación no válida.'; END IF;
  IF r.role IN ('owner', 'operator') THEN RETURN r; END IF;
  IF r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = p_location AND a.active) THEN
    RETURN r;
  END IF;
  RAISE EXCEPTION 'No tienes asignada esta ubicación.' USING ERRCODE = 'insufficient_privilege';
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_get_product(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE result jsonb; online f360.locations;
BEGIN
  PERFORM f360.require_role('viewer');
  online := f360.online_location();
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.name, 'code', p.code, 'codes_locked', p.codes_locked_at IS NOT NULL,
    'category', cat.name, 'category_key', p.category_key,
    'description', p.description, 'short_description', p.short_description,
    'regular_price', p.regular_price, 'sale_price', p.sale_price,
    'image_path', f360.product_primary_image(p.id),
    'readiness', f360.product_readiness(p.id),
    'online_location', CASE WHEN online.id IS NULL THEN NULL ELSE jsonb_build_object('id', online.id, 'name', online.name) END,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]'::jsonb) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'code', c.code, 'hex', c.hex, 'image_path', f360.color_primary_image(c.id),
        'media', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'path', m.storage_path) ORDER BY m.sort, m.created_at), '[]'::jsonb)
                  FROM f360.product_media m WHERE m.color_id = c.id),
        'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'size', v.size_label, 'sku', v.sku) ORDER BY ps.sort), '[]'::jsonb)
                     FROM f360.product_variants v JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
                     WHERE v.color_id = c.id AND v.status = 'active'),
        'balances', (SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', b.location_id, 'size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0))
        ORDER BY c.sort, c.created_at), '[]'::jsonb) FROM f360.product_colors c WHERE c.product_id = p.id),
    'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))
  INTO result FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key WHERE p.id = p_product_id;
  IF result IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN result;
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_home()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'display_name', r.display_name, 'role', r.role,
    'locations', public.f360_list_locations(),
    'recent', public.f360_list_events(5, NULL, NULL),
    'product_count', (SELECT count(*) FROM f360.products WHERE status = 'active'));
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_inventory_by_location(p_location_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(loc ORDER BY (loc->>'sort')::int, loc->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sort', l.sort,
      'is_authoritative', l.is_authoritative, 'sales_sync_pending', l.sales_sync_pending,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id),
      'products', (SELECT coalesce(jsonb_agg(pr ORDER BY pr->>'name'), '[]'::jsonb) FROM (
          SELECT jsonb_build_object('id', p.id, 'name', p.name, 'image_path', f360.product_primary_image(p.id),
            'pairs', sum(b.on_hand),
            'colors', (SELECT jsonb_agg(jsonb_build_object('name', c2.name, 'hex', c2.hex,
                         'sizes', (SELECT jsonb_agg(jsonb_build_object('size', v3.size_label, 'on_hand', b3.on_hand) ORDER BY ps3.sort)
                                   FROM f360.inventory_balances b3 JOIN f360.product_variants v3 ON v3.id = b3.variant_id
                                   JOIN f360.product_sizes ps3 ON ps3.product_id = v3.product_id AND ps3.label = v3.size_label
                                   WHERE b3.location_id = l.id AND v3.color_id = c2.id AND b3.on_hand > 0))
                         ORDER BY c2.sort)
                       FROM f360.product_colors c2 WHERE c2.product_id = p.id AND EXISTS (
                         SELECT 1 FROM f360.inventory_balances b4 JOIN f360.product_variants v4 ON v4.id = b4.variant_id
                         WHERE b4.location_id = l.id AND v4.color_id = c2.id AND b4.on_hand > 0))) AS pr
          FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id JOIN f360.products p ON p.id = v.product_id
          WHERE b.location_id = l.id AND b.on_hand > 0 GROUP BY p.id) q)) AS loc
    FROM f360.locations l WHERE l.status = 'active' AND (p_location_id IS NULL OR l.id = p_location_id)) s);
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_list_locations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'name', l.name, 'type', l.type, 'is_authoritative', l.is_authoritative,
      'sales_sync_pending', l.sales_sync_pending, 'ledger_authority', l.ledger_authority, 'sellable', l.sellable,
      'starts_on', l.starts_on, 'ends_on', l.ends_on,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id))
      ORDER BY l.sort, l.name), '[]'::jsonb)
    FROM f360.locations l WHERE l.status = 'active');
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_list_products(p_query text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'last_activity') DESC NULLS LAST, x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'name', p.name, 'code', p.code, 'category', cat.name, 'image_path', f360.product_primary_image(p.id),
      'regular_price', p.regular_price, 'sale_price', p.sale_price,
      'ready', (f360.product_readiness(p.id)->>'ready')::boolean,
      'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex) ORDER BY c.sort, c.name), '[]'::jsonb)
                 FROM f360.product_colors c WHERE c.product_id = p.id),
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id),
      'last_activity', greatest(p.updated_at, (SELECT max(b.updated_at) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))) AS x
    FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key
    WHERE p.status = 'active'
      AND (p_query IS NULL OR btrim(p_query) = '' OR p.name ILIKE '%' || btrim(p_query) || '%'
           OR EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id AND c.name ILIKE '%' || btrim(p_query) || '%'))
  ) s);
END $function$
;

CREATE OR REPLACE FUNCTION public.f360_my_locations()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sellable', l.sellable,
      'ledger_authority', l.ledger_authority) ORDER BY l.sort, l.name), '[]')
    FROM f360.locations l
    WHERE l.status = 'active' AND (
      r.role IN ('owner', 'operator')
      OR (r.role = 'seller' AND EXISTS (SELECT 1 FROM f360.location_assignments a WHERE a.auth_user_id = r.auth_user_id AND a.location_id = l.id AND a.active))));
END $function$
;

DROP FUNCTION f360.transit_location();
DELETE FROM f360.inventory_balances WHERE location_id IN (SELECT id FROM f360.locations WHERE type = 'transit') AND on_hand = 0;
DELETE FROM f360.locations WHERE type = 'transit';
DROP INDEX f360.locations_single_transit;
ALTER TABLE f360.locations DROP CONSTRAINT locations_transit_not_sellable;
ALTER TABLE f360.locations DROP CONSTRAINT locations_type_check;
ALTER TABLE f360.locations ADD CONSTRAINT locations_type_check CHECK (type IN ('warehouse', 'receiving', 'store', 'bazaar', 'workshop', 'other'));
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
