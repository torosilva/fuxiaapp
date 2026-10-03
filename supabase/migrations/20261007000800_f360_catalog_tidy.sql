-- Fuxia 360 — catalog tidy-up asked by Mario/Carolina 2026-10-02 (STAGING). Additive.
--   1. f360_list_products also returns category_key and from_store (model adopted from the store's homologation),
--      so the Products screen can be segmented by category and show "En la tienda" instead of "Borrador".
--   2. f360_remove_color: a person removes a colour from a model. Only when that colour has no history that matters:
--      no pairs, no inventory movement, no transfer, no store link, not confirmed in a homologation, not in an opening
--      count or a store cutover. Its photos' rows go with it (files stay in storage). Logged in f360.catalog_changes.
-- Rollback: supabase/rollbacks/20261007000800_f360_catalog_tidy.down.sql

CREATE TABLE f360.catalog_changes (
  id                  bigserial PRIMARY KEY,
  product_id          uuid NOT NULL,
  what                text NOT NULL,
  detail              jsonb,
  reason              text,
  actor_auth_user_id  uuid,
  actor_name          text NOT NULL,
  at                  timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION f360.catalog_changes_append_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'El historial del catálogo no se puede modificar.';
END $$;
CREATE TRIGGER catalog_changes_append_only BEFORE UPDATE OR DELETE ON f360.catalog_changes FOR EACH ROW EXECUTE FUNCTION f360.catalog_changes_append_only();

CREATE FUNCTION f360.color_remove_blockers(p_color_id uuid) RETURNS text[] LANGUAGE sql STABLE AS $$
  WITH v AS (SELECT id FROM f360.product_variants WHERE color_id = p_color_id)
  SELECT array_remove(ARRAY[
    (SELECT format('Tiene %s pares en inventario', sum(on_hand)) FROM f360.inventory_balances WHERE variant_id IN (SELECT id FROM v) HAVING sum(on_hand) > 0),
    CASE WHEN EXISTS (SELECT 1 FROM f360.inventory_movements WHERE variant_id IN (SELECT id FROM v)) THEN 'Tiene historial de inventario (recepciones, ventas o movimientos)' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.transfer_lines WHERE variant_id IN (SELECT id FROM v)) THEN 'Aparece en transferencias' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE variant_id IN (SELECT id FROM v)) THEN 'Está ligado a la tienda en línea' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.legacy_woo_map WHERE confirmed_variant_id IN (SELECT id FROM v))
      THEN 'Viene de la tienda (confirmado en Homologación): reabre esa homologación primero' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.opening_count_lines WHERE variant_id IN (SELECT id FROM v)) THEN 'Está en un conteo de apertura' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.cutover_counts WHERE variant_id IN (SELECT id FROM v))
           OR EXISTS (SELECT 1 FROM f360.legacy_inventory_map WHERE proposed_variant_id IN (SELECT id FROM v) OR confirmed_variant_id IN (SELECT id FROM v))
      THEN 'Está en el corte de una tienda' END,
    CASE WHEN EXISTS (SELECT 1 FROM public.offline_sale_items WHERE variant_id IN (SELECT id FROM v)) THEN 'Tiene ventas en tienda' END,
    CASE WHEN EXISTS (SELECT 1 FROM f360.woo_order_lines WHERE variant_id IN (SELECT id FROM v)) THEN 'Tiene pedidos en línea' END,
    CASE WHEN (SELECT count(*) FROM f360.product_colors WHERE product_id = (SELECT product_id FROM f360.product_colors WHERE id = p_color_id)) <= 1
      THEN 'Es el único color del modelo (archiva el modelo en su lugar)' END
  ], NULL)
$$;

CREATE FUNCTION public.f360_color_remove_state(p_color_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('operator');
  IF NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE id = p_color_id) THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  RETURN jsonb_build_object('blockers', to_jsonb(f360.color_remove_blockers(p_color_id)));
END $$;

