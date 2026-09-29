-- S0.3 BEFORE/AFTER probe (STAGING, ROLLED BACK). Records what each path ACCEPTS; not a pass/fail suite.
-- BEFORE = the legacy client path the current app uses (direct table writes, app/vendedora/sale.tsx:160-199).
-- AFTER  = public.f360_record_store_sale (S0.3). Both exist today until the S0.3c cutover.
BEGIN;
CREATE TEMP TABLE t_probe (n serial, path text, probe text, outcome text) ON COMMIT DROP;
GRANT ALL ON t_probe TO authenticated, anon; GRANT USAGE, SELECT ON SEQUENCE t_probe_n_seq TO authenticated, anon;
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS s1 FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.carolina', :'carolina', true), set_config('t.s1', :'s1', true) \gset t_
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid, t text) ON COMMIT DROP; GRANT ALL ON t_ids TO authenticated, anon;
DO $$ DECLARE ch uuid; loc jsonb; tok jsonb; u uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; BEGIN
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ Canal probe', 'store', true) RETURNING id INTO ch;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch, 'ZZ Probe', '37', 'Negro', 2800, 1, 0) RETURNING id) INSERT INTO t_ids SELECT 'row', id, NULL FROM x;
  INSERT INTO t_ids VALUES ('ch', ch, NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
  loc := public.f360_create_location('ZZ Tienda probe', 'store', ch);
  PERFORM public.f360_set_user_role(c1, 'seller', 'Vendedora probe');
  PERFORM public.f360_set_location_assignment(c1, (loc->>'id')::uuid, true);
  PERFORM public.f360_set_seller_pin(c1, '2468');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', c1, 'role', 'authenticated')::text, true); SET LOCAL ROLE authenticated;
  tok := public.f360_start_seller_shift((loc->>'id')::uuid, '2468');
  RESET ROLE;
  INSERT INTO t_ids VALUES ('tok', NULL, tok->>'token');
END $$;

CREATE FUNCTION pg_temp.try(p_path text, p_probe text, p_uid uuid, p_role text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n int; v_out text; v_phone text; BEGIN
  SELECT phone INTO v_phone FROM public.customers WHERE auth_user_id = p_uid;
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role, 'user_metadata', json_build_object('phone', v_phone))::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql; GET DIAGNOSTICS n = ROW_COUNT;
    RESET ROLE;
    v_out := 'ACCEPTED (' || n || ' row)';
    RAISE EXCEPTION 'undo';   -- undo this attempt only, keep the fixture
  EXCEPTION WHEN OTHERS THEN RESET ROLE;
    IF SQLERRM <> 'undo' THEN v_out := 'REFUSED: ' || left(SQLERRM, 110); END IF;
  END;
  INSERT INTO t_probe(path, probe, outcome) VALUES (p_path, p_probe, v_out);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.try(text, text, uuid, text, text) TO authenticated, anon;

DO $$ DECLARE r uuid := (SELECT v FROM t_ids WHERE k='row'); ch uuid := (SELECT v FROM t_ids WHERE k='ch'); tok text := (SELECT t FROM t_ids WHERE k='tok');
  c1 uuid := current_setting('t.c1')::uuid; c2 uuid := current_setting('t.c2')::uuid; s1 uuid := current_setting('t.s1')::uuid; BEGIN
  -- BEFORE: legacy client path
  PERFORM pg_temp.try('BEFORE', 'legacy staff seller inserts a sale with a manipulated total ($1 for a $2,800 pair)', s1, 'authenticated',
    format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('PRB001', %L, '[{"inventory_id":"%s","quantity":1,"unit_price":1}]', 1, 100)$q$, ch, r));
  PERFORM pg_temp.try('BEFORE', 'a CUSTOMER (non-seller) inserts a store sale', c2, 'authenticated',
    format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('PRB002', %L, '[]', 0, 5000)$q$, ch));
  PERFORM pg_temp.try('BEFORE', 'anonymous inserts a store sale', NULL, 'anon',
    format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('PRB003', %L, '[]', 0, 100)$q$, ch));
  PERFORM pg_temp.try('BEFORE', 'legacy staff seller decrements stock with NO sale (sold = stock)', s1, 'authenticated',
    format($q$UPDATE public.channel_inventory SET sold = 1 WHERE id = %L$q$, r));
  PERFORM pg_temp.try('BEFORE', 'legacy staff seller sets sold beyond stock (oversell; blocked only by the new S0.3 CHECK)', s1, 'authenticated',
    format($q$UPDATE public.channel_inventory SET sold = 5 WHERE id = %L$q$, r));
  PERFORM pg_temp.try('BEFORE', 'legacy staff seller rewrites the price of the stock row', s1, 'authenticated',
    format($q$UPDATE public.channel_inventory SET price = 1 WHERE id = %L$q$, r));
  PERFORM pg_temp.try('BEFORE', 'a CUSTOMER changes stock', c2, 'authenticated',
    format($q$UPDATE public.channel_inventory SET sold = 1 WHERE id = %L$q$, r));
  PERFORM pg_temp.try('BEFORE', 'legacy staff inserts the SAME sale twice (double tap = 2 sales)', s1, 'authenticated',
    format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('PRB010', %L, '[]', 2800, 100), ('PRB011', %L, '[]', 2800, 100)$q$, ch, ch));
  -- AFTER: S0.3 RPC
  PERFORM pg_temp.try('AFTER', 'seller sends a price in the line', c1, 'authenticated',
    format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":1,"unit_price":1}]', 'cash')$q$, tok, r));
  PERFORM pg_temp.try('AFTER', 'seller sends a location/channel in the line', c1, 'authenticated',
    format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":1,"location_id":"%s"}]', 'cash')$q$, tok, r, ch));
  PERFORM pg_temp.try('AFTER', 'a CUSTOMER calls the sale RPC (no shift)', c2, 'authenticated',
    format($q$SELECT public.f360_record_store_sale('x', gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":1}]', 'cash')$q$, r));
  PERFORM pg_temp.try('AFTER', 'anonymous calls the sale RPC', NULL, 'anon',
    format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":1}]', 'cash')$q$, tok, r));
  PERFORM pg_temp.try('AFTER', 'seller sells 2 of a row with 1 left', c1, 'authenticated',
    format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":2}]', 'cash')$q$, tok, r));
  PERFORM pg_temp.try('AFTER', 'seller sells the last pair correctly (price from server)', c1, 'authenticated',
    format($q$SELECT public.f360_record_store_sale(%L, gen_random_uuid(), '[{"channel_inventory_id":"%s","quantity":1}]', 'cash')$q$, tok, r));
END $$;
SELECT path || ' | ' || probe || ' | ' || outcome FROM t_probe ORDER BY n;
ROLLBACK;
