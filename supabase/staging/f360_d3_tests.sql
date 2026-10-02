-- Track D · D3 — opening physical count (double count, freeze, reconciliation, approval) — database tests (STAGING).
-- One transaction, ROLLED BACK. Its own channel "zz_d3" and location "ZZ D3 Bodega": the real Bodega CDMX is not touched.
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
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) SELECT id, 'operator', 'ZZ Operación', 'test (rolled back)' FROM auth.users WHERE email = '15550100011@fuxia.app'
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator' RETURNING auth_user_id AS op \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.mario', :'mario', true), set_config('t.op', :'op', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; mar uuid := current_setting('t.mario')::uuid; op uuid := current_setting('t.op')::uuid;
  r jsonb; loc uuid; cid uuid; pid uuid; v36 uuid; v37 uuid; v38 uuid; tgt uuid; ev0 int; bal0 int; sh jsonb; err text; uid uuid;
BEGIN
  r := pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ D3 Bodega', 'warehouse')$q$);
  loc := (r->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_d3', 'ZZ D3', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_d3', '[{"woo_variation_id":980036,"woo_product_id":9800,"woo_product_name":"ZZ D3 negro","woo_size":"36"},
    {"woo_variation_id":980037,"woo_product_id":9800,"woo_product_name":"ZZ D3 negro","woo_size":"37"},
    {"woo_variation_id":980038,"woo_product_id":9800,"woo_product_name":"ZZ D3 negro","woo_size":"38"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_d3', ARRAY[980036, 980037], NULL, 'ZZ D3 Modelo', 'ballerinas', 'Negro', NULL)$q$);
  pid := (r->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  SELECT count(*) INTO ev0 FROM f360.inventory_events; SELECT count(*) INTO bal0 FROM f360.inventory_balances;
  PERFORM pg_temp.ok(pid IS NOT NULL AND v36 IS NOT NULL AND v37 IS NOT NULL, 'fixture: channel zz_d3 → ZZ D3 Bodega; ZZ D3 Modelo Negro 36, 37 confirmed', '');

  -- start
  r := pg_temp.as(op, $q$SELECT public.f360_opening_start('zz_d3')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'an operator cannot start an opening count (owner only)', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_opening_start('zz_d3', 'Conteo de apertura de prueba')$q$);
  cid := (r->'count'->>'id')::uuid;
  PERFORM pg_temp.ok(r->'count'->>'status' = 'preliminar' AND (r->'summary'->>'lines')::int = 2 AND (r->'summary'->>'pendiente')::int = 2,
    'owner starts the count: scope = the 2 confirmed sizes, all pending', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_opening_start('zz_d3')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE 'Ya hay un conteo abierto%', 'only one open count per location', r::text);

  -- scope follows the homologation (added / out of scope)
  r := pg_temp.as(car, format($q$SELECT public.f360_legacy_confirm('zz_d3', ARRAY[980038], %L, NULL, NULL, 'Negro', NULL)$q$, pid));
  SELECT id INTO v38 FROM f360.product_variants WHERE product_id = pid AND size_label = '38';
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_refresh_scope(%L)$q$, cid));
  PERFORM pg_temp.ok((r->'scope_change'->>'added')::int = 1 AND (r->'summary'->>'lines')::int = 3, 'a model confirmed later is added to the count', r::text);
  PERFORM pg_temp.as(car, $q$SELECT public.f360_legacy_reopen('zz_d3', ARRAY[980038], 'prueba')$q$);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_refresh_scope(%L)$q$, cid));
  PERFORM pg_temp.ok((r->'scope_change'->>'out_of_scope')::int = 1 AND (r->'summary'->>'lines')::int = 2 AND (r->'summary'->>'out_of_scope')::int = 1,
    'a reopened homologation leaves the count (out of scope, history kept)', r::text);

  -- count 1 / count 2 (double control, blind)
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":3},{"variant_id":"%s","qty":2}]')$q$, cid, v36, v37));
  PERFORM pg_temp.ok((r->'summary'->>'contado_1')::int = 2, 'count 1 (Carolina): 36 = 3, 37 = 2', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, '2', '[{"variant_id":"%s","qty":3}]')$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%otra persona%', 'count 2 by the same person is refused (double control)', r::text);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":9}]')$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%otra persona%', 'someone else cannot overwrite count 1', r::text);
  sh := pg_temp.as(mar, format($q$SELECT public.f360_opening_sheet(%L, 'conteo2')$q$, cid));
  PERFORM pg_temp.ok((SELECT bool_and((s->>'count1') IS NULL AND (s->>'count1_done')::boolean) FROM jsonb_array_elements(sh->'models'->0->'colors'->0->'sizes') s),
    'count 2 is blind: the sheet hides count 1 values (only "already counted")', sh::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_record(%L, '2', '[{"variant_id":"%s","qty":3},{"variant_id":"%s","qty":1}]')$q$, cid, v36, v37));
  PERFORM pg_temp.ok((r->'summary'->>'doble_ok')::int = 1 AND (r->'summary'->>'diferencia')::int = 1
    AND (SELECT final_qty FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v36) = 3
    AND (SELECT final_qty FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v37) IS NULL,
    'count 2 (Mario): 36 matches → final 3; 37 differs (2 vs 1) → no final until recount', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_approve(%L, 'ok')$q$, cid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%congela%' AND r->>'error' LIKE '%diferencia%', 'approval blocked: not frozen, a difference pending (reasons listed)', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, 're', '[{"variant_id":"%s","qty":3}]')$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no necesita reconteo%', 'a size that matched does not take a recount', r::text);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, 're', '[{"variant_id":"%s","qty":1}]')$q$, cid, v37));
  PERFORM pg_temp.ok((r->'summary'->>'recontado')::int = 1 AND (SELECT final_qty FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v37) = 1,
    'recount settles the difference: 37 final = 1', r::text);

  -- pairs without a homologated model
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_add_unlisted(%L, 'Mule beige sin etiqueta', '37', 2)$q$, cid));
  PERFORM pg_temp.ok((r->'summary'->>'unlisted_open')::int = 1 AND (r->'summary'->>'unlisted_pairs')::int = 2, 'pairs found without a model are recorded (not lost, not counted as stock)', r::text);
  SELECT id INTO uid FROM f360.opening_count_unlisted WHERE count_id = cid;
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_resolve_unlisted(%L, 'Homologado')$q$, uid));
  PERFORM pg_temp.ok(r ? 'error', 'only an owner resolves "sin ficha"', r::text);

  -- freeze → moves at the location refused
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_freeze(%L)$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'congelado' AND f360.location_in_cutover(loc), 'freeze window starts: the location is in cutover', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, loc, v36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'while frozen, receiving at the location is refused', r::text);
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_approve(%L, 'ok')$q$, cid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%reconciliar%' AND r->>'error' LIKE '%sin ficha%', 'approval blocked: not reconciled, "sin ficha" open', r::text);

  -- a Woo sale after the count → that size must be recounted
  INSERT INTO f360.woo_orders (target_id, woo_order_id, woo_status, woo_modified_at, currency) VALUES (tgt, 9980001, 'processing', clock_timestamp(), 'MXN');
  INSERT INTO f360.woo_order_lines (target_id, woo_order_id, woo_line_id, woo_product_id, woo_variation_id, quantity, outcome, created_at)
    VALUES (tgt, 9980001, 1, 9800, 980036, 1, 'legacy', clock_timestamp());
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_reconcile(%L)$q$, cid));
  PERFORM pg_temp.ok((r->>'to_recount')::int = 1 AND (SELECT status || ':' || (affected->>'woo_sold') FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v36) = 'recontar:1'
    AND (SELECT status FROM f360.opening_count_lines WHERE count_id = cid AND variant_id = v37) = 'recontado',
    'reconciliation: 36 sold 1 online after its count → recount; 37 untouched', r::text);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_record(%L, 're', '[{"variant_id":"%s","qty":2}]')$q$, cid, v36));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_resolve_unlisted(%L, 'Es Mafalda beige: se homologa aparte y se cuenta en el siguiente conteo')$q$, uid));
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_approve(%L, 'ok')$q$, cid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%reconcilia de nuevo%', 'a recount after the reconciliation requires reconciling again', r::text);
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_reconcile(%L)$q$, cid));
  PERFORM pg_temp.ok((r->>'to_recount')::int = 0 AND jsonb_array_length(r->'blockers') = 0, 'reconciled again: nothing to recount, no blockers', r::text);

  -- Woo reference (never the balance) and the report
  PERFORM public.f360_opening_set_woo_reference(cid, '[{"woo_variation_id":980036,"managed":true,"stock":5},{"woo_variation_id":980037,"managed":false}]');
  sh := pg_temp.as(car, format($q$SELECT public.f360_opening_sheet(%L, 'reporte')$q$, cid));
  PERFORM pg_temp.ok((SELECT (s->>'difference')::int FROM jsonb_array_elements(sh->'models'->0->'colors'->0->'sizes') s WHERE s->>'size' = '36') = -3
    AND (SELECT s->>'difference' FROM jsonb_array_elements(sh->'models'->0->'colors'->0->'sizes') s WHERE s->>'size' = '37') IS NULL,
    'report: Woo 5 vs count 2 → difference −3; Woo without stock control → no number', sh::text);

  -- approval (Mario) seals the count, writes no inventory
  r := pg_temp.as(op, format($q$SELECT public.f360_opening_approve(%L, 'ok')$q$, cid));
  PERFORM pg_temp.ok(r ? 'error', 'an operator cannot approve', r::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_approve(%L, ' ')$q$, cid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%nota%', 'approval needs a note', r::text);
  r := pg_temp.as(mar, format($q$SELECT public.f360_opening_approve(%L, 'Conteo revisado, aprobado para apertura')$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'aprobado' AND r->'count'->>'approved_by' = 'Mario' AND (r->'summary'->>'final_pairs')::int = 3,
    'Mario approves: sealed, 3 pairs final (36 = 2, 37 = 1)', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = ev0 AND (SELECT count(*) FROM f360.inventory_balances) = bal0,
    'NOTHING was written to inventory (no event, no balance): the opening load is a separate step', '');
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_record(%L, '1', '[{"variant_id":"%s","qty":1}]')$q$, cid, v36));
  PERFORM pg_temp.ok(r->>'error' = 'El conteo no está abierto.' AND f360.location_in_cutover(loc), 'an approved count is sealed and keeps the location frozen', r::text);
  BEGIN UPDATE f360.opening_count_changes SET actor_name = 'x' WHERE count_id = cid; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%' AND (SELECT count(*) FROM f360.opening_count_changes WHERE count_id = cid) >= 10, 'every step is logged, append-only', err);
  r := pg_temp.as(car, format($q$SELECT public.f360_opening_cancel(%L, 'Prueba terminada')$q$, cid));
  PERFORM pg_temp.ok(r->'count'->>'status' = 'cancelado' AND NOT f360.location_in_cutover(loc), 'cancel releases the freeze', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
