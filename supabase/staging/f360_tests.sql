-- Fuxia 360 Admin V1 — database tests (STAGING). Everything runs in one transaction and is ROLLED BACK.
-- Output: one row per check: PASS/FAIL | name | detail
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;

CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN '{"role":"anon"}' ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon;

-- Fixture ids (staging)
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS e1 FROM auth.users WHERE email = 'e1.attacker@staging.invalid' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS bodega FROM f360.locations WHERE name = 'Bodega CDMX' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.e1', :'e1', true), set_config('t.c1', :'c1', true), set_config('t.bodega', :'bodega', true) \gset t_
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c1', 'viewer', 'Viewer de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'viewer', display_name = 'Viewer de prueba', granted_by = 'test (rolled back)';   -- the lab user may carry a demo role; rolled back anyway

-- 1. anon cannot call f360 RPCs
DO $$ BEGIN PERFORM pg_temp.as_user(NULL, 'anon'); PERFORM public.f360_me();
  INSERT INTO t_results(status,name,detail) VALUES ('FAIL','anon denied','call succeeded'); RESET ROLE;
EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('PASS','anon denied', SQLERRM); END $$;

-- 2. authenticated user WITHOUT an f360 role (email-only E1) is denied
DO $$ DECLARE u uuid := current_setting('t.e1')::uuid; BEGIN PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_me();
  RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('FAIL','no-role user denied','call succeeded');
EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('PASS','no-role user denied', SQLERRM); END $$;

-- 3. no direct table access for authenticated users
DO $$ DECLARE u uuid := current_setting('t.carolina')::uuid; BEGIN PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM count(*) FROM f360.products;
  RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('FAIL','no direct table access','select succeeded');
EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('PASS','no direct table access', SQLERRM); END $$;

-- 4. viewer cannot create products
DO $$ DECLARE u uuid := current_setting('t.c1')::uuid; BEGIN PERFORM pg_temp.as_user(u, 'authenticated');
  PERFORM public.f360_create_product('ZZ Viewer', ARRAY['23'], '[{"name":"Negro"}]'::jsonb);
  RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('FAIL','viewer cannot write','create succeeded');
EXCEPTION WHEN insufficient_privilege THEN RESET ROLE; INSERT INTO t_results(status,name,detail) VALUES ('PASS','viewer cannot write', SQLERRM); END $$;

-- 5. owner creates product; receives 2+3 pairs; balances; idempotent replay; validation; reconciliation
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; loc uuid := current_setting('t.bodega')::uuid;
  p jsonb; v23 uuid; v24 uuid; ev jsonb; ev2 jsonb; k uuid := gen_random_uuid(); b23 int; b24 int; n_events int; err text;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Prueba Automática', ARRAY['23','24'], '[{"name":"Negro","hex":"#1C1A17"}]'::jsonb);
  v23 := (SELECT (v->>'id')::uuid FROM jsonb_array_elements(p->'colors'->0->'variants') v WHERE v->>'size' = '23');
  v24 := (SELECT (v->>'id')::uuid FROM jsonb_array_elements(p->'colors'->0->'variants') v WHERE v->>'size' = '24');
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN v23 IS NOT NULL AND v24 IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, 'owner creates product + variants', p->>'name');

  ev := public.f360_receive_inventory(k, loc, jsonb_build_array(jsonb_build_object('variant_id', v23, 'quantity', 2), jsonb_build_object('variant_id', v24, 'quantity', 3), jsonb_build_object('variant_id', v23, 'quantity', 0)), 'prueba');
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN (ev->>'total_pairs')::int = 5 AND ev->>'actor_name' = 'Carolina' AND ev->>'type' = 'RECEIPT' THEN 'PASS' ELSE 'FAIL' END,
    'receipt recorded (5 pairs, actor Carolina)', (ev->>'actor_name') || ' ' || (ev->>'total_pairs'));

  ev2 := public.f360_receive_inventory(k, loc, jsonb_build_array(jsonb_build_object('variant_id', v23, 'quantity', 2)), NULL);
  RESET ROLE;
  SELECT on_hand INTO b23 FROM f360.inventory_balances WHERE variant_id = v23 AND location_id = loc;
  SELECT on_hand INTO b24 FROM f360.inventory_balances WHERE variant_id = v24 AND location_id = loc;
  SELECT count(*) INTO n_events FROM f360.inventory_events WHERE idempotency_key = k;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN b23 = 2 AND b24 = 3 THEN 'PASS' ELSE 'FAIL' END, 'balances updated (23→2, 24→3)', b23 || '/' || b24);
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN (ev2->>'replayed')::boolean AND n_events = 1 THEN 'PASS' ELSE 'FAIL' END, 'double submit is idempotent (1 event, balances unchanged)', 'events=' || n_events);
  INSERT INTO t_results(status,name,detail) SELECT CASE WHEN bool_and(b.on_hand = coalesce(m.qty,0)) THEN 'PASS' ELSE 'FAIL' END, 'balances reconcile with ledger', count(*)::text
    FROM f360.inventory_balances b LEFT JOIN (
      -- in − out per variant and location (P2.3A adds SALE movements that LEAVE a location)
      SELECT x.variant_id, x.lid, sum(x.q) qty FROM (
        SELECT mv.variant_id, mv.to_location_id AS lid, mv.quantity AS q FROM f360.inventory_movements mv WHERE mv.to_location_id IS NOT NULL
        UNION ALL
        SELECT mv.variant_id, mv.from_location_id, -mv.quantity FROM f360.inventory_movements mv WHERE mv.from_location_id IS NOT NULL) x GROUP BY 1, 2
    ) m ON m.variant_id = b.variant_id AND m.lid = b.location_id;

  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_receive_inventory(gen_random_uuid(), loc, jsonb_build_array(jsonb_build_object('variant_id', v23, 'quantity', 0)), NULL); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'zero-pair receipt rejected', err);
  BEGIN PERFORM public.f360_receive_inventory(gen_random_uuid(), loc, jsonb_build_array(jsonb_build_object('variant_id', v23, 'quantity', -4)), NULL); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'negative quantity rejected', err);
  BEGIN PERFORM public.f360_receive_inventory(gen_random_uuid(), loc, jsonb_build_array(jsonb_build_object('variant_id', gen_random_uuid(), 'quantity', 1)), NULL); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'unknown variant rejected', err);
  BEGIN PERFORM public.f360_create_product('ZZ Prueba Automática', ARRAY['23'], '[{"name":"Negro"}]'::jsonb); err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'duplicate product name rejected', err);
  RESET ROLE;

  -- history is append-only, even for the database owner
  BEGIN UPDATE f360.inventory_events SET note = 'x' WHERE idempotency_key = k; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'ledger UPDATE blocked', err);
  BEGIN DELETE FROM f360.inventory_movements WHERE variant_id = v23; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN err <> 'accepted' THEN 'PASS' ELSE 'FAIL' END, 'ledger DELETE blocked', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
