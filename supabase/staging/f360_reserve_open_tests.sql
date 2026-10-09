-- "Apártalas 3 horas" for every customer with a WhatsApp code (20261020000200) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_sql text, p_role text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('role', p_role)::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;

DO $$
DECLARE loc uuid; v uuid; v2 uuid; v3 uuid; r jsonb; code text; ph text := '+525599990001'; cid uuid; n int; exp timestamptz;
BEGIN
  -- fixture: a selling store with free pairs of three sizes
  SELECT b.location_id, b.variant_id INTO loc, v FROM f360.inventory_balances b JOIN f360.locations l ON l.id = b.location_id
    WHERE l.type = 'store' AND l.sellable AND l.status = 'active' AND l.ledger_authority = 'f360' AND NOT f360.location_in_cutover(l.id)
      AND b.on_hand - f360.reserved_qty(b.variant_id, b.location_id) >= 1 LIMIT 1;
  SELECT b.variant_id INTO v2 FROM f360.inventory_balances b WHERE b.location_id = loc AND b.variant_id <> v AND b.on_hand - f360.reserved_qty(b.variant_id, loc) >= 1 LIMIT 1;
  SELECT b.variant_id INTO v3 FROM f360.inventory_balances b WHERE b.location_id = loc AND b.variant_id NOT IN (v, v2) AND b.on_hand - f360.reserved_qty(b.variant_id, loc) >= 1 LIMIT 1;
  PERFORM pg_temp.ok(loc IS NOT NULL AND v IS NOT NULL AND v2 IS NOT NULL AND v3 IS NOT NULL, 'fixture: store with 3 free sizes', coalesce(loc::text, 'none'));
  DELETE FROM public.customers WHERE phone = ph;

  -- security: anon / authenticated cannot issue codes, reserve with code, or read the codes table
  r := pg_temp.as(format($q$SELECT public.f360_reserve_code_issue(%L)$q$, ph), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot issue a code', r::text);
  r := pg_temp.as(format($q$SELECT public.f360_reserve_with_code(%L, '123456', 'X', %L::uuid, %L::uuid)$q$, ph, loc, v), 'authenticated');
  PERFORM pg_temp.ok(r ? 'error', 'authenticated cannot reserve with a code', r::text);
  r := pg_temp.as($q$SELECT to_jsonb(count(*)) FROM f360.reserve_codes$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read the codes table', r::text);

  -- code issue: normalized phone, 6 digits, stored hashed
  r := public.f360_reserve_code_issue('55 9999 0001');
  code := r->>'code';
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'phone' = ph AND code ~ '^[0-9]{6}$', 'code issued for a 10-digit MX number', r->>'phone');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.reserve_codes WHERE phone = ph AND code_hash = code), 'code stored hashed, not in clear', '');

  -- wrong code: refused, counts an attempt, nothing created
  r := public.f360_reserve_with_code(ph, '000000', 'Lucía Prueba', loc, v);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%no es correcto%', 'wrong code refused', r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.customers WHERE phone = ph), 'wrong code creates no customer', '');

  -- new customer without a name: refused
  r := public.f360_reserve_with_code(ph, code, '', loc, v);
  PERFORM pg_temp.ok(r->>'error' = 'Escribe tu nombre.', 'new customer needs a name', r::text);

  -- right code: registers her (not Gold), holds 3 hours
  r := public.f360_reserve_with_code(ph, code, 'Lucía Prueba', loc, v);
  SELECT id INTO cid FROM public.customers WHERE phone = ph;
  exp := (r->'reservation'->>'expires_at')::timestamptz;
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (r->>'created')::boolean AND r->>'first_name' = 'Lucía', 'any customer can reserve; she is registered', left(r::text, 160));
  PERFORM pg_temp.ok(exp BETWEEN clock_timestamp() + interval '2 hours 59 minutes' AND clock_timestamp() + interval '3 hours 1 minute', 'hold lasts 3 hours', exp::text);
  PERFORM pg_temp.ok((SELECT source FROM public.customers WHERE id = cid) = 'woo' AND EXISTS (SELECT 1 FROM public.loyalty_cards WHERE customer_id = cid AND tier = 'bronze'),
    'registered as online customer with a bronze card', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.customer_consent_events WHERE customer_id = cid AND purpose_key = 'privacy_notice' AND status = 'requested' AND source = 'web'),
    'privacy notice requested (web)', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.reservations WHERE customer_id = cid AND channel = 'web' AND status = 'activa'), 'reservation recorded (web)', '');

  -- the code is one-time
  r := public.f360_reserve_with_code(ph, code, 'Lucía Prueba', loc, v2);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean, 'a used code cannot be reused', r::text);

  -- second pair with a new code: ok (existing customer, no new row); third pair: refused (max 2)
  code := public.f360_reserve_code_issue(ph)->>'code';
  r := public.f360_reserve_with_code(ph, code, '', loc, v2);
  PERFORM pg_temp.ok((r->>'ok')::boolean AND NOT (r->>'created')::boolean, 'existing customer reserves a 2nd pair without a name', left(r::text, 120));
  code := public.f360_reserve_code_issue(ph)->>'code';
  BEGIN
    r := public.f360_reserve_with_code(ph, code, '', loc, v3);
    PERFORM pg_temp.ok(false, 'max 2 pairs', r::text);
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(SQLERRM LIKE '%2 pares apartados%', 'max 2 pairs', SQLERRM); END;
  PERFORM pg_temp.ok((SELECT count(*) FROM public.customers WHERE phone = ph) = 1, 'never a duplicate customer', '');

  -- rate limit: 3 codes per 10 minutes (3 already issued above)
  r := public.f360_reserve_code_issue(ph);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%3 códigos%', 'max 3 codes per 10 minutes', r::text);

  -- 5 wrong attempts lock the code
  DELETE FROM f360.reserve_codes WHERE phone = '+525599990002';
  code := public.f360_reserve_code_issue('+525599990002')->>'code';
  FOR n IN 1..5 LOOP PERFORM public.f360_reserve_with_code('+525599990002', '999999', 'Ana', loc, v3); END LOOP;
  r := public.f360_reserve_with_code('+525599990002', code, 'Ana', loc, v3);
  PERFORM pg_temp.ok(r->>'error' LIKE '%Demasiados intentos%', 'code locked after 5 wrong attempts', r::text);

  -- availability resolves the size even though the channel is inactive
  r := public.f360_store_availability(NULL, (SELECT woo_variation_id FROM f360.woo_variant_links WHERE variant_id = v LIMIT 1)::int);
  PERFORM pg_temp.ok(r->>'variant_id' IS NOT NULL OR NOT EXISTS (SELECT 1 FROM f360.woo_variant_links WHERE variant_id = v), 'availability works with the channel inactive', left(r::text, 120));
END $$;

SELECT status, name, detail FROM t_results ORDER BY n;
SELECT count(*) FILTER (WHERE status = 'PASS') AS pass, count(*) FILTER (WHERE status = 'FAIL') AS fail FROM t_results;
ROLLBACK;
