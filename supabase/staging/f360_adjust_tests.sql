-- Inventory ADJUSTMENT by hand — database tests (STAGING). One transaction, ROLLED BACK.
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
-- a seller for permission checks: lab user 15550100011 gets the role inside this transaction only
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'seller', 'ZZ Vendedora', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'seller' RETURNING auth_user_id AS seller \gset
SELECT id AS op FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.seller', :'seller', true), set_config('t.op', :'op', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; sel uuid := current_setting('t.seller')::uuid; op uuid := current_setting('t.op')::uuid;
  bodega uuid := (SELECT id FROM f360.locations WHERE name = 'Bodega CDMX');
  transit uuid := (SELECT id FROM f360.locations WHERE type = 'transit');
  r jsonb; v35 uuid; v36 uuid; k uuid := gen_random_uuid(); ev uuid;
  bal35 int; bal36 int;
BEGIN
  r := pg_temp.as(car, $q$SELECT public.f360_create_product('ZZ Ajuste', ARRAY['35','36'], '[{"name":"Negro"}]'::jsonb)$q$);
  SELECT id INTO v35 FROM f360.product_variants WHERE product_id = (r->>'id')::uuid AND size_label = '35';
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = (r->>'id')::uuid AND size_label = '36';
  r := pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":3}]'::jsonb)$q$, bodega, v35));
  PERFORM pg_temp.ok((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v35 AND location_id = bodega) = 3, 'fixture: 3 pairs of ZZ Ajuste Negro 35 in Bodega CDMX', r::text);

  r := pg_temp.as(sel, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1}]'::jsonb, 'prueba')$q$, bodega, v35));
  PERFORM pg_temp.ok(r ? 'error', 'a seller cannot adjust inventory', r::text);
  IF op IS NOT NULL THEN
    PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_user_role(%L, 'operator', 'ZZ Operación')$q$, op));
    r := pg_temp.as(op, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1}]'::jsonb, 'prueba')$q$, bodega, v35));
    PERFORM pg_temp.ok(r ? 'error', 'an operator cannot adjust inventory (owner only)', r::text);
  END IF;
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1}]'::jsonb, ' ')$q$, bodega, v35));
  PERFORM pg_temp.ok(r->>'error' = 'Escribe el motivo del ajuste.', 'a reason is mandatory', r::text);

  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(%L, %L, '[{"variant_id":"%s","delta":-2}]'::jsonb, 'Pares de prueba')$q$, k, bodega, v35));
  ev := (r->>'id')::uuid;
  PERFORM pg_temp.ok((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v35 AND location_id = bodega) = 1
    AND (SELECT event_type || '|' || note || '|' || actor_name FROM f360.inventory_events WHERE id = ev) = 'ADJUSTMENT|Ajuste · Pares de prueba|Carolina'
    AND (SELECT count(*) FROM f360.inventory_movements WHERE event_id = ev AND from_location_id = bodega AND to_location_id IS NULL AND quantity = 2) = 1,
    'owner removes 2 pairs: 3 → 1, one ADJUSTMENT event with reason and who, movement Bodega → out ×2', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(%L, %L, '[{"variant_id":"%s","delta":-2}]'::jsonb, 'Pares de prueba')$q$, k, bodega, v35));
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v35 AND location_id = bodega) = 1,
    'same key again (double click) → replayed, applied once', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-5}]'::jsonb, 'demasiado')$q$, bodega, v35));
  PERFORM pg_temp.ok(r->>'error' LIKE 'No se pueden quitar 5 pares%solo hay 1%' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v35 AND location_id = bodega) = 1,
    'never negative: removing more than there is → refused, unchanged', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1},{"variant_id":"%s","delta":2}]'::jsonb, 'Conteo')$q$, bodega, v35, v36));
  PERFORM pg_temp.ok((SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v35 AND location_id = bodega) = 0
    AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v36 AND location_id = bodega) = 2,
    'one adjustment can remove and add (35: 1 → 0, 36: 0 → 2)', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":-1},{"variant_id":"%s","delta":-1}]'::jsonb, 'dup')$q$, bodega, v36, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%una sola vez%', 'the same size twice in one adjustment is refused', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_adjust_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","delta":1}]'::jsonb, 'tránsito')$q$, transit, v36));
  PERFORM pg_temp.ok(r->>'error' = 'Elige una ubicación válida.', '"En camino" cannot be adjusted by hand', r::text);
  SELECT coalesce(sum(CASE WHEN to_location_id = bodega THEN quantity ELSE -quantity END), 0) INTO bal36 FROM f360.inventory_movements WHERE variant_id = v36 AND (to_location_id = bodega OR from_location_id = bodega);
  SELECT coalesce(sum(CASE WHEN to_location_id = bodega THEN quantity ELSE -quantity END), 0) INTO bal35 FROM f360.inventory_movements WHERE variant_id = v35 AND (to_location_id = bodega OR from_location_id = bodega);
  PERFORM pg_temp.ok(bal35 = 0 AND bal36 = 2, 'balances = ledger (sum of movements) after adjustments', bal35 || '/' || bal36);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
