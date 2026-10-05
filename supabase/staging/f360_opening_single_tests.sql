-- Fuxia 360 · Conteo de apertura modo simple — database tests (STAGING). One transaction, ROLLED BACK.
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
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'operator', 'ZZ Operación', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator' RETURNING auth_user_id AS op \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.op', :'op', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; op uuid := current_setting('t.op')::uuid;
  r jsonb; loc uuid; cid uuid; pid uuid; v36 uuid; v37 uuid; tgt uuid; ev0 int; bal0 int;
BEGIN
  r := pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ S Bodega', 'warehouse')$q$);
  loc := (r->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_s', 'ZZ S', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_s', '[{"woo_variation_id":970036,"woo_product_id":9700,"woo_product_name":"ZZ S negro","woo_size":"36"},
    {"woo_variation_id":970037,"woo_product_id":9700,"woo_product_name":"ZZ S negro","woo_size":"37"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_s', ARRAY[970036, 970037], NULL, 'ZZ S Modelo', 'ballerinas', 'Negro', NULL)$q$);
  pid := (r->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  SELECT count(*) INTO ev0 FROM f360.inventory_events; SELECT count(*) INTO bal0 FROM f360.inventory_balances;

  cid := (pg_temp.as(car, $q$SELECT public.f360_opening_start('zz_s')$q$)->'count'->>'id')::uuid;
  PERFORM pg_temp.ok((SELECT mode FROM f360.opening_counts WHERE id = cid) = 'doble', 'API default unchanged: f360_opening_start alone is still a double count', 'ok');
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_set_simple(%L)$q$, cid));
  PERFORM pg_temp.ok(r ? 'error', 'only an owner switches to one count', r->>'error');
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_set_simple(%L)$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'mode' = 'simple' AND r->'summary'->>'mode' = 'simple', 'Carolina switches the count to ONE count (Mario 2026-10-05 b)', r->'count'->>'mode');

  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":3}]')$q$, cid, v36));
  PERFORM pg_temp.ok((SELECT status = 'contado' AND final_qty = 3 FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v36),
    'one count: the first count is the final quantity', coalesce(r->>'error', 'ok'));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":4}]')$q$, cid, v36));
  PERFORM pg_temp.ok((SELECT final_qty = 4 AND count1_by_name = 'Carolina' FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v36),
    'one count: another person can correct it while open (logged)', coalesce(r->>'error', 'ok'));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.opening_count_changes WHERE count_id = cid AND action = 'count_1') = 2, 'every count is in the append-only log', 'ok');
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '2', '[{"variant_id":"%s","qty":4}]')$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%una sola vuelta%', 'one count: no second round', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":-1}]')$q$, cid, v37));
  PERFORM pg_temp.ok(r ? 'error', 'negative refused', r->>'error');

  -- easy sheet
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_easy_sheet(%L)$q$, cid));
  PERFORM pg_temp.ok(r->>'mode' = 'simple' AND jsonb_array_length(r->'models') = 1 AND (r->'models'->0->>'sizes_total')::int = 2 AND (r->'models'->0->>'sizes_done')::int = 1,
    'easy sheet: model with photo slot, colors, sizes and progress', left(r::text, 120));

  -- blockers: pending size, then freeze + reconcile + approve
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_state(%L)$q$, cid));
  PERFORM pg_temp.ok(r->'blockers' @> '["1 tallas sin contar (escribe 0 si no hay pares)"]', 'blocker: a size without count (0 must be written)', (r->'blockers')::text);
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":0}]')$q$, cid, v37));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_freeze(%L)$q$, cid));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_reconcile(%L)$q$, cid));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_approve(%L, 'Conteo de Carolina')$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'aprobado' AND (r->'summary'->>'final_pairs')::int = 4, 'Carolina approves the single count (4 pares)', coalesce(r->>'error', r->'count'->>'status'));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = ev0 AND (SELECT count(*) FROM f360.inventory_balances) = bal0, 'approval writes no inventory (loading stays a separate step)', 'ok');
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_load(%L, gen_random_uuid())$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'cargado' AND (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v36 AND location_id = loc) = 4,
    'the existing D4 load takes the single count as the opening balance', coalesce(r->>'error', r->'count'->>'status'));
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
