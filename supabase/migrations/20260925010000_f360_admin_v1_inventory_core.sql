-- Fuxia 360 Admin V1 — canonical product + inventory core (Product Sprint 1)
-- Spec: docs/fuxia360/admin/ADMIN_V1_PLAN.md · Rollback: supabase/rollbacks/20260925010000_f360_admin_v1_inventory_core.down.sql
--
-- * New schema `f360`, NOT exposed through the Data API: clients never touch these tables.
--   All access goes through public.f360_* SECURITY DEFINER functions that check a Fuxia 360 role.
-- * Roles live in f360.user_roles (owner/operator/viewer), written only by migrations/service role.
--   Independent of customers.role and of user_metadata.
-- * ONE canonical inventory ledger (D5): inventory_events (header, append-only) +
--   inventory_movements (lines, append-only; from/to location). Receipts now; transfers, sales,
--   fulfillment, returns, adjustments and production receipts reuse the same two tables.
--   inventory_balances is a derived cache maintained in the same transaction.
-- * Legacy tables (channels, channel_inventory, …) are untouched. channel_inventory is NOT canonical.

CREATE SCHEMA IF NOT EXISTS f360;
REVOKE ALL ON SCHEMA f360 FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA f360 TO service_role;

-- ── Roles ──────────────────────────────────────────────────────────────────
CREATE TABLE f360.user_roles (
  auth_user_id  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role          text NOT NULL CHECK (role IN ('owner', 'operator', 'viewer')),
  display_name  text NOT NULL,
  granted_by    text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ── Product master ─────────────────────────────────────────────────────────
CREATE TABLE f360.products (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL CHECK (length(btrim(name)) > 0),
  slug           text NOT NULL UNIQUE,
  category       text,
  status         text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  tier           text CHECK (tier IN ('A', 'B', 'C')),
  image_path     text,
  wc_product_id  integer,
  created_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE f360.product_colors (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  name        text NOT NULL CHECK (length(btrim(name)) > 0),
  hex         text CHECK (hex ~ '^#[0-9A-Fa-f]{6}$'),
  image_path  text,
  sort        integer NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX product_colors_product_name_key ON f360.product_colors (product_id, lower(name));

-- Size sets are per product (D6: 22–27 by halves is only the UI default).
CREATE TABLE f360.product_sizes (
  product_id  uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  label       text NOT NULL CHECK (length(btrim(label)) > 0),
  sort        integer NOT NULL,
  PRIMARY KEY (product_id, label)
);

CREATE TABLE f360.product_variants (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id              uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  color_id                uuid NOT NULL REFERENCES f360.product_colors(id) ON DELETE RESTRICT,
  size_label              text NOT NULL,
  sku                     text UNIQUE,
  barcode                 text,
  status                  text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
  make_to_order_eligible  boolean NOT NULL DEFAULT false,
  wc_variation_id         integer,
  created_at              timestamptz NOT NULL DEFAULT now(),
  UNIQUE (color_id, size_label),
  FOREIGN KEY (product_id, size_label) REFERENCES f360.product_sizes (product_id, label) ON DELETE RESTRICT
);

-- ── Locations ──────────────────────────────────────────────────────────────
CREATE TABLE f360.locations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL UNIQUE,
  type               text NOT NULL CHECK (type IN ('warehouse', 'receiving', 'store', 'bazaar', 'workshop', 'other')),
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  -- D1: authoritative = the ledger is the full truth for this location (bodega/receiving in V1).
  -- Store locations can receive transfers, but their sales sync is pending until POS integration,
  -- so their balances must not be used for immediate-delivery promises.
  is_authoritative   boolean NOT NULL DEFAULT false,
  sales_sync_pending boolean NOT NULL DEFAULT false,
  legacy_channel_id  uuid REFERENCES public.channels(id) ON DELETE SET NULL,
  sort               integer NOT NULL DEFAULT 0,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- ── Canonical inventory ledger ─────────────────────────────────────────────
CREATE TABLE f360.inventory_events (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type               text NOT NULL CHECK (event_type IN
                             ('RECEIPT', 'TRANSFER', 'SALE', 'RETURN', 'ADJUSTMENT',
                              'RESERVATION', 'RELEASE', 'WRITE_OFF', 'FULFILLMENT', 'PRODUCTION_RECEIPT')),
  idempotency_key          uuid NOT NULL UNIQUE,
  actor_auth_user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_name               text NOT NULL,           -- snapshot, so history survives renames
  actor_role               text NOT NULL,
  note                     text,
  business_reference_type  text,                    -- e.g. 'woo_order', 'offline_sale', 'production_request'
  business_reference_id    text,
  occurred_at              timestamptz NOT NULL DEFAULT now(),
  created_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX inventory_events_occurred_idx ON f360.inventory_events (occurred_at DESC);

CREATE TABLE f360.inventory_movements (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id          uuid NOT NULL REFERENCES f360.inventory_events(id) ON DELETE RESTRICT,
  variant_id        uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  from_location_id  uuid REFERENCES f360.locations(id) ON DELETE RESTRICT,
  to_location_id    uuid REFERENCES f360.locations(id) ON DELETE RESTRICT,
  quantity          integer NOT NULL CHECK (quantity > 0),
  CHECK (from_location_id IS NOT NULL OR to_location_id IS NOT NULL),
  CHECK (from_location_id IS DISTINCT FROM to_location_id)
);
CREATE INDEX inventory_movements_event_idx ON f360.inventory_movements (event_id);
CREATE INDEX inventory_movements_variant_idx ON f360.inventory_movements (variant_id);

CREATE TABLE f360.inventory_balances (
  variant_id     uuid NOT NULL REFERENCES f360.product_variants(id) ON DELETE RESTRICT,
  location_id    uuid NOT NULL REFERENCES f360.locations(id) ON DELETE RESTRICT,
  on_hand        integer NOT NULL DEFAULT 0 CHECK (on_hand >= 0),
  last_event_id  uuid REFERENCES f360.inventory_events(id),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (variant_id, location_id)
);

-- Ledger is append-only (no UPDATE/DELETE, for anyone).
CREATE FUNCTION f360.reject_ledger_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial de inventario no se puede modificar (%.%)', TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = 'insufficient_privilege';
END $$;
CREATE TRIGGER inventory_events_append_only BEFORE UPDATE OR DELETE ON f360.inventory_events
  FOR EACH ROW EXECUTE FUNCTION f360.reject_ledger_change();
CREATE TRIGGER inventory_movements_append_only BEFORE UPDATE OR DELETE ON f360.inventory_movements
  FOR EACH ROW EXECUTE FUNCTION f360.reject_ledger_change();

-- Explicit: no client privileges on any f360 table.
REVOKE ALL ON ALL TABLES IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA f360 TO service_role;

-- ── Helpers ────────────────────────────────────────────────────────────────
CREATE FUNCTION f360.role_rank(p_role text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE p_role WHEN 'owner' THEN 3 WHEN 'operator' THEN 2 WHEN 'viewer' THEN 1 ELSE 0 END $$;

-- Returns the caller's role row or raises. Identity comes only from auth.uid().
CREATE FUNCTION f360.require_role(p_min text) RETURNS f360.user_roles
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  SELECT * INTO r FROM f360.user_roles WHERE auth_user_id = auth.uid();
  IF r.auth_user_id IS NULL THEN
    RAISE EXCEPTION 'Esta cuenta no tiene acceso a Fuxia 360.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF f360.role_rank(r.role) < f360.role_rank(p_min) THEN
    RAISE EXCEPTION 'Tu cuenta no tiene permiso para esta acción.' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN r;
END $$;

CREATE FUNCTION f360.slugify(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT trim(both '-' from regexp_replace(lower(translate(p,
    'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
    'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC')), '[^a-z0-9]+', '-', 'g'))
$$;

-- Human-readable event (for history screens).
CREATE FUNCTION f360.event_json(p_event_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'type', e.event_type, 'actor_name', e.actor_name, 'note', e.note,
    'occurred_at', e.occurred_at,
    'total_pairs', (SELECT coalesce(sum(m.quantity), 0) FROM f360.inventory_movements m WHERE m.event_id = e.id),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'product_id', p.id, 'product_name', p.name, 'product_image', p.image_path,
        'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'quantity', m.quantity,
        'from_location', lf.name, 'to_location', lt.name)
        ORDER BY p.name, c.name, ps.sort), '[]'::jsonb)
      FROM f360.inventory_movements m
      JOIN f360.product_variants v ON v.id = m.variant_id
      JOIN f360.products p ON p.id = v.product_id
      JOIN f360.product_colors c ON c.id = v.color_id
      JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
      LEFT JOIN f360.locations lf ON lf.id = m.from_location_id
      LEFT JOIN f360.locations lt ON lt.id = m.to_location_id
      WHERE m.event_id = e.id))
  FROM f360.inventory_events e WHERE e.id = p_event_id
$$;

-- ── Public RPCs (the only client surface) ──────────────────────────────────
CREATE FUNCTION public.f360_me() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object('display_name', r.display_name, 'role', r.role);
END $$;

CREATE FUNCTION public.f360_list_locations() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', l.id, 'name', l.name, 'type', l.type, 'is_authoritative', l.is_authoritative,
      'sales_sync_pending', l.sales_sync_pending,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id))
      ORDER BY l.sort, l.name), '[]'::jsonb)
    FROM f360.locations l WHERE l.status = 'active');
