-- Currency corrections (#2095) — rolled-back checks (staging). Run: psql "$STAGING_DB_URL" -f supabase/staging/test_currency_corrections.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE display_name = 'Mario');
  owner_np uuid := (SELECT r.auth_user_id FROM f360.user_roles r WHERE r.role = 'owner' AND NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers v WHERE v.auth_user_id = r.auth_user_id) LIMIT 1);
  seller uuid := (SELECT auth_user_id FROM f360.user_roles WHERE role = 'seller' LIMIT 1);
  tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  src_before text; base jsonb; d jsonb; c jsonb; r jsonb; who uuid; n int;
  mk text := $q$ SELECT m FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') m WHERE m->>'market' = $1 $q$;
  co0 jsonb; row0 jsonb; co1 jsonb; row1 jsonb;
BEGIN
  SELECT md5(o::text) INTO src_before FROM f360.commerce_woo_orders o WHERE target_id = tgt AND woo_order_id = 2095;
  IF src_before IS NULL THEN RAISE EXCEPTION 'K0 fixture #2095 missing'; END IF;
  -- start from "no active correction" inside this transaction
  IF EXISTS (SELECT 1 FROM f360.commerce_currency_scope WHERE target_id = tgt AND woo_order_id = 2095 AND active) THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
    PERFORM public.f360_rec_correct_currency(tgt, 2095, NULL, 'test: reset al estado de la fuente', true);
  END IF;
  -- K1 only Carolina & Mario
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'COP', 'intento anónimo de corrección'); RAISE EXCEPTION 'K1 anon'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  FOREACH who IN ARRAY array_remove(ARRAY[seller, owner_np], NULL) LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', who, 'role', 'authenticated')::text, true);
    BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'COP', 'intento sin permiso de corrección'); RAISE EXCEPTION 'K1 %', who; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  IF has_table_privilege('authenticated', 'f360.commerce_currency_corrections', 'INSERT') THEN RAISE EXCEPTION 'K1 table grant'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  -- K2 the alert finds #2095 (billing CO + USD + price out of USD range) and ONLY #2095 in staging
  c := public.f360_rec_case(tgt, 2095);
  IF NOT c->'flags' @> '[{"code":"MONEDA_SOSPECHOSA","kind":"revision"}]' OR c->>'market' <> 'ROW' OR c->>'currency' <> 'USD' THEN RAISE EXCEPTION 'K2 %', c->'flags'; END IF;
  SELECT count(*) INTO n FROM f360.sales_rec_cases WHERE flags @> '[{"code":"MONEDA_SOSPECHOSA"}]' AND woo_order_id <> 2095;
  IF n <> 0 THEN RAISE EXCEPTION 'K2 other suspicious orders: %', n; END IF;
  EXECUTE mk INTO co0 USING 'CO'; EXECUTE mk INTO row0 USING 'ROW';
  -- K3 validation: reason, currency, nothing to correct
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'COP', 'corto'); RAISE EXCEPTION 'K3 reason'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'EUR', 'moneda que no existe aquí'); RAISE EXCEPTION 'K3 currency'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'USD', 'ya está en dólares en la fuente'); RAISE EXCEPTION 'K3 same'; EXCEPTION WHEN check_violation THEN NULL; END;
  -- K4 correct #2095 → COP / CO; the source record is untouched (USD 405,000, cancelled, never paid)
  r := public.f360_rec_correct_currency(tgt, 2095, 'COP', 'Mario 2026-10-10: el pedido es COP 405,000 (factura en Colombia, precio colombiano).');
  IF r->>'currency' <> 'COP' OR r->>'market' <> 'CO' OR r->>'woo_currency' <> 'USD' THEN RAISE EXCEPTION 'K4 %', r; END IF;
  IF (SELECT md5(o::text) FROM f360.commerce_woo_orders o WHERE target_id = tgt AND woo_order_id = 2095) <> src_before THEN RAISE EXCEPTION 'K4 source changed'; END IF;
  IF (SELECT currency_original FROM f360.commerce_orders WHERE target_id = tgt AND woo_order_id = 2095) <> 'USD' THEN RAISE EXCEPTION 'K4 commerce_orders changed'; END IF;
  -- K5 Conciliación shows CO / COP, the correction (original vs corrected), no "sospechosa", and the payment state unchanged
  c := public.f360_rec_case(tgt, 2095);
  IF c->>'market' <> 'CO' OR c->>'currency' <> 'COP' OR (c->>'order_total')::numeric <> 405000 OR c->>'financial_state' <> 'SIN_COBRO'
     OR NOT c->'flags' @> '[{"code":"MONEDA_CORREGIDA"}]' OR c->'flags' @> '[{"code":"MONEDA_SOSPECHOSA"}]'
     OR c->'currency_correction'->>'woo_currency' <> 'USD' OR c->'currency_correction'->>'currency' <> 'COP' THEN RAISE EXCEPTION 'K5 %', c; END IF;
  -- K6 War Room: the order moves from ROW to CO (created / never paid); paid revenue in both markets unchanged (it was never paid)
  EXECUTE mk INTO co1 USING 'CO'; EXECUTE mk INTO row1 USING 'ROW';
  IF (co1->'checkout'->>'created')::int <> (co0->'checkout'->>'created')::int + 1 OR (row1->'checkout'->>'created')::int <> (row0->'checkout'->>'created')::int - 1
     OR (co1->'checkout'->>'never_paid')::int <> (co0->'checkout'->>'never_paid')::int + 1
     OR co1->'kpis'->'revenue'->'value' <> co0->'kpis'->'revenue'->'value' OR row1->'kpis'->'revenue'->'value' <> row0->'kpis'->'revenue'->'value'
     OR co1->'kpis'->'paid_orders'->'value' <> co0->'kpis'->'paid_orders'->'value'
     OR (co1->'adjustments'->'currency_corrections'->>'count')::int <> 1
     OR co1->'adjustments'->'currency_corrections'->'detail'->0->>'woo_currency' <> 'USD' THEN RAISE EXCEPTION 'K6 CO % ROW %', co1->'checkout', row1->'checkout'; END IF;
  -- K7 append-only; no double correction; revert is a new event and restores the source view
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, 'COP', 'otra vez la misma corrección'); RAISE EXCEPTION 'K7 double'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN UPDATE f360.commerce_currency_corrections SET corrected_currency = 'MXN', corrected_market = 'MX'; RAISE EXCEPTION 'K7 update'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'K7%' THEN RAISE; END IF; END;
  BEGIN DELETE FROM f360.commerce_currency_corrections; RAISE EXCEPTION 'K7 delete'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'K7%' THEN RAISE; END IF; END;
  r := public.f360_rec_correct_currency(tgt, 2095, NULL, 'Prueba de reversión de la corrección', true);
  EXECUTE mk INTO co1 USING 'CO';
  IF (co1->'checkout'->>'created')::int <> (co0->'checkout'->>'created')::int OR public.f360_rec_case(tgt, 2095)->>'currency' <> 'USD' THEN RAISE EXCEPTION 'K7 revert'; END IF;
  BEGIN PERFORM public.f360_rec_correct_currency(tgt, 2095, NULL, 'revertir algo que ya no está activo', true); RAISE EXCEPTION 'K7 revert twice'; EXCEPTION WHEN check_violation THEN NULL; END;
  -- K8 evidence is captured by the server (not the client)
  IF NOT EXISTS (SELECT 1 FROM f360.commerce_currency_corrections WHERE target_id = tgt AND woo_order_id = 2095 AND action = 'correct'
                 AND evidence->>'billing_country' = 'CO' AND (evidence->>'max_unit_price')::numeric = 380000 AND evidence->>'woo_currency' = 'USD'
                 AND evidence->>'suspicion' IS NOT NULL) THEN RAISE EXCEPTION 'K8 evidence'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
