-- Fuxia 360 P2.1 (product master) — database tests (STAGING). One transaction, ROLLED BACK.
-- Output: one row per check: PASS/FAIL | name | detail
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;

CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN '{"role":"anon"}' ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true) \gset t_
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c1', 'viewer', 'Viewer de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'viewer', display_name = 'Viewer de prueba', granted_by = 'test (rolled back)';

-- 1–4. Owner creates the model: codes, SKUs, Colombian sizes, readiness starts incomplete
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; p jsonb; nude jsonb; n_var int;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Macarena Prueba', ARRAY['35','36','37','38','39','40'],
        '[{"name":"Nude","hex":"#D8B9A0"},{"name":"Azul marino","hex":"#1F2A44"}]'::jsonb);
  INSERT INTO t_ids VALUES ('p', (p->>'id')::uuid);
  nude := (SELECT c FROM jsonb_array_elements(p->'colors') c WHERE c->>'name' = 'Nude');
  n_var := (SELECT sum(jsonb_array_length(c->'variants')) FROM jsonb_array_elements(p->'colors') c);
  PERFORM pg_temp.ok(p->>'code' = 'ZZ-MACARENA-PRUEBA' AND nude->>'code' = 'NUDE'
    AND (SELECT c->>'code' FROM jsonb_array_elements(p->'colors') c WHERE c->>'name' = 'Azul marino') = 'AZUL-MARINO',
    'product + color codes generated', (p->>'code') || ' / ' || (nude->>'code'));
  PERFORM pg_temp.ok(n_var = 12 AND p->'sizes' = '["35","36","37","38","39","40"]'::jsonb, '2 colors × 6 Colombian sizes = 12 variants', n_var::text);
  PERFORM pg_temp.ok((SELECT v->>'sku' FROM jsonb_array_elements(nude->'variants') v WHERE v->>'size' = '37') = 'F360-ZZ-MACARENA-PRUEBA-NUDE-37',
    'SKU format F360-{PRODUCT}-{COLOR}-{SIZE}', (SELECT v->>'sku' FROM jsonb_array_elements(nude->'variants') v WHERE v->>'size' = '37'));
  PERFORM pg_temp.ok(NOT (p->'readiness'->>'ready')::boolean AND p->'readiness'->'missing' ?& ARRAY['precio','categoria','descripcion','fotos'],
    'new product is a draft (missing precio/categoria/descripcion/fotos)', p->'readiness'->>'missing');
  PERFORM pg_temp.ok(p->'online_location'->>'name' = 'Bodega CDMX', 'online location = Bodega CDMX', p->'online_location'->>'name');
  RESET ROLE;
END $$;

-- 5–6. Add a color later: variants for every size, no recreation; duplicate color rejected
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); p jsonb; rojo jsonb; err text;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_add_color(pid, 'Rojo', '#9E2A2B');
  rojo := (SELECT c FROM jsonb_array_elements(p->'colors') c WHERE c->>'name' = 'Rojo');
  PERFORM pg_temp.ok(p->>'id' = pid::text AND jsonb_array_length(rojo->'variants') = 6
    AND (SELECT bool_and(v->>'sku' = 'F360-ZZ-MACARENA-PRUEBA-ROJO-' || (v->>'size')) FROM jsonb_array_elements(rojo->'variants') v),
    'add_color creates 6 variants + SKUs on the same model', jsonb_array_length(rojo->'variants')::text);
  BEGIN PERFORM public.f360_add_color(pid, ' rojo ', NULL); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'duplicate color rejected', err);
  RESET ROLE;
END $$;