END $$;

CREATE FUNCTION public.f360_list_products(p_query text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'last_activity') DESC NULLS LAST, x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'name', p.name, 'category', p.category, 'image_path', p.image_path,
      'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex) ORDER BY c.sort, c.name), '[]'::jsonb)
                 FROM f360.product_colors c WHERE c.product_id = p.id),
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id),
      'last_activity', greatest(p.updated_at, (SELECT max(b.updated_at) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))) AS x
    FROM f360.products p
    WHERE p.status = 'active'
      AND (p_query IS NULL OR btrim(p_query) = '' OR p.name ILIKE '%' || btrim(p_query) || '%'
           OR EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id AND c.name ILIKE '%' || btrim(p_query) || '%'))
  ) s);
END $$;

CREATE FUNCTION public.f360_get_product(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  PERFORM f360.require_role('viewer');
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.name, 'category', p.category, 'image_path', p.image_path,
    'sizes', (SELECT coalesce(jsonb_agg(s.label ORDER BY s.sort), '[]'::jsonb) FROM f360.product_sizes s WHERE s.product_id = p.id),
    'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'hex', c.hex, 'image_path', c.image_path,
        'variants', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'size', v.size_label) ORDER BY ps.sort), '[]'::jsonb)
                     FROM f360.product_variants v JOIN f360.product_sizes ps ON ps.product_id = v.product_id AND ps.label = v.size_label
                     WHERE v.color_id = c.id AND v.status = 'active'),
        'balances', (SELECT coalesce(jsonb_agg(jsonb_build_object('location_id', b.location_id, 'size', v.size_label, 'on_hand', b.on_hand)), '[]'::jsonb)
                     FROM f360.inventory_balances b JOIN f360.product_variants v ON v.id = b.variant_id
                     WHERE v.color_id = c.id AND b.on_hand > 0))
        ORDER BY c.sort, c.name), '[]'::jsonb) FROM f360.product_colors c WHERE c.product_id = p.id),
    'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
              JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))
  INTO result FROM f360.products p WHERE p.id = p_product_id;
  IF result IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.' USING ERRCODE = 'no_data_found'; END IF;
  RETURN result;
