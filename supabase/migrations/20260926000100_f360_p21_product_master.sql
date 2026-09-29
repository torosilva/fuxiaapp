-- Fuxia 360 · P2.1 Product master (no WooCommerce). Additive; the inventory ledger is untouched.
-- Plan: docs/fuxia360/admin/WOO_PUBLISHING_V1_PLAN.md (P2.1) · Rollback: supabase/rollbacks/20260926000100_f360_p21_product_master.down.sql
--
-- * Canonical model: MODEL → COLOR → COLOMBIAN SIZE (35–40 …) → LOCATION. Sizes stay per-product labels.
-- * DW9 SKU identity: F360-{PRODUCT_CODE}-{COLOR_CODE}-{SIZE}. Codes are generated automatically and
--   become immutable once used for publishing (codes_locked_at, set by the P2.2 publisher).
-- * Photos: many per color (f360.product_media). Primary image = first photo of the first color.
-- * Commercial info for the future Woo product: description, short description, regular/sale price,
--   category (the 4 real Woo categories, as configuration).

-- ── Categories (configuration; names as used by the live store) ────────────
CREATE TABLE f360.categories (
  key   text PRIMARY KEY,
  name  text NOT NULL UNIQUE,
  sort  integer NOT NULL DEFAULT 0
);
INSERT INTO f360.categories (key, name, sort) VALUES
  ('ballerinas', 'Ballerinas', 1), ('sandalia-plana', 'Sandalia Plana', 2),
  ('sandalia-alta', 'Sandalia Alta', 3), ('botas', 'Botas', 4);

-- ── Product commercial fields + immutable code ─────────────────────────────
ALTER TABLE f360.products
  ADD COLUMN code              text,
  ADD COLUMN codes_locked_at   timestamptz,
  ADD COLUMN description       text,
  ADD COLUMN short_description text,
  ADD COLUMN regular_price     numeric(10,2) CHECK (regular_price IS NULL OR regular_price > 0),
  ADD COLUMN sale_price        numeric(10,2) CHECK (sale_price IS NULL OR sale_price > 0),
  ADD COLUMN category_key      text REFERENCES f360.categories(key),
  ADD CONSTRAINT products_sale_below_regular CHECK (sale_price IS NULL OR (regular_price IS NOT NULL AND sale_price < regular_price));

ALTER TABLE f360.product_colors ADD COLUMN code text;

