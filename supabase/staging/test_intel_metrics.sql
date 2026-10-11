-- I1b · capa de métricas del Centro de Inteligencia — rolled-back checks (staging). Run ONLY as a whole file (BEGIN … ROLLBACK).
BEGIN;
DO $$
DECLARE mario uuid := (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid');
  seller uuid; conta uuid; r jsonb; d jsonb; n numeric; m numeric; x jsonb; u uuid; v uuid; today date := (now() AT TIME ZONE 'America/Mexico_City')::date;
  claims_m text := json_build_object('sub', (SELECT u.id FROM auth.users u JOIN f360.user_roles r ON r.auth_user_id = u.id AND r.role = 'owner' WHERE u.email = 'mario.demo@staging.invalid'), 'role', 'authenticated', 'aal', 'aal2')::text;
BEGIN
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-intel-m-seller@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO seller;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (seller, 'seller', 'Vendedora de prueba');
  INSERT INTO auth.users (id, email, aud, role) VALUES (gen_random_uuid(), 'zz-intel-m-conta@staging.invalid', 'authenticated', 'authenticated') RETURNING id INTO conta;
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (conta, 'viewer', 'Contadora de prueba');
  INSERT INTO f360_board.finance_preparers (auth_user_id, display_name, granted_by_name, evidence) VALUES (conta, 'Contadora de prueba', 'test', 'prueba');

  -- M1 gate: seller, contadora, Mario without second factor → denied; Mario with aal2 → allowed; analyst calls logged as ai_analyst
  FOREACH u IN ARRAY ARRAY[seller, conta] LOOP
    PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    IF (public.f360_intel_cockpit())->>'ok' <> 'false' OR (public.f360_intel_query('ventas', '{}'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'M1 %', u; END IF;
  END LOOP;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated', 'aal', 'aal1')::text, true);
  IF (public.f360_intel_query('ventas', '{}'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'M1 mfa'; END IF;
  PERFORM set_config('request.jwt.claims', claims_m, true);
  PERFORM set_config('request.headers', '{"x-f360-actor":"ai_analyst"}', true);
  IF (public.f360_intel_query('fuentes', '{}'))->>'ok' <> 'true' THEN RAISE EXCEPTION 'M1 ok'; END IF;
  IF (SELECT actor_kind FROM f360_board.access_log WHERE auth_user_id = mario ORDER BY id DESC LIMIT 1) <> 'ai_analyst' THEN RAISE EXCEPTION 'M1 actor'; END IF;
  PERFORM set_config('request.headers', '{}', true);

  -- M2 the analyst cannot send SQL or unknown tools; ranges are bounded
  IF (public.f360_intel_query('select * from auth.users', '{}'))->>'error' <> 'Herramienta no disponible.' THEN RAISE EXCEPTION 'M2 sql'; END IF;
  IF (public.f360_intel_query('ventas', '{"desde":"ayer"}'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'M2 date'; END IF;
  IF (public.f360_intel_query('ventas', '{"desde":"2019-01-01","hasta":"2026-01-01"}'))->>'ok' <> 'false' THEN RAISE EXCEPTION 'M2 range'; END IF;

  -- M3 sales: rows add up to the source (countable, net product), foreign-environment events excluded, exclusions shown apart
  r := public.f360_intel_query('ventas', '{"desde":"2026-06-01","hasta":"2026-10-11"}');
  SELECT sum((e->>'venta_neta')::numeric) INTO n FROM jsonb_array_elements(r->'data'->'por_mercado_canal') e WHERE e->>'mercado' = 'MX';
  SELECT coalesce(sum(o.net_product), 0) INTO m FROM f360.commerce_orders_reporting o
    WHERE o.market_reporting = 'MX' AND o.status_class = 'countable' AND (o.occurred_at AT TIME ZONE 'America/Mexico_City')::date BETWEEN '2026-06-01' AND '2026-10-11'
      AND NOT EXISTS (SELECT 1 FROM f360.environment_foreign_events fe WHERE fe.target_id = o.target_id AND fe.woo_order_id = o.woo_order_id);
  IF n IS DISTINCT FROM m THEN RAISE EXCEPTION 'M3 MX % vs %', n, m; END IF;
  IF EXISTS (SELECT 1 FROM f360.environment_foreign_events fe JOIN f360.intel_orders('2026-06-01', '2026-10-11') o ON o.woo_order_id = fe.woo_order_id AND o.target_id = fe.target_id)
    THEN RAISE EXCEPTION 'M3 foreign included'; END IF;
  IF r->'meta'->>'disponibilidad' NOT IN ('DISPONIBLE', 'PARCIAL') OR r->'meta'->'periodo'->>'desde' <> '2026-06-01' OR r->'meta'->>'actualizado_al' IS NULL THEN RAISE EXCEPTION 'M3 meta %', r->'meta'; END IF;

  -- M4 MXN consolidation only with approved rates: none approved for June → null + listed; approve June (Mario) → value = Σ amount × rate
  r := public.f360_intel_query('ventas', '{"desde":"2026-08-01","hasta":"2026-08-31"}');
  IF NOT EXISTS (SELECT 1 FROM f360.fx_rates WHERE period = '2026-08-01' AND status = 'approved') THEN
    IF r->'data'->'consolidado_mxn'->>'mxn' IS NOT NULL OR jsonb_array_length(r->'data'->'consolidado_mxn'->'sin_tasa') = 0 THEN RAISE EXCEPTION 'M4 no rate %', r->'data'->'consolidado_mxn'; END IF;
    INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('fx_rate', mario, 'Mario', 'test') ON CONFLICT DO NOTHING;
    FOR u IN SELECT fr.id FROM f360.fx_rates fr WHERE fr.period = '2026-08-01' AND fr.status = 'proposed' LOOP PERFORM public.f360_fx_rate_approve(u); END LOOP;
  END IF;
  r := public.f360_intel_query('ventas', '{"desde":"2026-08-01","hasta":"2026-08-31"}');
  SELECT sum(amt * (SELECT rate FROM f360.fx_rates WHERE currency = q.cur AND period = '2026-08-01' AND status = 'approved')) + coalesce(sum(amt) FILTER (WHERE cur = 'MXN'), 0)
    INTO n FROM (SELECT currency cur, sum(net_product) amt FROM f360.intel_orders('2026-08-01', '2026-08-31') WHERE status_class = 'countable' AND NOT suspicious_currency GROUP BY 1) q;
  IF (r->'data'->'consolidado_mxn'->>'mxn')::numeric IS DISTINCT FROM round(n, 2) THEN RAISE EXCEPTION 'M4 mxn % vs %', r->'data'->'consolidado_mxn', n; END IF;

  -- M5 goal progress (the registered $300k) — fact + calculation, never a forecast
  r := public.f360_intel_query('avance_meta', '{"meta":"ecommerce_mx_mensual"}');
  IF (r->'data'->>'meta')::numeric <> 300000 OR (r->'data'->>'faltante')::numeric <> greatest(0, 300000 - (r->'data'->>'real_al_dia')::numeric) THEN RAISE EXCEPTION 'M5 %', r->'data'; END IF;
  r := public.f360_intel_query('avance_meta', '{"meta":"no_existe"}');
  IF r->'meta'->>'disponibilidad' <> 'FALTA' OR r->'data' <> 'null'::jsonb THEN RAISE EXCEPTION 'M5 missing goal'; END IF;

  -- M6 budget: without an approved version → FALTA; with one → compliance per market/channel (prorated by days)
  IF NOT EXISTS (SELECT 1 FROM f360_board.budget_versions WHERE status = 'APPROVED' AND fiscal_year = 2026) THEN
    IF (public.f360_intel_query('presupuesto_vs_real', '{"desde":"2026-08-01","hasta":"2026-08-31"}'))->'meta'->>'disponibilidad' <> 'FALTA' THEN RAISE EXCEPTION 'M6 falta'; END IF;
    INSERT INTO f360.approval_scopes (scope, auth_user_id, display_name, added_by_name) VALUES ('budget', mario, 'Mario', 'test') ON CONFLICT DO NOTHING;
    v := (public.f360_board_budget_draft(2026, 'Prueba', 'prueba de la capa de métricas')->>'id')::uuid;
    PERFORM public.f360_board_budget_lines_set(v, '[{"month":"2026-08-01","market":"MX","channel":"online","amount":62000}]');
    PERFORM public.f360_board_budget_validate(v); PERFORM public.f360_board_budget_approve(v);
  END IF;
  r := public.f360_intel_query('presupuesto_vs_real', '{"desde":"2026-08-01","hasta":"2026-08-15"}');
  x := (SELECT y FROM jsonb_array_elements(r->'data'->'lineas') y WHERE y->>'mercado' = 'MX' AND y->>'canal' = 'online');
  IF x IS NULL OR (x->>'presupuesto')::numeric <> round(62000 * 15 / 31.0, 2) THEN RAISE EXCEPTION 'M6 prorate %', r->'data'; END IF;

  -- M7 no invented numbers: margin and cash say FALTA (no costs / no approved close), funnel visits FALTA
  r := public.f360_intel_query('margen', '{"desde":"2026-08-01","hasta":"2026-08-31"}');
  IF r->'meta'->>'disponibilidad' <> 'FALTA' OR r->'data' ? 'margen' THEN RAISE EXCEPTION 'M7 margin %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM f360_board.monthly_close_entries WHERE approved_by IS NOT NULL) AND (public.f360_intel_query('caja', '{"mes":"2026-09-01"}'))->'meta'->>'disponibilidad' <> 'FALTA' THEN RAISE EXCEPTION 'M7 cash'; END IF;
  r := public.f360_intel_query('embudo', '{"desde":"2026-08-01","hasta":"2026-08-31"}');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'data'->'por_mercado') mk, jsonb_array_elements(mk->'etapas') e WHERE e->>'etapa' = 'Visitas' AND e->'valor' <> 'null'::jsonb) THEN RAISE EXCEPTION 'M7 visits'; END IF;
  r := public.f360_intel_query('marketing', '{"desde":"2026-08-01","hasta":"2026-08-31"}');
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'data'->'por_mercado') mk WHERE mk->'roas_atribuido'->'valor' <> 'null'::jsonb) THEN RAISE EXCEPTION 'M7 roas'; END IF;

  -- M8 inventory total = live ledger (active, non-transit locations)
  r := public.f360_intel_query('inventario_mx', '{"dias":60}');
  SELECT coalesce(sum(b.on_hand), 0) INTO n FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id WHERE l.status = 'active' AND l.type <> 'transit';
  IF (r->'data'->>'pares_total')::numeric <> n THEN RAISE EXCEPTION 'M8 % vs %', r->'data'->'pares_total', n; END IF;

  -- M9 cockpit: 8 cards, every card carries meta with availability
  r := public.f360_intel_cockpit(today);
  IF jsonb_array_length(r->'tarjetas') <> 8 THEN RAISE EXCEPTION 'M9 cards'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(r->'tarjetas') c WHERE coalesce(c->'valor'->'meta'->>'disponibilidad', c->'mes'->'meta'->>'disponibilidad') IS NULL) THEN RAISE EXCEPTION 'M9 meta'; END IF;
  r := public.f360_intel_query('senales_semana', jsonb_build_object('desde', today - 6, 'hasta', today));
  IF r->>'ok' <> 'true' OR jsonb_typeof(r->'data'->'senales') <> 'array' THEN RAISE EXCEPTION 'M9 signals'; END IF;

  -- M10 grants: cores are never callable directly
  IF has_function_privilege('authenticated', 'f360.intel_sales_core(date,date)', 'EXECUTE') OR has_function_privilege('authenticated', 'f360.intel_orders(date,date)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.f360_intel_query(text,jsonb)', 'EXECUTE') OR has_function_privilege('anon', 'public.f360_intel_cockpit(date)', 'EXECUTE')
     THEN RAISE EXCEPTION 'M10 grants'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