END $$;

-- Create a product with its colors and size set; variants = every color × size.
CREATE FUNCTION public.f360_create_product(p_name text, p_sizes text[], p_colors jsonb, p_category text DEFAULT NULL, p_image_path text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_id uuid; v_slug text; v_color jsonb; v_color_id uuid; v_i int := 0; v_size text;
BEGIN
  r := f360.require_role('operator');
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'Escribe el nombre del producto.'; END IF;
  IF p_sizes IS NULL OR cardinality(p_sizes) = 0 THEN RAISE EXCEPTION 'Elige al menos una talla.'; END IF;
  IF p_colors IS NULL OR jsonb_array_length(p_colors) = 0 THEN RAISE EXCEPTION 'Agrega al menos un color.'; END IF;
  v_slug := f360.slugify(p_name);
  IF EXISTS (SELECT 1 FROM f360.products WHERE slug = v_slug) THEN
    RAISE EXCEPTION 'Ya existe un producto llamado "%".', btrim(p_name);
  END IF;
  INSERT INTO f360.products (name, slug, category, image_path, created_by)
    VALUES (btrim(p_name), v_slug, nullif(btrim(p_category), ''), p_image_path, auth.uid()) RETURNING id INTO v_id;
  FOREACH v_size IN ARRAY p_sizes LOOP
    v_i := v_i + 1;
    INSERT INTO f360.product_sizes (product_id, label, sort) VALUES (v_id, btrim(v_size), v_i);
  END LOOP;
  v_i := 0;
  FOR v_color IN SELECT * FROM jsonb_array_elements(p_colors) LOOP
    v_i := v_i + 1;
    IF coalesce(btrim(v_color->>'name'), '') = '' THEN RAISE EXCEPTION 'Cada color necesita un nombre.'; END IF;
    INSERT INTO f360.product_colors (product_id, name, hex, image_path, sort)
      VALUES (v_id, btrim(v_color->>'name'), nullif(v_color->>'hex', ''), nullif(v_color->>'image_path', ''), v_i)
      RETURNING id INTO v_color_id;
    INSERT INTO f360.product_variants (product_id, color_id, size_label)
      SELECT v_id, v_color_id, label FROM f360.product_sizes WHERE product_id = v_id;
  END LOOP;
  RETURN public.f360_get_product(v_id);
END $$;

-- RECEIPT: merchandise arrives at a location. Atomic and idempotent.
-- p_lines: [{ "variant_id": uuid, "quantity": int }]
CREATE FUNCTION public.f360_receive_inventory(p_idempotency_key uuid, p_location_id uuid, p_lines jsonb, p_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_event uuid; v_line jsonb; v_qty int; v_variant uuid; v_total int := 0;
BEGIN
  r := f360.require_role('operator');
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'Falta la llave de la operación.'; END IF;
  SELECT id INTO v_event FROM f360.inventory_events WHERE idempotency_key = p_idempotency_key;
  IF v_event IS NOT NULL THEN RETURN f360.event_json(v_event) || jsonb_build_object('replayed', true); END IF;

  IF NOT EXISTS (SELECT 1 FROM f360.locations WHERE id = p_location_id AND status = 'active') THEN
    RAISE EXCEPTION 'Elige una ubicación válida.';
  END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' THEN RAISE EXCEPTION 'No hay cantidades para recibir.'; END IF;

  INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_auth_user_id, actor_name, actor_role, note)
    VALUES ('RECEIPT', p_idempotency_key, auth.uid(), r.display_name, r.role, nullif(btrim(p_note), ''))
    RETURNING id INTO v_event;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_qty := (v_line->>'quantity')::int;
    v_variant := (v_line->>'variant_id')::uuid;
    CONTINUE WHEN v_qty IS NULL OR v_qty = 0;
    IF v_qty < 0 THEN RAISE EXCEPTION 'Las cantidades no pueden ser negativas.'; END IF;
    IF NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE id = v_variant AND status = 'active') THEN
      RAISE EXCEPTION 'Una de las tallas no es válida.';
    END IF;
    INSERT INTO f360.inventory_movements (event_id, variant_id, from_location_id, to_location_id, quantity)
      VALUES (v_event, v_variant, NULL, p_location_id, v_qty);
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand, last_event_id, updated_at)
      VALUES (v_variant, p_location_id, v_qty, v_event, now())
      ON CONFLICT (variant_id, location_id)
      DO UPDATE SET on_hand = f360.inventory_balances.on_hand + EXCLUDED.on_hand, last_event_id = v_event, updated_at = now();
    v_total := v_total + v_qty;
  END LOOP;

  IF v_total = 0 THEN RAISE EXCEPTION 'Escribe al menos un par para recibir.'; END IF;
  UPDATE f360.products SET updated_at = now()
    WHERE id IN (SELECT v.product_id FROM f360.inventory_movements m JOIN f360.product_variants v ON v.id = m.variant_id WHERE m.event_id = v_event);
  RETURN f360.event_json(v_event) || jsonb_build_object('replayed', false);
