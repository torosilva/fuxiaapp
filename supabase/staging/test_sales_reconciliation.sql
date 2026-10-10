-- Conciliación de Ventas — rolled-back checks (staging). Run: psql "$STAGING_DB_URL" -f supabase/staging/test_sales_reconciliation.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE display_name = 'Mario');
  owner_np uuid := (SELECT r.auth_user_id FROM f360.user_roles r WHERE r.role = 'owner' AND NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers v WHERE v.auth_user_id = r.auth_user_id) LIMIT 1);
  operator uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'operator' LIMIT 1);
  seller uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' LIMIT 1);
  tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  who uuid; d jsonb; e jsonb; e2 jsonb; n int; facts_before text; cockpit_before jsonb; first_id bigint; paid_src bigint;
BEGIN
  IF mario IS NULL OR tgt IS NULL THEN RAISE EXCEPTION 'R0 fixtures (Mario / woo_staging4)'; END IF;
  SELECT md5(string_agg(o::text, '|' ORDER BY woo_order_id)) INTO facts_before FROM f360.commerce_woo_orders o WHERE target_id = tgt;
  -- R1 only Carolina & Mario: anon, seller, operator and an owner who is not a PII viewer are refused everywhere
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN PERFORM public.f360_rec_list(); RAISE EXCEPTION 'R1 anon'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  FOREACH who IN ARRAY array_remove(ARRAY[seller, operator, owner_np], NULL) LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
    BEGIN PERFORM public.f360_rec_can_view(); RAISE EXCEPTION 'R1 can_view %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM public.f360_rec_list(); RAISE EXCEPTION 'R1 list %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM public.f360_rec_summary(); RAISE EXCEPTION 'R1 summary %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM public.f360_rec_case(tgt, 5351); RAISE EXCEPTION 'R1 case %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM public.f360_rec_decide(tgt, 5351, 'prueba', 'intento ajeno'); RAISE EXCEPTION 'R1 decide %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
    BEGIN PERFORM public.f360_rec_set_analytics(tgt, 5351, true, 'intento ajeno'); RAISE EXCEPTION 'R1 exclude %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  IF owner_np IS NULL THEN RAISE NOTICE 'R1: no owner without PII access in staging (skipped that case)'; END IF;
  -- R2 no direct access: tables/views closed to app roles; evidence writes only for the service role
  IF has_table_privilege('authenticated', 'f360.sales_rec_decisions', 'SELECT') OR has_table_privilege('authenticated', 'f360.sales_rec_evidence', 'INSERT')
     OR has_table_privilege('anon', 'f360.sales_rec_cases_state', 'SELECT') THEN RAISE EXCEPTION 'R2 table grants'; END IF;
  IF has_function_privilege('authenticated', 'public.f360_rec_evidence_record(uuid, text, bigint, jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.f360_rec_list(date, date, text, text, text, text, text, text, int, int)', 'EXECUTE') THEN RAISE EXCEPTION 'R2 function grants'; END IF;
  -- R3 the list is Commerce Facts (no copy): every order of the store appears once; filters work; summary adds up
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  cockpit_before := (SELECT jsonb_agg(m - 'adjustments') FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') m);   -- original figures only
  d := public.f360_rec_list(p_limit => 200);
  IF (d->>'total')::int <> (SELECT count(*) FROM f360.commerce_woo_orders) THEN RAISE EXCEPTION 'R3 total % vs facts', d->>'total'; END IF;
  d := public.f360_rec_list(p_market => 'CO', p_limit => 200);
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(d->'rows') r WHERE r->>'market' <> 'CO' OR r->>'currency' <> 'COP') THEN RAISE EXCEPTION 'R3 market filter'; END IF;
  d := public.f360_rec_list(p_method => 'epayco', p_woo_status => 'cancelled', p_limit => 200);
  IF (d->>'total')::int = 0 OR EXISTS (SELECT 1 FROM jsonb_array_elements(d->'rows') r WHERE r->>'payment_method' <> 'epayco' OR r->>'woo_status' <> 'cancelled') THEN RAISE EXCEPTION 'R3 method/status filter'; END IF;
  d := public.f360_rec_summary();
  IF (SELECT sum((m->>'orders')::int) FROM jsonb_array_elements(d->'by_market') m) <> (SELECT count(*) FROM f360.commerce_woo_orders) THEN RAISE EXCEPTION 'R3 summary'; END IF;
  -- R4 flags separate "no se concretó" from real financial discrepancies, each with its reason
  d := public.f360_rec_case(tgt, 5351);
  IF NOT d->'flags' @> '[{"code":"PAGO_Y_CANCELADO","kind":"financiera"}]' OR (d->'decision' = 'null'::jsonb AND d->>'rec_state' <> 'pendiente_discrepancia') THEN RAISE EXCEPTION 'R4 5351 %', d->'flags'; END IF;
  IF NOT public.f360_rec_case(tgt, 3654)->'flags' @> '[{"code":"POSIBLE_PRUEBA"}]' THEN RAISE EXCEPTION 'R4 3654'; END IF;
  d := public.f360_rec_case(tgt, 3097);
  IF NOT d->'flags' @> '[{"code":"NO_CONCRETADO","kind":"no_concretado"},{"code":"REINTENTO_PAGADO"}]' OR d->>'financial_state' <> 'SIN_COBRO'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(d->'flags') f WHERE f->>'kind' = 'financiera') THEN RAISE EXCEPTION 'R4 3097 %', d->'flags'; END IF;
  IF public.f360_rec_case(tgt, 3101)->'flags' @> '[{"code":"POSIBLE_DUPLICADO"}]' THEN RAISE EXCEPTION 'R4 retry flagged as duplicate'; END IF;
  -- R5 duplicates are candidates only: a second PAID copy of an order is flagged on both sides, nothing is decided automatically
  SELECT o.woo_order_id INTO paid_src FROM f360.commerce_woo_orders o WHERE o.target_id = tgt AND o.ever_paid AND o.woo_status = 'completed' AND o.order_total > 0
    AND EXISTS (SELECT 1 FROM f360.commerce_woo_order_lines l WHERE l.target_id = o.target_id AND l.woo_order_id = o.woo_order_id) ORDER BY o.woo_order_id LIMIT 1;
  INSERT INTO f360.commerce_woo_orders SELECT (jsonb_populate_record(o, jsonb_build_object('woo_order_id', 999001, 'woo_created_at', o.woo_created_at + interval '2 hours'))).*
    FROM f360.commerce_woo_orders o WHERE o.target_id = tgt AND o.woo_order_id = paid_src;
  INSERT INTO f360.commerce_woo_order_lines SELECT (jsonb_populate_record(l, jsonb_build_object('woo_order_id', 999001, 'woo_line_id', 99900000 + l.woo_line_id))).*
    FROM f360.commerce_woo_order_lines l WHERE l.target_id = tgt AND l.woo_order_id = paid_src;
  d := public.f360_rec_case(tgt, 999001);
  IF NOT d->'flags' @> jsonb_build_array(jsonb_build_object('code', 'POSIBLE_DUPLICADO', 'candidates', jsonb_build_array(paid_src))) OR d->'decision' <> 'null'::jsonb
     OR d->>'rec_state' <> 'pendiente' OR jsonb_array_length(d->'duplicates') <> 1 THEN RAISE EXCEPTION 'R5 % %', paid_src, d->'flags'; END IF;
  IF NOT public.f360_rec_case(tgt, paid_src)->'flags' @> '[{"code":"POSIBLE_DUPLICADO"}]' THEN RAISE EXCEPTION 'R5 other side'; END IF;
  -- R6 evidence: service-only writer, actor must be a viewer, card-like numbers never stored, hash recorded
  IF owner_np IS NOT NULL THEN
    BEGIN PERFORM public.f360_rec_evidence_record(owner_np, 'woo_staging4', 5351, '{"gateway_result":"approved"}'); RAISE EXCEPTION 'R6 spoof';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END IF;
  e := public.f360_rec_evidence_record(mario, 'woo_staging4', 5351, jsonb_build_object('woo_status', 'cancelled', 'date_paid', '2026-10-08T14:18:36Z',
         'transaction_ref', '4111 1111 1111 1111', 'payment_method', 'woo-mercado-pago-custom', 'order_total', 2800, 'currency', 'MXN',
         'gateway_result', 'approved', 'signals', jsonb_build_array('note_approved', 'date_paid', 'nota libre: Ana 5512345678')));
  IF e->>'transaction_ref' IS NOT NULL OR NOT e->'signals' @> '["tx_redacted","note_approved"]' OR e->'signals' @> '["nota libre: Ana 5512345678"]'
     OR length(e->>'hash') <> 64 THEN RAISE EXCEPTION 'R6 evidence %', e; END IF;
  -- R7 a human "venta confirmada" needs evidence and NEVER turns into a verified charge; facts and Growth metrics untouched
  BEGIN PERFORM public.f360_rec_decide(tgt, 5351, 'venta_confirmada'); RAISE EXCEPTION 'R7 without evidence';
  EXCEPTION WHEN check_violation THEN NULL; END;
  d := public.f360_rec_decide(tgt, 5351, 'venta_confirmada', 'prueba R7: confirmación humana', (e->>'id')::bigint);
  IF d->>'rec_state' <> 'conflicto' OR d->>'conflict' IS NULL OR d->>'financial_state' = 'COBRO_CON_TRANSACCION' THEN RAISE EXCEPTION 'R7 %', d; END IF;
  first_id := (d->>'id')::bigint;
  -- R8 correcting a decision needs a reason; the new one supersedes, history keeps both
  BEGIN PERFORM public.f360_rec_decide(tgt, 5351, 'no_se_concreto'); RAISE EXCEPTION 'R8 no reason';
  EXCEPTION WHEN check_violation THEN NULL; END;
  d := public.f360_rec_decide(tgt, 5351, 'requiere_investigacion', 'Mercado Pago dice aprobado; pedir a Carolina el estado de cuenta');
  IF (d->>'supersedes')::bigint <> first_id OR d->>'rec_state' <> 'en_investigacion' THEN RAISE EXCEPTION 'R8 %', d; END IF;
  d := public.f360_rec_case(tgt, 5351);
  IF jsonb_array_length(d->'decision_history') <> 2 + (SELECT count(*) FROM f360.sales_rec_decisions x WHERE x.target_id = tgt AND x.woo_order_id = 5351 AND x.id < first_id) OR d->'decision'->>'decision' <> 'requiere_investigacion' OR d->'decision'->>'by' <> 'Mario' THEN RAISE EXCEPTION 'R8 history'; END IF;
  -- R9 duplicado needs the other order + reason; prueba needs a reason; invalid decision refused
  BEGIN PERFORM public.f360_rec_decide(tgt, 999001, 'duplicado', 'mismo pedido dos veces'); RAISE EXCEPTION 'R9 dup without original'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM public.f360_rec_decide(tgt, 999001, 'duplicado', 'mismo pedido dos veces', NULL, 999001); RAISE EXCEPTION 'R9 dup of itself'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM public.f360_rec_decide(tgt, 3654, 'prueba'); RAISE EXCEPTION 'R9 prueba without reason'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM public.f360_rec_decide(tgt, 3654, 'cobrada'); RAISE EXCEPTION 'R9 bad decision'; EXCEPTION WHEN check_violation THEN NULL; END;
  d := public.f360_rec_decide(tgt, 999001, 'duplicado', 'La clienta pagó dos veces el mismo carrito', NULL, paid_src);
  IF d->>'conflict' IS NULL THEN RAISE EXCEPTION 'R9 paid duplicate without refund must show conflict %', d; END IF;
  d := public.f360_rec_decide(tgt, 3654, 'prueba', 'Pedido de prueba del equipo (método f360_prueba)');   -- may supersede an example review
  -- R10 exclusion is a separate action with reason, append-only, reversible by a new record; NOT applied to metrics yet
  IF EXISTS (SELECT 1 FROM f360.sales_rec_analytics_scope WHERE target_id = tgt AND woo_order_id = 3654 AND excluded) THEN   -- example exclusion in staging
    PERFORM public.f360_rec_set_analytics(tgt, 3654, false, 'test: parte de incluido');
  END IF;
  BEGIN PERFORM public.f360_rec_set_analytics(tgt, 3654, true, 'x'); RAISE EXCEPTION 'R10 short reason'; EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM public.f360_rec_set_analytics(tgt, 3654, true, 'Pedido de prueba, no es venta');
  BEGIN PERFORM public.f360_rec_set_analytics(tgt, 3654, true, 'otra vez excluir'); RAISE EXCEPTION 'R10 double exclude'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'R10%' THEN RAISE; END IF; END;
  IF NOT (public.f360_rec_case(tgt, 3654)->>'excluded')::boolean THEN RAISE EXCEPTION 'R10 excluded flag'; END IF;
  PERFORM public.f360_rec_set_analytics(tgt, 3654, false, 'Se vuelve a incluir para revisar');
  IF (public.f360_rec_case(tgt, 3654)->>'excluded')::boolean OR jsonb_array_length(public.f360_rec_case(tgt, 3654)->'exclusion_history') < 2 THEN RAISE EXCEPTION 'R10 include'; END IF;
  -- R11 append-only: nothing recorded can be edited or deleted
  BEGIN UPDATE f360.sales_rec_decisions SET decision = 'venta_confirmada' WHERE id = first_id; RAISE EXCEPTION 'R11 update decision'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'R11%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360.sales_rec_decisions WHERE id = first_id; RAISE EXCEPTION 'R11 delete decision'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'R11%' THEN RAISE; END IF; END;
  BEGIN UPDATE f360.sales_rec_evidence SET transaction_ref = 'X' WHERE id = (e->>'id')::bigint; RAISE EXCEPTION 'R11 update evidence'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'R11%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360.sales_rec_exclusions; RAISE EXCEPTION 'R11 delete exclusions'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'R11%' THEN RAISE; END IF; END;
  -- R12 the source and the metrics never change because of a review (fixture order 999001 removed from the comparison)
  DELETE FROM f360.commerce_woo_order_lines WHERE target_id = tgt AND woo_order_id = 999001;
  DELETE FROM f360.commerce_woo_orders WHERE target_id = tgt AND woo_order_id = 999001;
  IF (SELECT md5(string_agg(o::text, '|' ORDER BY woo_order_id)) FROM f360.commerce_woo_orders o WHERE target_id = tgt) <> facts_before THEN RAISE EXCEPTION 'R12 facts changed'; END IF;
  IF (SELECT jsonb_agg(m - 'adjustments') FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') m) <> cockpit_before THEN RAISE EXCEPTION 'R12 Growth original metrics changed'; END IF;
  -- R13 a review is flagged again when the source changes after it
  d := public.f360_rec_decide(tgt, 4115, 'no_se_concreto', 'prueba R13: no se pagó');
  UPDATE f360.commerce_woo_orders SET woo_status = 'cancelled' WHERE target_id = tgt AND woo_order_id = 4115;
  IF public.f360_rec_case(tgt, 4115)->>'rec_state' <> 'cambio_despues' THEN RAISE EXCEPTION 'R13'; END IF;
  -- R14 no personal or card data columns in the reconciliation tables
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'f360' AND table_name IN ('sales_rec_evidence', 'sales_rec_decisions', 'sales_rec_exclusions')
             AND column_name ~ '(email|phone|address|card|billing|customer|note)') THEN RAISE EXCEPTION 'R14'; END IF;
  -- R15 an order WooCommerce no longer has is evidence: paid + missing = financial discrepancy, and "venta confirmada" stays a conflict
  e2 := public.f360_rec_evidence_record(mario, 'woo_staging4', 4114, '{"woo_status":"no_existe","gateway_result":"order_missing"}');
  d := public.f360_rec_case(tgt, 4114);
  IF d->>'financial_state' <> 'NO_EXISTE_EN_WOO' OR NOT d->'flags' @> '[{"code":"NO_EXISTE_EN_WOO","kind":"financiera"}]' THEN RAISE EXCEPTION 'R15 %', d->'flags'; END IF;
  d := public.f360_rec_decide(tgt, 4114, 'venta_confirmada', 'prueba R15: confirmación humana', (e2->>'id')::bigint);
  IF d->>'rec_state' <> 'conflicto' THEN RAISE EXCEPTION 'R15 conflict %', d; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
