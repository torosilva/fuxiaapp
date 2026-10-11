-- I1a · presupuesto versionado, metas, costo estimado/confirmado, contadora (cierre + compromisos) — rolled-back checks (staging).
-- Run ONLY wrapped: psql "$STAGING_DB_URL" -v ON_ERROR_STOP=1 -f supabase/staging/test_intel_inputs.sql   (this file has BEGIN … ROLLBACK)
BEGIN;
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  caro uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'carolina.demo@staging.invalid');
  conta uuid; seller uuid; r jsonb; v1 uuid; v2 uuid; per uuid; e1 uuid; e2 uuid; c1 uuid; c2 uuid; prod uuid; g jsonb;
  as_ text;
BEGIN
  IF mario IS NULL OR caro IS NULL THEN RAISE EXCEPTION 'N0 fixtures'; END IF;
  -- this test controls the approval scopes it relies on
  DELETE FROM f360.approval_scopes WHERE scope IN ('budget', 'close');
  INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('budget', mario, 'Mario', 'test'), ('close', mario, 'Mario', 'test'), ('close', caro, 'Carolina', 'test');
  -- throw-away contadora (viewer + preparer) and seller, only inside this transaction
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-intel-conta@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO conta;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (conta, 'viewer', 'Contadora de prueba');
  INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, granted_by_name, evidence) VALUES (conta, 'Contadora de prueba', 'test', 'prueba');
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-intel-seller@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO seller;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (seller, 'seller', 'Vendedora de prueba');
  SELECT id INTO per FROM f360_board.fiscal_periods WHERE kind = 'MONTH' AND status IN ('OPEN', 'REOPENED') ORDER BY period_start LIMIT 1;

  -- N1 budget: Carolina drafts + validates; she cannot approve; Mario approves; frozen; a revision supersedes, the original stays
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_board_budget_draft(2027, 'Presupuesto 2027', 'Primer presupuesto por país y canal'); v1 := (r->>'id')::uuid;
  IF v1 IS NULL THEN RAISE EXCEPTION 'N1 draft %', r; END IF;
  r := public.f360_board_budget_lines_set(v1, '[{"month":"2027-01-01","market":"MX","channel":"online","amount":300000},{"month":"2027-01-01","market":"CO","channel":"online","amount":20000000},{"month":"2027-01-01","market":"MX","channel":"store","amount":450000}]');
  IF (r->>'lines')::int <> 3 THEN RAISE EXCEPTION 'N1 lines %', r; END IF;
  IF (public.f360_board_budget_lines_set(v1, '[{"month":"2026-12-01","market":"MX","channel":"online","amount":1}]'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N1 other year'; END IF;
  IF (public.f360_board_budget_lines_set(v1, '[{"month":"2027-01-01","market":"US","channel":"online","amount":1}]'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N1 market'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_board_budget_approve(v1))->>'error' NOT LIKE 'Falta la validación comercial%' THEN RAISE EXCEPTION 'N1 needs validation'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM public.f360_board_budget_validate(v1, 'Revisado con tiendas');
  IF (public.f360_board_budget_approve(v1))->>'error' NOT LIKE 'Solo quien aprueba presupuestos%' THEN RAISE EXCEPTION 'N1 Carolina cannot approve'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_board_budget_approve(v1))->>'ok' <> 'true' THEN RAISE EXCEPTION 'N1 approve'; END IF;
  IF (SELECT status FROM f360_board.budget_versions WHERE id = v1) <> 'APPROVED' OR (SELECT content_hash FROM f360_board.budget_versions WHERE id = v1) IS NULL THEN RAISE EXCEPTION 'N1 frozen'; END IF;
  IF (public.f360_board_budget_lines_set(v1, '[]'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N1 approved lines locked'; END IF;
  r := public.f360_board_budget_draft(2027, 'Presupuesto 2027 rev. 1', 'Ajuste Colombia por tipo de cambio', v1); v2 := (r->>'id')::uuid;
  IF (SELECT count(*) FROM f360_board.budget_lines WHERE version_id = v2) <> 3 THEN RAISE EXCEPTION 'N1 copy'; END IF;
  PERFORM public.f360_board_budget_lines_set(v2, '[{"month":"2027-01-01","market":"MX","channel":"online","amount":320000}]');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM public.f360_board_budget_validate(v2);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM public.f360_board_budget_approve(v2);
  IF (SELECT status FROM f360_board.budget_versions WHERE id = v1) <> 'SUPERSEDED' OR (SELECT count(*) FROM f360_board.budget_lines WHERE version_id = v1) <> 3
     OR (SELECT change_reason FROM f360_board.budget_versions WHERE id = v2) <> 'Ajuste Colombia por tipo de cambio' OR (SELECT supersedes_id FROM f360_board.budget_versions WHERE id = v2) <> v1
     THEN RAISE EXCEPTION 'N1 revision'; END IF;
  -- without second factor the board refuses
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  IF (public.f360_board_budgets(2027))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N1 mfa'; END IF;

  -- N2 goals: Mario registers $300,000 MXN ecommerce MX; Carolina cannot; a change is a new version
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_board_goal_set('ecommerce_mx_mensual', 'Ecommerce México', 'MX', 'online', 300000, '2026-10-01', 'Mario 2026-10-11: meta mensual de $300,000 MXN');
  IF r->>'ok' <> 'true' THEN RAISE EXCEPTION 'N2 %', r; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_board_goal_set('ecommerce_mx_mensual', 'x', 'MX', 'online', 1, '2026-10-01', 'intento'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N2 caro'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  PERFORM public.f360_board_goal_set('ecommerce_mx_mensual', 'Ecommerce México', 'MX', 'online', 350000, '2027-01-01', 'Prueba: meta 2027');
  IF (f360_board.goal_for('ecommerce_mx_mensual', '2026-11-15')).amount <> 300000 OR (f360_board.goal_for('ecommerce_mx_mensual', '2027-02-01')).amount <> 350000
     OR (f360_board.goal_for('ecommerce_mx_mensual', '2026-09-01')).id IS NOT NULL THEN RAISE EXCEPTION 'N2 goal_for'; END IF;
  BEGIN UPDATE f360_board.goals SET amount = 1; RAISE EXCEPTION 'N2 update'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'N2%' THEN RAISE; END IF; END;

  -- N3 cost basis: an estimate is "estimated", an invoice is "confirmed" (derived, never typed)
  SELECT id INTO prod FROM f360.products ORDER BY created_at LIMIT 1;
  r := public.f360_product_cost_propose(prod, NULL, 'MX', 450, 'MXN', '2026-10-01', 'owner_estimate', 'estimado de Carolina');
  IF (SELECT cost_basis FROM f360.product_cost_versions WHERE id = (r->>'id')::uuid) <> 'estimated' THEN RAISE EXCEPTION 'N3 estimated'; END IF;
  r := public.f360_product_cost_propose(prod, NULL, 'MX', 470, 'MXN', '2026-10-02', 'supplier_invoice', 'factura');
  IF (SELECT cost_basis FROM f360.product_cost_versions WHERE id = (r->>'id')::uuid) <> 'confirmed' THEN RAISE EXCEPTION 'N3 confirmed'; END IF;

  -- N4 contadora: captures / voids her own close amounts in an OPEN month; cannot approve; Carolina approves; no strategy, no PII
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_close_prep_context(); IF r->>'ok' <> 'true' OR jsonb_array_length(r->'accounts') < 5 THEN RAISE EXCEPTION 'N4 context %', left(r::text, 200); END IF;
  r := public.f360_close_prep_entry_add(gen_random_uuid(), per, 'cash_bank', 125000.50, 'MXN', 'estado de cuenta BBVA', 'BBVA-sep.pdf'); e1 := (r->>'id')::uuid;
  r := public.f360_close_prep_entry_add(gen_random_uuid(), per, 'opex_rent', 38000, 'MXN', 'contrato de renta Polanco'); e2 := (r->>'id')::uuid;
  IF e1 IS NULL OR e2 IS NULL OR (SELECT captured_by FROM f360_board.monthly_close_entries WHERE id = e1) <> conta THEN RAISE EXCEPTION 'N4 add %', r; END IF;
  IF (public.f360_close_prep_entry_void(e2, 'capturé el mes equivocado'))->>'ok' <> 'true' THEN RAISE EXCEPTION 'N4 void own'; END IF;
  IF (public.f360_board_close_entries_approve(per))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 conta cannot approve'; END IF;
  IF (public.f360_board_plans())->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 no strategy'; END IF;
  IF (public.f360_board_budgets(2027))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 no budget without can_budget'; END IF;
  BEGIN PERFORM public.f360_rec_list(); RAISE EXCEPTION 'N4 pii'; EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN IF SQLERRM LIKE 'N4%' THEN RAISE; END IF; END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  IF (public.f360_close_prep_context())->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 mfa'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_board_close_entries_approve(per);
  IF (r->>'approved')::int < 1 OR (SELECT approved_by FROM f360_board.monthly_close_entries WHERE id = e1) <> caro THEN RAISE EXCEPTION 'N4 approve %', r; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_close_prep_entry_void(e1, 'ya aprobado, no debe dejar'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 approved locked'; END IF;
  -- seller: nothing
  PERFORM set_config('request.jwt.claims', json_build_object('sub', seller, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_close_prep_context())->>'ok' <> 'false' OR (public.f360_finance_commitment_add('renta', 'x', NULL, '2026-11-01', 1, 'MXN', 'una_vez', 'xxx'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N4 seller'; END IF;

  -- N5 commitments: contadora captures and corrects (reason, new row); she cannot approve; Carolina approves; paid with reason; immutable
  PERFORM set_config('request.jwt.claims', json_build_object('sub', conta, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  r := public.f360_finance_commitment_add('produccion', 'Taller León', 'Lote de 300 pares', '2026-11-15', 90000, 'MXN', 'una_vez', 'orden de producción OP-12'); c1 := (r->>'id')::uuid;
  r := public.f360_finance_commitment_add('produccion', 'Taller León', 'Lote de 300 pares', '2026-11-20', 92000, 'MXN', 'una_vez', 'orden de producción OP-12 (ajuste)', NULL, c1, 'el taller cambió la fecha y el precio'); c2 := (r->>'id')::uuid;
  IF (SELECT state FROM f360_board.commitments_current WHERE id = c1) <> 'corregido' OR (SELECT state FROM f360_board.commitments_current WHERE id = c2) <> 'pendiente' THEN RAISE EXCEPTION 'N5 correct'; END IF;
  IF (public.f360_finance_commitment_event(c2, 'approved'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N5 conta approve'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', caro, 'role', 'authenticated', 'aal', 'aal2')::text, true);
  IF (public.f360_finance_commitment_event(c2, 'approved'))->>'ok' <> 'true' OR (SELECT approved_by_name FROM f360_board.commitments_current WHERE id = c2) <> 'Carolina' THEN RAISE EXCEPTION 'N5 approve'; END IF;
  IF (public.f360_finance_commitment_event(c2, 'paid'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'N5 paid needs reason'; END IF;
  PERFORM public.f360_finance_commitment_event(c2, 'paid', 'transferencia SPEI 20/11');
  IF (SELECT state FROM f360_board.commitments_current WHERE id = c2) <> 'pagado' THEN RAISE EXCEPTION 'N5 paid'; END IF;
  BEGIN UPDATE f360_board.financial_commitments SET amount = 1 WHERE id = c2; RAISE EXCEPTION 'N5 update'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'N5%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360_board.financial_commitment_events; RAISE EXCEPTION 'N5 delete'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'N5%' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM f360_board.access_log WHERE auth_user_id = conta AND rpc LIKE 'f360_%' AND outcome IN ('allowed', 'write')) < 5 THEN RAISE EXCEPTION 'N5 audit'; END IF;

  -- N6 grants
  IF has_function_privilege('anon', 'public.f360_close_prep_context()', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_board_goal_set(text,text,text,text,numeric,date,text)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'f360_board.goals', 'SELECT') OR has_table_privilege('authenticated', 'f360_board.financial_commitments', 'INSERT')
     OR has_table_privilege('authenticated', 'f360_board.finance_preparers', 'SELECT') THEN RAISE EXCEPTION 'N6 grants'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