-- Code builder: uppercase, accents removed, non-alphanumerics → '-'.  "Azul marino" → AZUL-MARINO
CREATE FUNCTION f360.code_from(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT upper(trim(both '-' from regexp_replace(translate(p,
    'áàäâãéèëêíìïîóòöôõúùüûñçÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ',
    'aaaaaeeeeiiiiooooouuuuncAAAAAEEEEIIIIOOOOOUUUUNC'), '[^A-Za-z0-9]+', '-', 'g')))
$$;

-- Backfill codes for any existing rows, then enforce.
UPDATE f360.products SET code = f360.code_from(name) || CASE WHEN rn > 1 THEN '-' || rn ELSE '' END
  FROM (SELECT id AS pid, row_number() OVER (PARTITION BY f360.code_from(name) ORDER BY created_at) AS rn FROM f360.products) x
  WHERE x.pid = f360.products.id;
UPDATE f360.product_colors SET code = f360.code_from(name) || CASE WHEN rn > 1 THEN '-' || rn ELSE '' END
  FROM (SELECT id AS cid, row_number() OVER (PARTITION BY product_id, f360.code_from(name) ORDER BY sort, created_at) AS rn FROM f360.product_colors) x
  WHERE x.cid = f360.product_colors.id;
ALTER TABLE f360.products ALTER COLUMN code SET NOT NULL, ADD CONSTRAINT products_code_key UNIQUE (code),
  ADD CONSTRAINT products_code_format CHECK (code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$');
ALTER TABLE f360.product_colors ALTER COLUMN code SET NOT NULL, ADD CONSTRAINT product_colors_code_key UNIQUE (product_id, code),
  ADD CONSTRAINT product_colors_code_format CHECK (code ~ '^[A-Z0-9]+(-[A-Z0-9]+)*$');

-- SKU for a variant (DW9). Size keeps its label (e.g. 37, 36.5).
CREATE FUNCTION f360.variant_sku(p_product_code text, p_color_code text, p_size text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT 'F360-' || p_product_code || '-' || p_color_code || '-' || upper(regexp_replace(p_size, '\s+', '', 'g')) $$;

CREATE FUNCTION f360.refresh_skus(p_product_id uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE f360.product_variants v SET sku = f360.variant_sku(p.code, c.code, v.size_label)
  FROM f360.products p, f360.product_colors c
  WHERE v.product_id = p_product_id AND p.id = v.product_id AND c.id = v.color_id
    AND v.sku IS DISTINCT FROM f360.variant_sku(p.code, c.code, v.size_label)
$$;
SELECT f360.refresh_skus(id) FROM f360.products;

-- Immutability once codes are locked (first publish, P2.2).
CREATE FUNCTION f360.guard_locked_codes() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE locked timestamptz;
BEGIN
  IF TG_TABLE_NAME = 'products' THEN
    IF OLD.codes_locked_at IS NOT NULL AND (NEW.code IS DISTINCT FROM OLD.code OR NEW.codes_locked_at IS DISTINCT FROM OLD.codes_locked_at) THEN
      RAISE EXCEPTION 'El código del producto ya se usó para publicar y no puede cambiar.' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME = 'product_colors' THEN
    SELECT codes_locked_at INTO locked FROM f360.products WHERE id = NEW.product_id;
    IF locked IS NOT NULL AND NEW.code IS DISTINCT FROM OLD.code THEN
      RAISE EXCEPTION 'El código del color ya se usó para publicar y no puede cambiar.' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF TG_TABLE_NAME = 'product_variants' THEN
    SELECT codes_locked_at INTO locked FROM f360.products WHERE id = NEW.product_id;
    IF locked IS NOT NULL AND OLD.sku IS NOT NULL AND NEW.sku IS DISTINCT FROM OLD.sku THEN
      RAISE EXCEPTION 'El SKU ya se usó para publicar y no puede cambiar.' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER products_locked_codes BEFORE UPDATE ON f360.products FOR EACH ROW EXECUTE FUNCTION f360.guard_locked_codes();
CREATE TRIGGER product_colors_locked_codes BEFORE UPDATE ON f360.product_colors FOR EACH ROW EXECUTE FUNCTION f360.guard_locked_codes();
CREATE TRIGGER product_variants_locked_sku BEFORE UPDATE ON f360.product_variants FOR EACH ROW EXECUTE FUNCTION f360.guard_locked_codes();

-- ── Photos per color ───────────────────────────────────────────────────────
CREATE TABLE f360.product_media (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id    uuid NOT NULL REFERENCES f360.products(id) ON DELETE RESTRICT,
  color_id      uuid REFERENCES f360.product_colors(id) ON DELETE RESTRICT,
  storage_path  text NOT NULL CHECK (storage_path LIKE 'f360/%'),
  sort          integer NOT NULL DEFAULT 0,
  alt           text,
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX product_media_color_idx ON f360.product_media (color_id, sort);
CREATE INDEX product_media_product_idx ON f360.product_media (product_id, sort);

CREATE FUNCTION f360.color_primary_image(p_color_id uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT m.storage_path FROM f360.product_media m WHERE m.color_id = p_color_id ORDER BY m.sort, m.created_at LIMIT 1),
    (SELECT c.image_path FROM f360.product_colors c WHERE c.id = p_color_id))
$$;
CREATE FUNCTION f360.product_primary_image(p_product_id uuid) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT m.storage_path FROM f360.product_media m JOIN f360.product_colors c ON c.id = m.color_id
       WHERE m.product_id = p_product_id ORDER BY c.sort, c.created_at, m.sort, m.created_at LIMIT 1),
    (SELECT m.storage_path FROM f360.product_media m WHERE m.product_id = p_product_id AND m.color_id IS NULL ORDER BY m.sort LIMIT 1),
    (SELECT p.image_path FROM f360.products p WHERE p.id = p_product_id))
$$;

-- Readiness for the online store (P2.2 will require ready = true to sync).
CREATE FUNCTION f360.product_readiness(p_product_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object('ready', cardinality(missing) = 0, 'missing', to_jsonb(missing)) FROM (
    SELECT array_remove(ARRAY[
      CASE WHEN p.regular_price IS NULL THEN 'precio' END,
      CASE WHEN p.category_key IS NULL THEN 'categoria' END,
      CASE WHEN coalesce(btrim(p.description), '') = '' THEN 'descripcion' END,
      CASE WHEN NOT EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id) THEN 'color' END,
      CASE WHEN NOT EXISTS (SELECT 1 FROM f360.product_sizes s WHERE s.product_id = p.id) THEN 'talla' END,
      CASE WHEN EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id
                        AND NOT EXISTS (SELECT 1 FROM f360.product_media m WHERE m.color_id = c.id)) THEN 'fotos' END
    ], NULL) AS missing
    FROM f360.products p WHERE p.id = p_product_id) x
$$;

-- The location whose stock is exposed online in V1 (authoritative warehouse = Bodega CDMX).
CREATE FUNCTION f360.online_location() RETURNS f360.locations LANGUAGE sql STABLE AS $$
  SELECT * FROM f360.locations WHERE status = 'active' AND is_authoritative AND type IN ('warehouse', 'receiving')
  ORDER BY sort, created_at LIMIT 1
$$;

-- Unique code helper (product or color).
CREATE FUNCTION f360.next_code(p_base text, p_taken text[]) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE c text := nullif(p_base, ''); i int := 2;
BEGIN
  IF c IS NULL THEN c := 'X'; END IF;
  WHILE c = ANY (p_taken) LOOP c := p_base || '-' || i; i := i + 1; END LOOP;
  RETURN c;
END $$;

-- ── Redefined reads (now with codes, SKUs, media, commercial info, readiness) ──
CREATE OR REPLACE FUNCTION f360.event_json(p_event_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT jsonb_build_object(
    'id', e.id, 'type', e.event_type, 'actor_name', e.actor_name, 'note', e.note,
    'occurred_at', e.occurred_at,
    'total_pairs', (SELECT coalesce(sum(m.quantity), 0) FROM f360.inventory_movements m WHERE m.event_id = e.id),
    'lines', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'product_id', p.id, 'product_name', p.name, 'product_image', coalesce(f360.color_primary_image(c.id), f360.product_primary_image(p.id)),
        'color', c.name, 'color_hex', c.hex, 'size', v.size_label, 'sku', v.sku, 'quantity', m.quantity,
        'from_location', lf.name, 'to_location', lt.name)
        ORDER BY p.name, c.sort, ps.sort), '[]'::jsonb)
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

