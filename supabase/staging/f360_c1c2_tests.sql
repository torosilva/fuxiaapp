-- Fuxia 360 Track C · C1 (roles/locations/assignments) + C2 (legacy catalog mapping) — database tests (STAGING).
-- One transaction, ROLLED BACK. Fixture channels/inventory are fictitious and exist only inside this transaction.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon;
-- identity only (auth.uid() from JWT claims) while keeping the DB role: to test INTERNAL f360 functions
CREATE FUNCTION pg_temp.claims(p_uid uuid) RETURNS void LANGUAGE sql AS
$$ SELECT set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true) $$;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS c3 FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
SELECT set_config('t.mario', :'mario', true), set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.c3', :'c3', true) \gset t_

-- Fixture: two fictitious legacy channels (store A, store B) + one F360 model to map against
DO $$
DECLARE chA uuid; chB uuid; p jsonb; u uuid := current_setting('t.carolina')::uuid;
BEGIN
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ Tienda Prueba A', 'store', true) RETURNING id INTO chA;
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ Tienda Prueba B', 'store', true) RETURNING id INTO chB;
  INSERT INTO t_ids VALUES ('chA', chA), ('chB', chB);
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Mapeo Prueba', ARRAY['36','37'], '[{"name":"Negro"},{"name":"Nude"}]'::jsonb);
  RESET ROLE;
  INSERT INTO t_ids VALUES ('p', (p->>'id')::uuid);
  INSERT INTO t_ids SELECT 'var', id FROM f360.product_variants WHERE product_id = (p->>'id')::uuid LIMIT 1;
  INSERT INTO t_ids SELECT 'bodega', id FROM f360.locations WHERE name = 'Bodega CDMX';
  -- legacy rows: exact SKU, name+color+size ("Talla 37"), unmatched with units, unmatched without units
  INSERT INTO public.channel_inventory (channel_id, product_name, sku, size, color, price, stock, sold) VALUES
    (chA, 'Cualquier nombre', 'f360-zz-mapeo-prueba-negro-36', '36', 'negro', 2800, 3, 1),
    (chA, 'ZZ Mapeo  Prueba', NULL, 'Talla 37', 'NUDE', 2800, 2, 0),
    (chA, 'Slingback punta afilada', 'SUE-X-1', '38', 'Taupe', 2500, 4, 1),
    (chA, 'Modelo agotado viejo', NULL, '35', 'Vino', 2500, 2, 2);
END $$;

-- ═════ C1 ═════
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; lA jsonb; lB jsonb; lN jsonb; err text; bodega uuid;
BEGIN
  SELECT id INTO bodega FROM f360.locations WHERE name = 'Bodega CDMX';
  PERFORM pg_temp.ok((SELECT ledger_authority = 'f360' AND NOT sellable FROM f360.locations WHERE id = bodega), 'existing Bodega CDMX stays f360-mastered, not sellable', '');
  PERFORM pg_temp.as_user(u, 'authenticated');
  lA := public.f360_create_location('ZZ Tienda Prueba A', 'store', (SELECT v FROM t_ids WHERE k = 'chA'));
  lB := public.f360_create_location('ZZ Tienda Prueba B', 'store', (SELECT v FROM t_ids WHERE k = 'chB'));
  lN := public.f360_create_location('ZZ Bazar Nuevo', 'bazaar', NULL, NULL, '2026-11-01', '2026-11-03');
  BEGIN PERFORM public.f360_create_location('Duplicada', 'store', (SELECT v FROM t_ids WHERE k = 'chA')); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  RESET ROLE;
  INSERT INTO t_ids VALUES ('lA', (lA->>'id')::uuid), ('lB', (lB->>'id')::uuid), ('lN', (lN->>'id')::uuid);
  PERFORM pg_temp.ok(lA->>'ledger_authority' = 'legacy' AND (lA->>'sellable')::boolean, 'location linked to a legacy channel starts LEGACY (one master)', lA->>'ledger_authority');
  PERFORM pg_temp.ok(lN->>'ledger_authority' = 'f360' AND lN->>'type' = 'bazaar' AND lN->>'ends_on' = '2026-11-03', 'new bazaar with no legacy stock starts f360, with dates', '');
  PERFORM pg_temp.ok(err <> 'accepted', 'one channel cannot map to two locations', err);

  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_receive_inventory(gen_random_uuid(), (lA->>'id')::uuid,
    jsonb_build_array(jsonb_build_object('variant_id', (SELECT t_ids.v FROM t_ids WHERE k = 'var'), 'quantity', 1)), NULL);
    err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%sistema anterior%', 'receiving into a LEGACY location is refused (no second master)', err);
END $$;

DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; err text; r jsonb; lA uuid := (SELECT v FROM t_ids WHERE k = 'lA'); lB uuid := (SELECT v FROM t_ids WHERE k = 'lB'); lN uuid := (SELECT v FROM t_ids WHERE k = 'lN');
BEGIN
  -- the lab user may carry a demo seller role; for this check she must not be a seller (rolled back anyway)
  DELETE FROM f360.location_assignments WHERE auth_user_id = current_setting('t.c1')::uuid;
  DELETE FROM f360.seller_sessions WHERE auth_user_id = current_setting('t.c1')::uuid;
  DELETE FROM f360.seller_credentials WHERE auth_user_id = current_setting('t.c1')::uuid;
  DELETE FROM f360.user_roles WHERE auth_user_id = current_setting('t.c1')::uuid AND role = 'seller';
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_set_location_assignment(current_setting('t.c1')::uuid, lA, true); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%vendedoras%', 'assignments only for users with role seller', err);
  PERFORM public.f360_set_user_role(current_setting('t.c1')::uuid, 'seller', 'Vendedora Prueba');
  PERFORM public.f360_set_user_role(current_setting('t.c2')::uuid, 'viewer', 'Consulta Prueba');
  PERFORM public.f360_set_user_role(current_setting('t.c3')::uuid, 'operator', 'Operadora Prueba');
  PERFORM public.f360_set_location_assignment(current_setting('t.c1')::uuid, lA, true);
  PERFORM public.f360_set_location_assignment(current_setting('t.c1')::uuid, lN, true);
  -- make Carolina the LAST owner (Mario → viewer, rolled back), then try to demote her
  PERFORM public.f360_set_user_role(current_setting('t.mario')::uuid, 'viewer', 'Mario');
  BEGIN PERFORM public.f360_set_user_role(u, 'viewer', 'Carolina'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%al menos una dueña%' AND (SELECT role FROM f360.user_roles WHERE auth_user_id = u) = 'owner', 'the last owner cannot be demoted', err);

  PERFORM pg_temp.as_user(current_setting('t.c1')::uuid, 'authenticated');
  r := public.f360_my_locations();
  RESET ROLE;
  PERFORM pg_temp.claims(current_setting('t.c1')::uuid);
  -- robust to other committed synthetic fixtures (e.g. the C3 demo store assigned to the same lab user):
  -- every location returned must be an ACTIVE assignment of hers, and of this test's locations exactly the 2 assigned ones
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE NOT EXISTS (SELECT 1 FROM f360.location_assignments a
      WHERE a.auth_user_id = current_setting('t.c1')::uuid AND a.location_id = (x->>'id')::uuid AND a.active))
    AND (SELECT count(*) FROM jsonb_array_elements(r) x WHERE x->>'name' LIKE 'ZZ %') = 2 AND r::text LIKE '%ZZ Tienda Prueba A%' AND r::text LIKE '%ZZ Bazar Nuevo%' AND r::text NOT LIKE '%Prueba B%' AND r::text NOT LIKE '%Bodega%',
    'seller sees ONLY her assigned locations at shift start (D-L2: several allowed)', r::text);
  PERFORM f360.require_location(lA);
  BEGIN PERFORM f360.require_location(lB); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%No tienes asignada%', 'seller cannot act at a location she is not assigned to', err);

  PERFORM pg_temp.as_user(u, 'authenticated');
  PERFORM public.f360_set_location_assignment(current_setting('t.c1')::uuid, lA, false);
  RESET ROLE;
  PERFORM pg_temp.claims(current_setting('t.c1')::uuid);
  BEGIN PERFORM f360.require_location(lA); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'revoked assignment → access gone immediately', err);

  PERFORM pg_temp.claims(current_setting('t.c2')::uuid);
  BEGIN PERFORM f360.require_location(lA); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'viewer can never act at a location', err);

  PERFORM pg_temp.as_user(current_setting('t.c1')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_receive_inventory(gen_random_uuid(), (SELECT t_ids.v FROM t_ids WHERE k = 'bodega'), '[]'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%no tiene permiso%', 'seller cannot receive stock (operator+ only, role check)', err);

  PERFORM pg_temp.claims(current_setting('t.c3')::uuid);
  PERFORM f360.require_location(lB);
  PERFORM pg_temp.as_user(current_setting('t.c3')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_create_location('X', 'store'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'operator acts at any location but cannot create locations or grant roles', err);

  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_my_locations(); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot call C1 RPCs', err);

  PERFORM pg_temp.ok((SELECT count(*) FROM f360.access_changes WHERE by_name = 'Carolina' AND at >= now()) >= 8, 'every role/assignment/location change is audited', '');
  BEGIN UPDATE f360.access_changes SET by_name = 'x'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'access audit is append-only', err);
END $$;

-- ═════ C2 ═════
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; err text; r jsonb; lA uuid := (SELECT v FROM t_ids WHERE k = 'lA'); lN uuid := (SELECT v FROM t_ids WHERE k = 'lN');
  before text; after text; unm uuid; zero uuid; nude37 uuid; props uuid[]; x uuid;
BEGIN
  SELECT string_agg(id || ':' || stock || ':' || sold, ',' ORDER BY id) INTO before FROM public.channel_inventory WHERE channel_id = (SELECT v FROM t_ids WHERE k = 'chA');
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_propose_legacy_mapping(lN); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  r := public.f360_propose_legacy_mapping(lA);
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'mapping needs a location linked to a legacy channel', err);
  SELECT string_agg(id || ':' || stock || ':' || sold, ',' ORDER BY id) INTO after FROM public.channel_inventory WHERE channel_id = (SELECT v FROM t_ids WHERE k = 'chA');
  PERFORM pg_temp.ok(before = after, 'channel_inventory is NEVER written by mapping (read-only)', '');
  PERFORM pg_temp.ok((r->>'rows_total')::int = 4 AND (r->>'proposed')::int = 2 AND (r->>'unmatched')::int = 2 AND (r->>'unmatched_with_units')::int = 1 AND NOT (r->>'catalog_ready')::boolean,
    'proposals: exact SKU + model/color/size (normalized); 2 unmatched; NOT ready', r::text);
  PERFORM pg_temp.ok((SELECT proposal_reason FROM f360.legacy_inventory_map WHERE snap_sku = 'f360-zz-mapeo-prueba-negro-36') = 'sku'
    AND (SELECT proposal_reason FROM f360.legacy_inventory_map WHERE snap_size = 'Talla 37') = 'modelo+color+talla', 'match reasons recorded', '');

  SELECT channel_inventory_id INTO unm FROM f360.legacy_inventory_map WHERE snap_product_name = 'Slingback punta afilada';
  SELECT channel_inventory_id INTO zero FROM f360.legacy_inventory_map WHERE snap_product_name = 'Modelo agotado viejo';
  SELECT array_agg(channel_inventory_id) INTO props FROM f360.legacy_inventory_map WHERE status = 'propuesto' AND location_id = lA;
  SELECT v.id INTO nude37 FROM f360.product_variants v JOIN f360.product_colors c ON c.id = v.color_id WHERE v.product_id = (SELECT t_ids.v FROM t_ids WHERE k = 'p') AND c.name = 'Nude' AND v.size_label = '37';
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_review_legacy_mapping(unm, 'descartar', NULL, 'no lo quiero'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%D-M1%', 'D-M1: a product WITH units cannot be discarded — it must exist in Fuxia 360', err);
  PERFORM public.f360_review_legacy_mapping(zero, 'descartar', NULL, 'Sin existencias, modelo descontinuado');
  FOREACH x IN ARRAY props LOOP PERFORM public.f360_review_legacy_mapping(x, 'confirmar'); END LOOP;
  r := public.f360_location_migration_readiness(lA);
  PERFORM pg_temp.ok(NOT (r->>'catalog_ready')::boolean AND (r->>'unmatched_with_units')::int = 1, 'still NOT ready while one product with units is unmapped', r::text);
  PERFORM public.f360_review_legacy_mapping(unm, 'confirmar', nude37, 'mapeo manual de prueba');
  r := public.f360_location_migration_readiness(lA);
  PERFORM pg_temp.ok((r->>'catalog_ready')::boolean AND (r->>'confirmed')::int = 3 AND (r->>'discarded')::int = 1, 'every product with units confirmed → catalog ready (opening balance still = physical count)', r::text);
  r := public.f360_propose_legacy_mapping(lA);
  RESET ROLE;
  PERFORM pg_temp.ok((r->>'confirmed')::int = 3 AND (SELECT m.confirmed_variant_id FROM f360.legacy_inventory_map m WHERE m.channel_inventory_id = unm) = nude37,
    're-proposing never overwrites human decisions', r::text);

  PERFORM pg_temp.as_user(current_setting('t.c2')::uuid, 'authenticated');
  r := public.f360_location_migration_readiness(lA);
  BEGIN PERFORM public.f360_review_legacy_mapping(unm, 'reabrir'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(r IS NOT NULL AND err <> 'accepted', 'viewer reads readiness but cannot review', err);
  PERFORM pg_temp.as_user(current_setting('t.c1')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_propose_legacy_mapping(lA); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'seller cannot run or change mappings', err);
  PERFORM pg_temp.ok((SELECT ledger_authority FROM f360.locations WHERE id = lA) = 'legacy', 'C2 never switches a location (still legacy)', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