CREATE FUNCTION public.f360_remove_color(p_color_id uuid, p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE r f360.user_roles; c f360.product_colors; b text[]; n_var int; n_media int;
BEGIN
  r := f360.require_role('operator');
  IF coalesce(length(btrim(p_reason)), 0) < 3 THEN RAISE EXCEPTION 'Escribe el motivo.'; END IF;
  SELECT * INTO c FROM f360.product_colors WHERE id = p_color_id FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'Color no encontrado.'; END IF;
  b := f360.color_remove_blockers(c.id);
  IF cardinality(b) > 0 THEN RAISE EXCEPTION 'No se puede quitar %: %.', c.name, array_to_string(b, '; '); END IF;
  -- unconfirmed homologation proposals that pointed at this model keep working (they reference the model, not the colour)
  DELETE FROM f360.woo_media_links WHERE media_id IN (SELECT id FROM f360.product_media WHERE color_id = c.id);
  DELETE FROM f360.product_media WHERE color_id = c.id;
  GET DIAGNOSTICS n_media = ROW_COUNT;
  DELETE FROM f360.stock_sync_queue WHERE variant_id IN (SELECT id FROM f360.product_variants WHERE color_id = c.id);
  DELETE FROM f360.inventory_balances WHERE variant_id IN (SELECT id FROM f360.product_variants WHERE color_id = c.id) AND on_hand = 0;
  DELETE FROM f360.product_variants WHERE color_id = c.id;
  GET DIAGNOSTICS n_var = ROW_COUNT;
  DELETE FROM f360.product_colors WHERE id = c.id;
  UPDATE f360.products SET updated_at = now() WHERE id = c.product_id;
  INSERT INTO f360.catalog_changes (product_id, what, detail, reason, actor_auth_user_id, actor_name)
    VALUES (c.product_id, 'remove_color', jsonb_build_object('color', c.name, 'code', c.code, 'variants', n_var, 'photos', n_media), btrim(p_reason), auth.uid(), r.display_name);
  RETURN public.f360_get_product(c.product_id);
END $$;

-- Same list as before (transfers migration) + category_key + from_store.
CREATE OR REPLACE FUNCTION public.f360_list_products(p_query text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
BEGIN
  PERFORM f360.require_role('viewer');
  RETURN (SELECT coalesce(jsonb_agg(x ORDER BY (x->>'last_activity') DESC NULLS LAST, x->>'name'), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
      'id', p.id, 'name', p.name, 'code', p.code, 'category', cat.name, 'category_key', p.category_key, 'image_path', f360.product_primary_image(p.id),
      'regular_price', p.regular_price, 'sale_price', p.sale_price,
      'ready', (f360.product_readiness(p.id)->>'ready')::boolean,
      'from_store', EXISTS (SELECT 1 FROM f360.legacy_woo_map m JOIN f360.product_variants v ON v.id = m.confirmed_variant_id WHERE v.product_id = p.id),
      'colors', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', c.name, 'hex', c.hex) ORDER BY c.sort, c.name), '[]'::jsonb)
                 FROM f360.product_colors c WHERE c.product_id = p.id),
      'pairs', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id <> f360.transit_location()),
      'in_transit', (SELECT coalesce(sum(b.on_hand), 0) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id AND b.location_id = f360.transit_location()),
      'last_activity', greatest(p.updated_at, (SELECT max(b.updated_at) FROM f360.inventory_balances b
                JOIN f360.product_variants v ON v.id = b.variant_id WHERE v.product_id = p.id))) AS x
    FROM f360.products p LEFT JOIN f360.categories cat ON cat.key = p.category_key
    WHERE p.status = 'active'
      AND (p_query IS NULL OR btrim(p_query) = '' OR p.name ILIKE '%' || btrim(p_query) || '%'
           OR EXISTS (SELECT 1 FROM f360.product_colors c WHERE c.product_id = p.id AND c.name ILIKE '%' || btrim(p_query) || '%'))
  ) s);
END $$;

REVOKE ALL ON f360.catalog_changes FROM PUBLIC, anon, authenticated;
GRANT ALL ON f360.catalog_changes TO service_role;
GRANT USAGE, SELECT ON SEQUENCE f360.catalog_changes_id_seq TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA f360 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.f360_color_remove_state(uuid), public.f360_remove_color(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.f360_color_remove_state(uuid), public.f360_remove_color(uuid, text) TO authenticated, service_role;