CREATE OR REPLACE FUNCTION public.f360_list_products(p_query text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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
END $$;

CREATE OR REPLACE FUNCTION public.f360_get_product(p_product_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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
END $$;

CREATE OR REPLACE FUNCTION public.f360_inventory_by_location(p_location_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
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
END $$;

-- ── Writes ─────────────────────────────────────────────────────────────────
-- Create: same signature as V1 (backwards compatible); now assigns codes and SKUs.
CREATE OR REPLACE FUNCTION public.f360_create_product(p_name text, p_sizes text[], p_colors jsonb, p_category text DEFAULT NULL, p_image_path text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_id uuid; v_slug text; v_code text; v_color jsonb; v_color_id uuid; v_i int := 0; v_size text; v_ccode text; v_taken text[] := '{}';
BEGIN
  r := f360.require_role('operator');
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'Escribe el nombre del producto.'; END IF;
  IF p_sizes IS NULL OR cardinality(p_sizes) = 0 THEN RAISE EXCEPTION 'Elige al menos una talla.'; END IF;
  IF p_colors IS NULL OR jsonb_array_length(p_colors) = 0 THEN RAISE EXCEPTION 'Agrega al menos un color.'; END IF;
  v_slug := f360.slugify(p_name);
  IF EXISTS (SELECT 1 FROM f360.products WHERE slug = v_slug) THEN
    RAISE EXCEPTION 'Ya existe un producto llamado "%".', btrim(p_name);
  END IF;
  v_code := f360.next_code(f360.code_from(p_name), ARRAY(SELECT code FROM f360.products));
  INSERT INTO f360.products (name, slug, code, category, image_path, created_by)
    VALUES (btrim(p_name), v_slug, v_code, nullif(btrim(p_category), ''), p_image_path, auth.uid()) RETURNING id INTO v_id;
  FOREACH v_size IN ARRAY p_sizes LOOP
    v_i := v_i + 1;
    INSERT INTO f360.product_sizes (product_id, label, sort) VALUES (v_id, btrim(v_size), v_i);
  END LOOP;
  v_i := 0;
  FOR v_color IN SELECT * FROM jsonb_array_elements(p_colors) LOOP
    v_i := v_i + 1;
    IF coalesce(btrim(v_color->>'name'), '') = '' THEN RAISE EXCEPTION 'Cada color necesita un nombre.'; END IF;
    v_ccode := f360.next_code(f360.code_from(v_color->>'name'), v_taken);
    v_taken := v_taken || v_ccode;
    INSERT INTO f360.product_colors (product_id, name, code, hex, image_path, sort)
      VALUES (v_id, btrim(v_color->>'name'), v_ccode, nullif(v_color->>'hex', ''), nullif(v_color->>'image_path', ''), v_i)
      RETURNING id INTO v_color_id;
    INSERT INTO f360.product_variants (product_id, color_id, size_label)
      SELECT v_id, v_color_id, label FROM f360.product_sizes WHERE product_id = v_id;
  END LOOP;
  PERFORM f360.refresh_skus(v_id);
  RETURN public.f360_get_product(v_id);
END $$;

-- Add a color to an existing model: one variant per existing size, SKUs generated.
CREATE FUNCTION public.f360_add_color(p_product_id uuid, p_name text, p_hex text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_color uuid; v_code text;
BEGIN
  r := f360.require_role('operator');
  IF NOT EXISTS (SELECT 1 FROM f360.products WHERE id = p_product_id) THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF coalesce(btrim(p_name), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre del color.'; END IF;
  IF EXISTS (SELECT 1 FROM f360.product_colors WHERE product_id = p_product_id AND lower(name) = lower(btrim(p_name))) THEN
    RAISE EXCEPTION 'Este producto ya tiene el color "%".', btrim(p_name);
  END IF;
  v_code := f360.next_code(f360.code_from(p_name), ARRAY(SELECT code FROM f360.product_colors WHERE product_id = p_product_id));
  INSERT INTO f360.product_colors (product_id, name, code, hex, sort)
    VALUES (p_product_id, btrim(p_name), v_code, nullif(p_hex, ''),
            (SELECT coalesce(max(sort), 0) + 1 FROM f360.product_colors WHERE product_id = p_product_id))
    RETURNING id INTO v_color;
  INSERT INTO f360.product_variants (product_id, color_id, size_label)
    SELECT p_product_id, v_color, label FROM f360.product_sizes WHERE product_id = p_product_id;
  PERFORM f360.refresh_skus(p_product_id);
  UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  RETURN public.f360_get_product(p_product_id);
END $$;

-- Commercial info. Only the keys present in p_fields are changed.
CREATE FUNCTION public.f360_update_product(p_product_id uuid, p_fields jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; p f360.products;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO p FROM f360.products WHERE id = p_product_id;
  IF p.id IS NULL THEN RAISE EXCEPTION 'Producto no encontrado.'; END IF;
  IF p_fields ? 'name' THEN
    IF coalesce(btrim(p_fields->>'name'), '') = '' THEN RAISE EXCEPTION 'Escribe el nombre del producto.'; END IF;
    IF EXISTS (SELECT 1 FROM f360.products WHERE slug = f360.slugify(p_fields->>'name') AND id <> p.id) THEN
      RAISE EXCEPTION 'Ya existe un producto llamado "%".', btrim(p_fields->>'name');
    END IF;
    p.name := btrim(p_fields->>'name'); p.slug := f360.slugify(p.name);   -- code/SKUs do NOT change (DW9)
  END IF;
  IF p_fields ? 'description' THEN p.description := nullif(btrim(p_fields->>'description'), ''); END IF;
  IF p_fields ? 'short_description' THEN p.short_description := nullif(btrim(p_fields->>'short_description'), ''); END IF;
  IF p_fields ? 'category_key' THEN
    p.category_key := nullif(p_fields->>'category_key', '');
    IF p.category_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM f360.categories WHERE key = p.category_key) THEN
      RAISE EXCEPTION 'Elige una categoría válida.';
    END IF;
  END IF;
  IF p_fields ? 'regular_price' THEN p.regular_price := nullif(p_fields->>'regular_price', '')::numeric; END IF;
  IF p_fields ? 'sale_price' THEN p.sale_price := nullif(p_fields->>'sale_price', '')::numeric; END IF;
  IF p.regular_price IS NOT NULL AND p.regular_price <= 0 THEN RAISE EXCEPTION 'El precio debe ser mayor a cero.'; END IF;
  IF p.sale_price IS NOT NULL AND (p.regular_price IS NULL OR p.sale_price >= p.regular_price) THEN
    RAISE EXCEPTION 'El precio de oferta debe ser menor que el precio normal.';
  END IF;
  UPDATE f360.products SET name = p.name, slug = p.slug, description = p.description, short_description = p.short_description,
    category_key = p.category_key, regular_price = p.regular_price, sale_price = p.sale_price, updated_at = now()
    WHERE id = p.id;
  RETURN public.f360_get_product(p.id);
END $$;

-- Photos (uploaded to Storage first by the browser under product-images/f360/…).
CREATE FUNCTION public.f360_add_media(p_product_id uuid, p_color_id uuid, p_paths text[]) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_path text; v_sort int;
BEGIN
  r := f360.require_role('operator');
  IF NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE id = p_color_id AND product_id = p_product_id) THEN
    RAISE EXCEPTION 'Color no encontrado.';
  END IF;
  IF p_paths IS NULL OR cardinality(p_paths) = 0 THEN RAISE EXCEPTION 'No hay fotos.'; END IF;
  SELECT coalesce(max(sort), 0) INTO v_sort FROM f360.product_media WHERE color_id = p_color_id;
  FOREACH v_path IN ARRAY p_paths LOOP
    IF v_path !~ '^f360/[A-Za-z0-9._/-]+$' THEN RAISE EXCEPTION 'Ruta de foto no válida.'; END IF;
    v_sort := v_sort + 1;
    INSERT INTO f360.product_media (product_id, color_id, storage_path, sort, created_by) VALUES (p_product_id, p_color_id, v_path, v_sort, auth.uid());
  END LOOP;
  UPDATE f360.products SET updated_at = now() WHERE id = p_product_id;
  RETURN public.f360_get_product(p_product_id);
END $$;

CREATE FUNCTION public.f360_remove_media(p_media_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; v_product uuid;
BEGIN
  r := f360.require_role('operator');
  DELETE FROM f360.product_media WHERE id = p_media_id RETURNING product_id INTO v_product;
  IF v_product IS NULL THEN RAISE EXCEPTION 'Foto no encontrada.'; END IF;
  UPDATE f360.products SET updated_at = now() WHERE id = v_product;
  RETURN public.f360_get_product(v_product);
END $$;

-- Makes a photo the first (main) one of its color.
CREATE FUNCTION public.f360_set_primary_media(p_media_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; m f360.product_media;
BEGIN
  r := f360.require_role('operator');
  SELECT * INTO m FROM f360.product_media WHERE id = p_media_id;
  IF m.id IS NULL THEN RAISE EXCEPTION 'Foto no encontrada.'; END IF;
  UPDATE f360.product_media SET sort = (SELECT coalesce(min(sort), 0) - 1 FROM f360.product_media WHERE color_id = m.color_id) WHERE id = m.id;
  RETURN public.f360_get_product(m.product_id);
END $$;

CREATE FUNCTION public.f360_list_categories() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('key', key, 'name', name) ORDER BY sort), '[]'::jsonb) FROM f360.categories);
END $$;

-- ── Grants (explicit; authenticated only, role checked inside) ─────────────
REVOKE ALL ON ALL TABLES IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA f360 TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.f360_add_color(uuid, text, text), public.f360_update_product(uuid, jsonb),
  public.f360_add_media(uuid, uuid, text[]), public.f360_remove_media(uuid), public.f360_set_primary_media(uuid),
  public.f360_list_categories() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_add_color(uuid, text, text), public.f360_update_product(uuid, jsonb),
  public.f360_add_media(uuid, uuid, text[]), public.f360_remove_media(uuid), public.f360_set_primary_media(uuid),
  public.f360_list_categories() TO authenticated, service_role;
