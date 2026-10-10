-- Conciliación → War Room exclusions — rolled-back checks (staging). Run: psql "$STAGING_DB_URL" -f supabase/staging/test_growth_exclusions.sql
BEGIN;
DO $$
DECLARE mario uuid := (SELECT auth_user_id FROM f360.user_roles WHERE display_name = 'Mario');
  -- someone who may open the War Room but is NOT a customer-data viewer (an operator, or an owner like Adrián)
  operator uuid := (SELECT r.auth_user_id FROM f360.user_roles r WHERE r.role IN ('operator', 'owner')
                    AND NOT EXISTS (SELECT 1 FROM f360.customer_pii_viewers v WHERE v.auth_user_id = r.auth_user_id) ORDER BY r.role = 'operator' DESC LIMIT 1);
  tgt uuid := (SELECT id FROM f360.sales_targets WHERE key = 'woo_staging4');
  base jsonb; d jsonb; a jsonb; b0 jsonb; paid_a bigint; paid_b bigint; rev_a numeric; rev_b numeric; units_a int; never bigint; rev_part numeric;
  -- one helper: the MX adjustment block of the full period
  q text := $q$ SELECT m->'adjustments' FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') m WHERE m->>'market' = 'MX' $q$;
BEGIN
  PERFORM set_config('request.jwt.claims', json_build_object('sub', mario, 'role', 'authenticated')::text, true);
  base := public.f360_growth_cockpit('2026-06-01', '2026-10-10');
  -- start every staging state from "no exclusions active" inside this transaction (example reviews may exist)
  INSERT INTO f360.sales_rec_exclusions (target_id, woo_order_id, action, reason, supersedes, decided_by, decided_by_name)
    SELECT s.target_id, s.woo_order_id, 'include', 'test: reset', (SELECT max(id) FROM f360.sales_rec_exclusions e WHERE e.target_id = s.target_id AND e.woo_order_id = s.woo_order_id), mario, 'test'
    FROM f360.sales_rec_analytics_scope s WHERE s.excluded;
  base := public.f360_growth_cockpit('2026-06-01', '2026-10-10');
  -- G1 original block = the War Room KPIs; nothing excluded → adjusted = original, in every market
  FOR d IN SELECT * FROM jsonb_array_elements(base->'markets') LOOP
    a := d->'adjustments';
    IF (a->'original'->>'revenue')::numeric <> (d->'kpis'->'revenue'->>'value')::numeric OR (a->'original'->>'paid_orders')::int <> (d->'kpis'->'paid_orders'->>'value')::int
       OR a->'adjusted' <> a->'original' OR (a->'excluded'->>'paid_orders')::int <> 0 THEN RAISE EXCEPTION 'G1 % %', d->>'market', a; END IF;
  END LOOP;
  EXECUTE q INTO b0;
  SELECT woo_order_id, net_product, units INTO paid_a, rev_a, units_a FROM f360.commerce_orders WHERE source_system = 'woo' AND market = 'MX' AND status_class = 'countable'
    AND occurred_at >= '2026-06-01'::timestamp AT TIME ZONE 'America/Mexico_City' ORDER BY woo_order_id LIMIT 1;
  SELECT woo_order_id, net_product INTO paid_b, rev_b FROM f360.commerce_orders WHERE source_system = 'woo' AND market = 'MX' AND status_class = 'countable'
    AND occurred_at >= '2026-06-01'::timestamp AT TIME ZONE 'America/Mexico_City' AND woo_order_id > paid_a ORDER BY woo_order_id LIMIT 1;
  -- G2 a human classification alone never excludes (prueba / duplicado still count, and are reported as such)
  PERFORM public.f360_rec_decide(tgt, paid_a, 'prueba', 'G2: clasificada como prueba, sin excluir');
  EXECUTE q INTO a;
  IF a->'adjusted' <> b0->'adjusted' OR (a->>'classified_not_excluded')::int <> (b0->>'classified_not_excluded')::int + 1 THEN RAISE EXCEPTION 'G2 %', a; END IF;
  -- G3 an explicit exclusion of a paid order subtracts it ONCE, separately; the original KPIs do not move
  PERFORM public.f360_rec_set_analytics(tgt, paid_a, true, 'G3: pedido de prueba');
  EXECUTE q INTO a;
  IF (a->'adjusted'->>'revenue')::numeric <> (b0->'original'->>'revenue')::numeric - rev_a OR (a->'adjusted'->>'paid_orders')::int <> (b0->'original'->>'paid_orders')::int - 1
     OR (a->'adjusted'->>'units')::int <> (b0->'original'->>'units')::int - units_a OR a->'original' <> b0->'original'
     OR (a->>'classified_not_excluded')::int <> (b0->>'classified_not_excluded')::int THEN RAISE EXCEPTION 'G3 %', a; END IF;
  IF (SELECT m->'kpis'->'revenue'->>'value' FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') m WHERE m->>'market' = 'MX')
     <> (SELECT m->'kpis'->'revenue'->>'value' FROM jsonb_array_elements(base->'markets') m WHERE m->>'market' = 'MX') THEN RAISE EXCEPTION 'G3 original KPI moved'; END IF;
  -- G4 no double count: excluding twice is refused; exclude → include → exclude subtracts once; include restores the original
  BEGIN PERFORM public.f360_rec_set_analytics(tgt, paid_a, true, 'G4: otra vez'); RAISE EXCEPTION 'G4 double'; EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'G4%' THEN RAISE; END IF; END;
  PERFORM public.f360_rec_set_analytics(tgt, paid_a, false, 'G4: se revierte');
  EXECUTE q INTO a;
  IF a->'adjusted' <> b0->'adjusted' THEN RAISE EXCEPTION 'G4 revert %', a; END IF;
  PERFORM public.f360_rec_set_analytics(tgt, paid_a, true, 'G4: se excluye de nuevo');
  EXECUTE q INTO a;
  IF (a->'adjusted'->>'paid_orders')::int <> (b0->'original'->>'paid_orders')::int - 1 THEN RAISE EXCEPTION 'G4 once %', a; END IF;
  -- G5 never-paid and paid-then-cancelled (reversed) orders already count 0: excluding them has no effect
  SELECT woo_order_id INTO never FROM f360.commerce_orders WHERE source_system = 'woo' AND market = 'MX' AND payment_state = 'never_paid'
    AND occurred_at >= '2026-06-01'::timestamp AT TIME ZONE 'America/Mexico_City' LIMIT 1;
  PERFORM public.f360_rec_set_analytics(tgt, never, true, 'G5: nunca pagado');
  IF NOT EXISTS (SELECT 1 FROM f360.sales_rec_analytics_scope WHERE target_id = tgt AND woo_order_id = 5351 AND excluded) THEN
    PERFORM public.f360_rec_set_analytics(tgt, 5351, true, 'G5: pagado y cancelado');
  END IF;
  EXECUTE q INTO a;
  IF (a->'adjusted'->>'paid_orders')::int <> (b0->'original'->>'paid_orders')::int - 1 OR (a->'excluded'->>'without_effect')::int < 2
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a->'detail') x WHERE (x->>'woo_order_id')::bigint = 5351 AND NOT (x->>'effective')::boolean AND x->>'why_no_effect' IS NOT NULL)
  THEN RAISE EXCEPTION 'G5 %', a; END IF;
  -- G6 partial refund: an excluded partially-refunded order subtracts its NET product (already net of the refund), never more
  INSERT INTO f360.commerce_woo_refunds (target_id, woo_order_id, woo_refund_id, amount, currency, refunded_at, detail_status, product_amount, provenance)
    VALUES (tgt, paid_b, 990001, 500, 'MXN', now(), 'detailed', 500, 'test');
  SELECT net_product INTO rev_part FROM f360.commerce_orders WHERE source_system = 'woo' AND target_id = tgt AND woo_order_id = paid_b;
  IF rev_part <> rev_b - 500 THEN RAISE EXCEPTION 'G6 fixture % %', rev_part, rev_b; END IF;
  EXECUTE q INTO b0;   -- new baseline: the partial refund already lowered the ORIGINAL revenue by 500
  PERFORM public.f360_rec_set_analytics(tgt, paid_b, true, 'G6: duplicado con reembolso parcial');
  EXECUTE q INTO a;
  IF (b0->'adjusted'->>'revenue')::numeric - (a->'adjusted'->>'revenue')::numeric <> rev_part THEN RAISE EXCEPTION 'G6 % vs %', b0->'adjusted', a->'adjusted'; END IF;
  -- G7 breakdown adds up: original − excluded = adjusted, in every market
  FOR d IN SELECT * FROM jsonb_array_elements(public.f360_growth_cockpit('2026-06-01', '2026-10-10')->'markets') LOOP
    a := d->'adjustments';
    IF (a->'original'->>'revenue')::numeric - (a->'excluded'->>'revenue')::numeric <> (a->'adjusted'->>'revenue')::numeric
       OR (a->'original'->>'paid_orders')::int - (a->'excluded'->>'paid_orders')::int <> (a->'adjusted'->>'paid_orders')::int
       OR (SELECT coalesce(sum((x->>'revenue_effect')::numeric), 0) FROM jsonb_array_elements(a->'detail') x) <> (a->'excluded'->>'revenue')::numeric
    THEN RAISE EXCEPTION 'G7 % %', d->>'market', a; END IF;
  END LOOP;
  -- G8 non-viewers (operator / owner without customer-data access) see the totals, never the order list / reasons
  IF operator IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', operator, 'role', 'authenticated')::text, true);
    EXECUTE q INTO a;
    IF a->'detail' <> 'null'::jsonb OR (a->'excluded'->>'paid_orders')::int < 2 THEN RAISE EXCEPTION 'G8 %', a; END IF;
  ELSE RAISE NOTICE 'G8: no non-viewer War Room user in staging (skipped)'; END IF;
  RAISE NOTICE 'ENSAYO OK';
END $$;
ROLLBACK;