-- 7–10. Price / category / description validation
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); p jsonb; err text;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_update_product(pid, '{"regular_price":2800,"sale_price":2800}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'sale price >= regular rejected', err);
  BEGIN PERFORM public.f360_update_product(pid, '{"regular_price":-5}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'non-positive price rejected', err);
  BEGIN PERFORM public.f360_update_product(pid, '{"category_key":"zapatos-inventados"}'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'unknown category rejected', err);
  p := public.f360_update_product(pid, '{"regular_price":2800,"sale_price":2400,"category_key":"ballerinas","description":"Ballerina en piel.","short_description":"Cómoda."}');
  PERFORM pg_temp.ok((p->>'regular_price')::numeric = 2800 AND (p->>'sale_price')::numeric = 2400 AND p->>'category' = 'Ballerinas'
    AND p->'readiness'->'missing' = '["fotos"]'::jsonb, 'valid update saved; only photos missing', p->'readiness'->>'missing');
  RESET ROLE;
END $$;

-- 11–18. Photos per color: P2.1b path guard (own folder, real object, no reuse), readiness, primary, remove
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); p jsonb; c jsonb; err text;
  other_color uuid; other_path text; m2 text; nude_id uuid;
BEGIN
  -- as table owner, before switching role: fixtures for real uploaded objects (rolled back)
  SELECT id INTO other_color FROM f360.product_colors WHERE product_id <> pid LIMIT 1;
  IF other_color IS NULL THEN other_color := gen_random_uuid(); END IF;
  INSERT INTO storage.objects (bucket_id, name)
    SELECT 'product-images', 'f360/ZZ-MACARENA-PRUEBA/' || c.code || '/' || f FROM f360.product_colors c, unnest(ARRAY['a.png','b.png']) f WHERE c.product_id = pid;
  INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', 'f360/OTRO-PRODUCTO/NUDE/robada.png');
  INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', 'f360/ZZ-MACARENA-PRUEBA/NUDE/sub/x.png');
  -- a photo already attached to ANOTHER product (if any exists in staging) — must not be attachable here
  SELECT storage_path INTO other_path FROM f360.product_media WHERE product_id <> pid LIMIT 1;
  PERFORM pg_temp.as_user(u, 'authenticated');
  c := (SELECT x FROM jsonb_array_elements(public.f360_get_product(pid)->'colors') x WHERE x->>'name' = 'Nude');
  nude_id := (c->>'id')::uuid;
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['../secret.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'photo path outside f360/ rejected', err);
  BEGIN PERFORM public.f360_add_media(pid, other_color, ARRAY['f360/x/y.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'photo for a color of another product rejected', err);
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['f360/OTRO-PRODUCTO/NUDE/robada.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: existing object in ANOTHER product folder rejected', err);
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['f360/ZZ-MACARENA-PRUEBA/NEGRO/a.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: path of another COLOR folder rejected', err);
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['f360/ZZ-MACARENA-PRUEBA/NUDE/sub/x.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: nested sub-path rejected', err);
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['f360/ZZ-MACARENA-PRUEBA/NUDE/nunca-subida.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: path that was never uploaded rejected', err);
  IF other_path IS NOT NULL THEN
    BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY[other_path]); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
    PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: photo attached to another product rejected', err);
  END IF;

  FOR c IN SELECT x FROM jsonb_array_elements(public.f360_get_product(pid)->'colors') x LOOP
    p := public.f360_add_media(pid, (c->>'id')::uuid, ARRAY['f360/ZZ-MACARENA-PRUEBA/' || (c->>'code') || '/a.png', 'f360/ZZ-MACARENA-PRUEBA/' || (c->>'code') || '/b.png']);
  END LOOP;
  PERFORM pg_temp.ok((p->'readiness'->>'ready')::boolean AND p->'image_path' IS NOT NULL, 'every color has photos → Listo para publicar', p->>'readiness');
  BEGIN PERFORM public.f360_add_media(pid, nude_id, ARRAY['f360/ZZ-MACARENA-PRUEBA/NUDE/a.png']); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'P2.1b: same photo cannot be attached twice', err);

  c := (SELECT x FROM jsonb_array_elements(p->'colors') x WHERE x->>'name' = 'Nude');
  m2 := c->'media'->1->>'id';
  p := public.f360_set_primary_media(m2::uuid);
  c := (SELECT x FROM jsonb_array_elements(p->'colors') x WHERE x->>'name' = 'Nude');
  PERFORM pg_temp.ok(c->'media'->0->>'id' = m2 AND c->>'image_path' LIKE '%/b.png', 'set primary photo reorders the color gallery', c->>'image_path');
  p := public.f360_remove_media(m2::uuid);
  p := public.f360_remove_media(((SELECT x FROM jsonb_array_elements(p->'colors') x WHERE x->>'name' = 'Nude')->'media'->0->>'id')::uuid);
  PERFORM pg_temp.ok(NOT (p->'readiness'->>'ready')::boolean AND p->'readiness'->'missing' = '["fotos"]'::jsonb, 'removing all photos of one color → draft again', p->'readiness'->>'missing');
  RESET ROLE;
END $$;

-- 15. Rename keeps code and SKUs (DW9)
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); p jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_update_product(pid, '{"name":"ZZ Macarena Clásica"}');
  RESET ROLE;
  PERFORM pg_temp.ok(p->>'name' = 'ZZ Macarena Clásica' AND p->>'code' = 'ZZ-MACARENA-PRUEBA'
    AND EXISTS (SELECT 1 FROM f360.product_variants WHERE product_id = pid AND sku = 'F360-ZZ-MACARENA-PRUEBA-NUDE-37'),
    'rename keeps product code and SKUs', p->>'code');
END $$;

-- 16–19. Locked codes are immutable (lock is set by P2.2 publish; simulated here)
DO $$
DECLARE pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); err text;
BEGIN
  UPDATE f360.products SET codes_locked_at = now() WHERE id = pid;
  BEGIN UPDATE f360.products SET code = 'OTRO' WHERE id = pid; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'locked product code cannot change', err);
  BEGIN UPDATE f360.products SET codes_locked_at = NULL WHERE id = pid; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'lock cannot be removed', err);
  BEGIN UPDATE f360.product_colors SET code = 'OTRO' WHERE product_id = pid AND code = 'NUDE'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'locked color code cannot change', err);
  BEGIN UPDATE f360.product_variants SET sku = 'X' WHERE product_id = pid AND sku = 'F360-ZZ-MACARENA-PRUEBA-NUDE-37'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'locked SKU cannot change', err);
