-- Catalog tidy-up: remove a colour, product list segmentation fields — database tests (STAGING). ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'seller', 'ZZ Vendedora', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'seller' RETURNING auth_user_id AS seller \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.seller', :'seller', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; sel uuid := current_setting('t.seller')::uuid;
  bodega uuid := (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX');
  r jsonb; pid uuid; negro uuid; rojo uuid; nude uuid; err text; lp uuid;
BEGIN
  r := pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Colores', ARRAY['36','37'], '[{"name":"Negro"},{"name":"Rojo"},{"name":"Nude"}]'::jsonb, 'Ballerinas')$q$);
  pid := (r->>'id')::uuid;
  UPDATE f360.products SET category_key = 'ballerinas' WHERE id = pid;
  SELECT id INTO negro FROM f360.product_colors WHERE product_id = pid AND name = 'Negro';
  SELECT id INTO rojo FROM f360.product_colors WHERE product_id = pid AND name = 'Rojo';
  SELECT id INTO nude FROM f360.product_colors WHERE product_id = pid AND name = 'Nude';

  r := pg_temp.as(car, $q$SELECT public.f360_list_products('ZZ Colores')$q$);
  PERFORM pg_temp.ok(r->0->>'category_key' = 'ballerinas' AND (r->0->>'from_store')::boolean = false, 'product list carries category_key and from_store', r::text);

  r := pg_temp.as(sel, format($q$SELECT public.f360_remove_color(%L, 'x')$q$, rojo));
  PERFORM pg_temp.ok(r ? 'error', 'a seller cannot remove a colour', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, ' ')$q$, rojo));
  PERFORM pg_temp.ok(r->>'error' = 'Escribe el motivo.', 'a reason is required', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, 'Se creó por error')$q$, rojo));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE id = rojo) AND NOT EXISTS (SELECT 1 FROM f360.product_variants WHERE color_id = rojo)
    AND (SELECT count(*) FROM f360.product_colors WHERE product_id = pid) = 2
    AND EXISTS (SELECT 1 FROM f360.catalog_changes WHERE product_id = pid AND what = 'remove_color' AND detail->>'color' = 'Rojo' AND actor_name = 'Carolina'),
    'an unused colour is removed with its sizes; logged with who and why', r::text);

  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, bodega,
    (SELECT id FROM f360.product_variants WHERE color_id = negro AND size_label = '36')));
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, 'x x x')$q$, negro));
  PERFORM pg_temp.ok(r->>'error' LIKE '%pares en inventario%' AND r->>'error' LIKE '%historial de inventario%', 'a colour with pairs / history cannot be removed', r::text);

  -- adopted from the store: blocked until its homologation is reopened
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_cat', 'ZZ cat', 'https://zz.invalid', bodega, true);
  PERFORM public.f360_legacy_load_snapshot('zz_cat', '[{"woo_variation_id":990501,"woo_product_id":9905,"woo_product_name":"ZZ Tienda negro","woo_size":"36"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_cat', ARRAY[990501], NULL, 'ZZ De la tienda', 'botas', 'Negro', NULL)$q$);
  lp := (r->>'product_id')::uuid;
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_add_color(%L, 'Café', NULL)$q$, lp));
  r := pg_temp.as(car, format($q$SELECT public.f360_color_remove_state(%L)$q$, (SELECT id FROM f360.product_colors WHERE product_id = lp AND name = 'Negro')));
  PERFORM pg_temp.ok((r->'blockers')::text LIKE '%Homologación%', 'state tells why a store colour cannot be removed', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, 'x x x')$q$, (SELECT id FROM f360.product_colors WHERE product_id = lp AND name = 'Negro')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%reabre esa homologación%', 'a colour confirmed from the store cannot be removed (reopen first)', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_list_products('ZZ De la tienda')$q$));
  PERFORM pg_temp.ok((r->0->>'from_store')::boolean, 'a model adopted from the store is flagged from_store', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, 'Lo agregué por error')$q$, (SELECT id FROM f360.product_colors WHERE product_id = lp AND name = 'Café')));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE product_id = lp AND name = 'Café'), 'an extra colour added by hand to a store model can be removed', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_remove_color(%L, 'x x x')$q$, nude));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.product_colors WHERE id = nude), 'second unused colour removed', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_color_remove_state(%L)$q$, negro));
  PERFORM pg_temp.ok((r->'blockers')::text LIKE '%único color%', 'the last colour of a model is never removed (archive the model instead)', r::text);
  -- rename a colour: name only, SKU unchanged
  r := pg_temp.as(car, format($q$SELECT public.f360_rename_color(%L, 'Negro charol')$q$, negro));
  PERFORM pg_temp.ok((SELECT name FROM f360.product_colors WHERE id = negro) = 'Negro charol'
    AND (SELECT sku FROM f360.product_variants WHERE color_id = negro AND size_label = '36') = 'F360-ZZ-COLORES-NEGRO-36'
    AND EXISTS (SELECT 1 FROM f360.catalog_changes WHERE product_id = pid AND what = 'rename_color' AND detail->>'from' = 'Negro'),
    'a colour is renamed; its SKU stays the same; logged', r::text);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_add_color(%L, 'Vino', NULL)$q$, pid));
  r := pg_temp.as(car, format($q$SELECT public.f360_rename_color(%L, 'vino')$q$, negro));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya tiene un color%', 'two colours of a model cannot share a name', r::text);
  r := pg_temp.as(sel, format($q$SELECT public.f360_rename_color(%L, 'X')$q$, negro));
  PERFORM pg_temp.ok(r ? 'error', 'a seller cannot rename a colour', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_channels_available()$q$);
  PERFORM pg_temp.ok(jsonb_typeof(r) = 'array' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x JOIN f360.locations l ON l.legacy_channel_id = (x->>'id')::uuid),
    'available legacy stores = not yet linked to a location', r::text);
  BEGIN UPDATE f360.catalog_changes SET reason = 'x'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%', 'catalog history is append-only', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
