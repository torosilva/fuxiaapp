-- Fuxia 360 · Conteo de apertura deshacer (borrar talla / quitar par sin ficha) — database tests (STAGING). One transaction, ROLLED BACK.
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
  r := pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ U Bodega', 'warehouse')$q$);
  loc := (r->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_u', 'ZZ U', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_u', '[{"woo_variation_id":970136,"woo_product_id":9701,"woo_product_name":"ZZ U negro","woo_size":"36"},
    {"woo_variation_id":970137,"woo_product_id":9701,"woo_product_name":"ZZ U negro","woo_size":"37"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_u', ARRAY[970136, 970137], NULL, 'ZZ U Modelo', 'ballerinas', 'Negro', NULL)$q$);
  pid := (r->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  SELECT count(*) INTO ev0 FROM f360.inventory_events; SELECT count(*) INTO bal0 FROM f360.inventory_balances;

  cid := (pg_temp.as(car, $q$SELECT public.f360_opening_start('zz_u')$q$)->'count'->>'id')::uuid;

  -- clear a size: refused in double mode
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":2}]')$q$, cid, v36));
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_clear_line(%L, %L)$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%una sola vuelta%', 'clear: refused in a double count', r->>'error');
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_set_simple(%L)$q$, cid));

  -- clear a size in simple mode: back to pendiente, logged with previous value, blocks approval again
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":5}]')$q$, cid, v36));
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_clear_line(%L, %L)$q$, cid, v36));
  PERFORM pg_temp.ok((SELECT status = 'pendiente' AND final_qty IS NULL AND count1 IS NULL FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v36),
    'clear: a counted size goes back to sin contar', coalesce(r->>'error', 'ok'));
  PERFORM pg_temp.ok((SELECT (detail->>'previous_qty')::int = 5 FROM f360.opening_count_changes WHERE count_id = cid AND action = 'clear_line' ORDER BY id DESC LIMIT 1),
    'clear: logged with the previous quantity', 'ok');
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_clear_line(%L, %L)$q$, cid, v36));
  PERFORM pg_temp.ok(NOT r ? 'error', 'clear: clearing an empty size is a harmless no-op', coalesce(r->>'error', 'ok'));
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":0}]')$q$, cid, v37));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_state(%L)$q$, cid));
  PERFORM pg_temp.ok(r->'blockers' @> '["1 tallas sin contar (escribe 0 si no hay pares)"]', 'clear: the cleared size blocks approval until counted', (r->'blockers')::text);
  r := pg_temp.as(NULL, format($q$SELECT public.f360_opening_clear_line(%L, %L)$q$, cid, v37), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'clear: anon cannot call it', r->>'error');

  -- unlisted: author removes own entry; another operator cannot remove someone else's; owner can
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_add_unlisted(%L, 'Paula dorada', '37', 1)$q$, cid));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_add_unlisted(%L, 'Sueco caramelo', '38', 2)$q$, cid));
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_unlisted_open(%L)$q$, cid));
  PERFORM pg_temp.ok(jsonb_array_length(r) = 2, 'unlisted_open lists the open entries', left(r::text, 120));
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_remove_unlisted(%L)$q$, (SELECT id FROM f360.opening_count_unlisted WHERE count_id = cid AND description = 'Sueco caramelo')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo quien lo anotó%', 'remove: an operator cannot remove someone else''s entry', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_remove_unlisted(%L)$q$, (SELECT id FROM f360.opening_count_unlisted WHERE count_id = cid AND description = 'Paula dorada')));
  PERFORM pg_temp.ok((r->'summary'->>'unlisted_open')::int = 1 AND (SELECT status FROM f360.opening_count_unlisted WHERE count_id = cid AND description = 'Paula dorada') = 'quitado',
    'remove: the author removes her own entry (kept as quitado, not deleted)', coalesce(r->>'error', 'ok'));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_remove_unlisted(%L)$q$, (SELECT id FROM f360.opening_count_unlisted WHERE count_id = cid AND description = 'Sueco caramelo')));
  PERFORM pg_temp.ok((r->'summary'->>'unlisted_open')::int = 0, 'remove: Carolina (owner) can remove any entry', coalesce(r->>'error', 'ok'));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.opening_count_changes WHERE count_id = cid AND action = 'unlisted_remove') = 2, 'remove: both removals logged', 'ok');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = ev0 AND (SELECT count(*) FROM f360.inventory_balances) = bal0, 'undo writes no inventory', 'ok');

  -- closed count: nothing can be undone
  PERFORM pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":1}]')$q$, cid, v36));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_freeze(%L)$q$, cid));
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_opening_reconcile(%L)$q$, cid));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_approve(%L, 'Conteo de prueba aprobado')$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'aprobado', 'approve after undo (setup for the next check)', coalesce(r->>'error', r->'count'->>'status') || ' ' || coalesce((r->'blockers')::text, ''));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_clear_line(%L, %L)$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no está abierto%', 'clear: refused once the count is approved', r->>'error');
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