END $$;

-- 20. A color added AFTER lock still gets its own new code + SKUs (existing ones untouched)
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); p jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_add_color(pid, 'Camel', '#B07A4A');
  RESET ROLE;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.product_variants WHERE product_id = pid AND sku = 'F360-ZZ-MACARENA-PRUEBA-CAMEL-40')
    AND EXISTS (SELECT 1 FROM f360.product_variants WHERE product_id = pid AND sku = 'F360-ZZ-MACARENA-PRUEBA-NUDE-37'),
    'new color after lock gets SKUs; locked SKUs untouched', (SELECT count(*)::text FROM f360.product_variants WHERE product_id = pid));
END $$;

-- 21. Code collision helper
SELECT pg_temp.ok(f360.next_code('MACARENA', ARRAY['MACARENA','MACARENA-2']) = 'MACARENA-3', 'code collision gets a suffix', f360.next_code('MACARENA', ARRAY['MACARENA','MACARENA-2']));

-- 22–25. Viewer and anon cannot write the product master
DO $$
DECLARE u uuid := current_setting('t.c1')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); cid uuid; err text;
BEGIN
  SELECT id INTO cid FROM f360.product_colors WHERE product_id = pid LIMIT 1;
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_update_product(pid, '{"regular_price":1}'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'viewer cannot change price', err);
  BEGIN PERFORM public.f360_add_color(pid, 'Verde', NULL); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'viewer cannot add colors', err);
  BEGIN PERFORM public.f360_add_media(pid, cid, ARRAY['f360/x.png']); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'viewer cannot add photos', err);
  RESET ROLE;
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_list_categories(); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot call P2.1 RPCs', err);
END $$;

-- 26. Helper functions in f360 are not executable by API roles
SELECT pg_temp.ok(NOT has_function_privilege('authenticated', 'f360.refresh_skus(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('anon', 'f360.product_readiness(uuid)', 'EXECUTE'), 'f360 helpers not executable by API roles', '');

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