END $$;

CREATE FUNCTION public.f360_list_events(p_limit int DEFAULT 50, p_product_id uuid DEFAULT NULL, p_location_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(f360.event_json(e.id) ORDER BY e.occurred_at DESC), '[]'::jsonb)
    FROM (SELECT e.id, e.occurred_at FROM f360.inventory_events e
          WHERE (p_product_id IS NULL OR EXISTS (SELECT 1 FROM f360.inventory_movements m JOIN f360.product_variants v ON v.id = m.variant_id
                                                 WHERE m.event_id = e.id AND v.product_id = p_product_id))
            AND (p_location_id IS NULL OR EXISTS (SELECT 1 FROM f360.inventory_movements m WHERE m.event_id = e.id
                                                  AND (m.to_location_id = p_location_id OR m.from_location_id = p_location_id)))
          ORDER BY e.occurred_at DESC LIMIT greatest(1, least(coalesce(p_limit, 50), 200))) e);
END $$;

CREATE FUNCTION public.f360_get_event(p_event_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE result jsonb;
BEGIN
  PERFORM f360.require_role('viewer');
  result := f360.event_json(p_event_id);
  IF result IS NULL THEN RAISE EXCEPTION 'Movimiento no encontrado.'; END IF;
  RETURN result;
END $$;

-- Inventory by location → product → color → size.
CREATE FUNCTION public.f360_inventory_by_location(p_location_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(loc ORDER BY (loc->>'sort')::int, loc->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object('id', l.id, 'name', l.name, 'type', l.type, 'sort', l.sort,
      'is_authoritative', l.is_authoritative, 'sales_sync_pending', l.sales_sync_pending,
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b WHERE b.location_id = l.id),
      'products', (SELECT coalesce(jsonb_agg(pr ORDER BY pr->>'name'), '[]'::jsonb) FROM (
          SELECT jsonb_build_object('id', p.id, 'name', p.name, 'image_path', p.image_path,
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
END $$;

CREATE FUNCTION public.f360_home() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles;
BEGIN
  r := f360.require_role('viewer');
  RETURN jsonb_build_object(
    'display_name', r.display_name, 'role', r.role,
    'locations', public.f360_list_locations(),
    'recent', public.f360_list_events(5, NULL, NULL),
    'product_count', (SELECT count(*) FROM f360.products WHERE status = 'active'));
END $$;

-- Grants: RPCs only for authenticated users (roles are checked inside). Nothing for anon/PUBLIC.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_me(), public.f360_list_locations(), public.f360_list_products(text),
  public.f360_get_product(uuid), public.f360_create_product(text, text[], jsonb, text, text),
  public.f360_receive_inventory(uuid, uuid, jsonb, text), public.f360_list_events(int, uuid, uuid),
  public.f360_get_event(uuid), public.f360_inventory_by_location(uuid), public.f360_home()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_me(), public.f360_list_locations(), public.f360_list_products(text),
  public.f360_get_product(uuid), public.f360_create_product(text, text[], jsonb, text, text),
  public.f360_receive_inventory(uuid, uuid, jsonb, text), public.f360_list_events(int, uuid, uuid),
  public.f360_get_event(uuid), public.f360_inventory_by_location(uuid), public.f360_home()
  TO authenticated, service_role;

-- Product photos: users with an f360 operator role may upload under product-images/f360/.
CREATE FUNCTION public.f360_can_upload() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT EXISTS (SELECT 1 FROM f360.user_roles WHERE auth_user_id = auth.uid() AND f360.role_rank(role) >= 2)
$$;
REVOKE EXECUTE ON FUNCTION public.f360_can_upload() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_can_upload() TO authenticated, service_role;

CREATE POLICY "f360 operators upload product images" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'product-images' AND (storage.foldername(name))[1] = 'f360' AND public.f360_can_upload());
