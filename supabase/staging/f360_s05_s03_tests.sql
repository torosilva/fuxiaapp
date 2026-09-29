-- S0.5 loyalty_apply + S0.3 legacy store sale — database tests (STAGING). One transaction, ROLLED BACK.
-- Fixtures (channel, stock rows, locations, seller role/assignment/PIN) are synthetic and exist only in this transaction.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid, t text) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;
-- sale as a given user; returns the result or {"error": ...} (errors roll back only this attempt's sub-block)
CREATE FUNCTION pg_temp.sell(p_uid uuid, p_token text, p_key uuid, p_lines jsonb, p_pay text DEFAULT 'cash', p_ref text DEFAULT NULL, p_qr text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM pg_temp.as_user(p_uid, 'authenticated');
    r := public.f360_record_store_sale(p_token, p_key, p_lines, p_pay, p_ref, p_qr);
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.sold(p_id uuid) RETURNS int LANGUAGE sql AS $$ SELECT sold FROM public.channel_inventory WHERE id = p_id $$;
CREATE FUNCTION pg_temp.line(p_id uuid, p_q int) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_array(jsonb_build_object('channel_inventory_id', p_id, 'quantity', p_q)) $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true) \gset t_

-- Fixture: channel ZZ with 3 stock rows; another channel; a legacy location for ZZ (assigned to c1 = lab C1, who has card STG-C1)
DO $$
DECLARE ch uuid; ch2 uuid; loc jsonb; locf jsonb; u uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; tok jsonb;
BEGIN
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ Canal S03', 'store', true) RETURNING id INTO ch;
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ Canal ajeno', 'store', true) RETURNING id INTO ch2;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, sku, size, color, price, stock, sold) VALUES (ch, 'ZZ Macarena', 'ZZ-SKU-1', '37', 'Negro', 2800, 3, 2) RETURNING id) INSERT INTO t_ids SELECT 'last', id, NULL FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, sku, size, color, price, stock, sold) VALUES (ch, 'ZZ Lucía', NULL, '38', 'Nude', 1900, 20, 0) RETURNING id) INSERT INTO t_ids SELECT 'plenty', id, NULL FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch2, 'ZZ Ajena', '36', 'Rojo', 999, 5, 0) RETURNING id) INSERT INTO t_ids SELECT 'foreign', id, NULL FROM x;
  PERFORM pg_temp.as_user(u, 'authenticated');
  loc := public.f360_create_location('ZZ Tienda S03 (legacy)', 'store', ch);
  locf := public.f360_create_location('ZZ Tienda S03 (f360)', 'store');
  PERFORM public.f360_set_user_role(c1, 'seller', 'Vendedora S03');
  PERFORM public.f360_set_location_assignment(c1, (loc->>'id')::uuid, true);
  PERFORM public.f360_set_location_assignment(c1, (locf->>'id')::uuid, true);
  PERFORM public.f360_set_seller_pin(c1, '2468');
  RESET ROLE;
  PERFORM pg_temp.as_user(c1, 'authenticated');
  tok := public.f360_start_seller_shift((loc->>'id')::uuid, '2468');
  RESET ROLE;
  INSERT INTO t_ids VALUES ('loc', (loc->>'id')::uuid, NULL), ('locf', (locf->>'id')::uuid, NULL), ('ch', ch, NULL), ('tok', NULL, tok->>'token');
END $$;

-- ═════ S0.5 loyalty_apply ═════
DO $$
DECLARE err text; r jsonb; r2 jsonb; card uuid; pts0 int; key text := 'test:' || gen_random_uuid();
BEGIN
  SELECT id, total_points INTO card, pts0 FROM public.loyalty_cards WHERE qr_code = 'STG-C2';
  PERFORM pg_temp.as_user(current_setting('t.c2')::uuid, 'authenticated');
  BEGIN PERFORM public.loyalty_apply(card, '[{"quantity":50}]', 1, 'store', 'x', 'x', 'k1'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'Q7: the app (authenticated) cannot call loyalty_apply', err);
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.loyalty_apply(card, '[{"quantity":50}]', 1, 'store', 'x', 'x', 'k1'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot call loyalty_apply', err);

  r := public.loyalty_apply(card, '[{"sku":"ZZ-1","product_name":"ZZ","quantity":2,"unit_price":100}]', 200, 'store', 'test', '1', key, '{"type":"test"}');
  r2 := public.loyalty_apply(card, '[{"sku":"ZZ-1","product_name":"ZZ","quantity":2,"unit_price":100}]', 200, 'store', 'test', '1', key, '{"type":"test"}');
  PERFORM pg_temp.ok((r->>'points')::int = 200 AND (r2->>'replayed')::boolean AND (SELECT total_points FROM public.loyalty_cards WHERE id = card) = pts0 + 200
    AND (SELECT count(*) FROM public.transactions WHERE idempotency_key = key) = 1, 'idempotent: same key twice → credited once (100/pair)', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.purchase_items pi JOIN public.transactions t ON t.id = pi.transaction_id WHERE t.idempotency_key = key AND pi.sku = 'ZZ-1') = 1,
    'line items saved with SKU', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.loyalty_apply_audit WHERE idempotency_key = key AND result = 'applied') = 1
    AND (SELECT count(*) FROM public.loyalty_apply_audit WHERE idempotency_key = key AND result = 'replayed') = 1, 'audit: applied + replayed', '');
  r := public.loyalty_apply(card, '[{"quantity":1}]', 1, 'store', 'test', '2', 'self:' || gen_random_uuid(), jsonb_build_object('type', 'seller', 'auth_user_id', current_setting('t.c2')));
  PERFORM pg_temp.ok((r->>'self_sale')::boolean AND (r->>'points')::int = 0 AND (SELECT total_points FROM public.loyalty_cards WHERE id = card) = pts0 + 200,
    'self_sale (actor = card owner) → 0 loyalty, audited', r::text);
  BEGIN PERFORM public.loyalty_apply(card, '[{"quantity":0}]', 1, 'store', 't', '3', 'zero:' || gen_random_uuid()); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'a credit with 0 pairs is refused', err);
  BEGIN UPDATE public.loyalty_apply_audit SET points = 1 WHERE idempotency_key = key; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'loyalty audit is append-only', err);
END $$;

-- ═════ S0.3 ═════
DO $$
DECLARE c1 uuid := current_setting('t.c1')::uuid; tok text := (SELECT t FROM t_ids WHERE k = 'tok'); last uuid := (SELECT v FROM t_ids WHERE k = 'last');
  plenty uuid := (SELECT v FROM t_ids WHERE k = 'plenty'); foreign_ uuid := (SELECT v FROM t_ids WHERE k = 'foreign'); r jsonb; r2 jsonb; err text; k1 uuid := gen_random_uuid();
  ev0 bigint := (SELECT count(*) FROM f360.inventory_events); mv0 bigint := (SELECT count(*) FROM f360.inventory_movements); c2card uuid; c2pts int; sold0 int; tx0 bigint;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_record_store_sale(tok, gen_random_uuid(), pg_temp.line(plenty, 1), 'cash'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anonymous sale refused', err);
  r := pg_temp.sell(current_setting('t.c2')::uuid, tok, gen_random_uuid(), pg_temp.line(plenty, 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%turno no es válido%', 'another account cannot use the seller''s shift', r->>'error');

  r := pg_temp.sell(c1, tok, gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', plenty, 'quantity', 1, 'unit_price', 1)));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo se aceptan producto y cantidad%unit_price%', 'client-manipulated price refused', r->>'error');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', plenty, 'quantity', 1, 'location_id', gen_random_uuid())));
  PERFORM pg_temp.ok(r->>'error' LIKE '%location_id%', 'client-sent location refused', r->>'error');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(foreign_, 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no pertenece a tu tienda%' AND pg_temp.sold(foreign_) = 0, 'a product from another location is refused', r->>'error');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1), 'crypto');
  PERFORM pg_temp.ok(r->>'error' LIKE '%cómo pagó%', 'invalid payment method refused', r->>'error');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1), 'card', '4111111111111111');
  PERFORM pg_temp.ok(r->>'error' LIKE '%tarjeta%', 'card number as payment reference refused (never stored)', r->>'error');

  -- sale without customer; double tap
  sold0 := pg_temp.sold(plenty);
  r := pg_temp.sell(c1, tok, k1, pg_temp.line(plenty, 2), 'transfer', 'SPEI-778');
  r2 := pg_temp.sell(c1, tok, k1, pg_temp.line(plenty, 2), 'transfer', 'SPEI-778');
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (r->>'total')::numeric = 3800 AND r->>'code' IS NOT NULL AND (r2->>'replayed')::boolean AND r2->>'sale_id' = r->>'sale_id'
    AND pg_temp.sold(plenty) = sold0 + 2, 'sale without customer: system price 2×1900, stock −2 once; double tap → same sale', r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.offline_sale_items WHERE sale_id = (r->>'sale_id')::uuid AND price_source = 'legacy_channel_inventory' AND unit_price = 1900) = 1
    AND (SELECT payment_method || ':' || payment_reference || ':' || price_source FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid) = 'transfer:SPEI-778:legacy_channel_inventory'
    AND (SELECT seller_auth_user_id = c1 AND location_id = (SELECT v FROM t_ids WHERE k = 'loc') FROM public.offline_sales WHERE id = (r->>'sale_id')::uuid),
    'line items + payment + price source + seller + location recorded by the server', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.store_sale_facts WHERE sale_id = (r->>'sale_id')::uuid) = 1, 'Growth/Customer 360: exactly ONE fact for the sale', '');
  FOREACH err IN ARRAY ARRAY['cash', 'card', 'other'] LOOP
    r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1), err);
    PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'payment_method' = err, 'payment method ' || err || ' accepted', '');
  END LOOP;

  -- never negative (last pair: stock 3, sold 2)
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(last, 2));
  PERFORM pg_temp.ok(r->>'error' LIKE '%No hay existencia suficiente%' AND pg_temp.sold(last) = 2, 'asking more than available → refused, nothing moved', r->>'error');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(last, 1));
  r2 := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(last, 1));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r2->>'error' LIKE '%No hay existencia%' AND pg_temp.sold(last) = 3, 'last pair sold once; the next sale is refused (stock never negative)', r2->>'error');
  BEGIN UPDATE public.channel_inventory SET sold = stock + 1 WHERE id = last; err := 'accepted'; EXCEPTION WHEN check_violation THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'DB constraint: sold can never exceed stock (any path)', err);

  -- customer: other customer's card → 100/pair; self-sale → 0, audited
  SELECT id, total_points INTO c2card, c2pts FROM public.loyalty_cards WHERE qr_code = 'STG-C2';
  tx0 := (SELECT count(*) FROM public.transactions WHERE loyalty_card_id = c2card);
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 3), 'card', NULL, 'STG-C2');
  PERFORM pg_temp.ok((r->>'points')::int = 300 AND (r->>'claimed')::boolean AND (SELECT total_points FROM public.loyalty_cards WHERE id = c2card) = c2pts + 300
    AND (SELECT count(*) FROM public.transactions WHERE loyalty_card_id = c2card) = tx0 + 1
    AND (SELECT count(*) FROM public.purchase_items pi JOIN public.transactions t ON t.id = pi.transaction_id WHERE t.ref_id = r->>'sale_id') = 1,
    'with customer QR: 3 pairs → 300 points, 1 transaction, items saved, sale claimed', r::text);
  PERFORM pg_temp.ok((SELECT customer_id IS NOT NULL FROM f360.store_sale_facts WHERE sale_id = (r->>'sale_id')::uuid) AND (SELECT count(*) FROM f360.store_sale_facts WHERE sale_id = (r->>'sale_id')::uuid) = 1,
    'Customer 360 gets the sale linked to the customer (one fact)', '');
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1), 'cash', NULL, 'STG-C1');
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (r->>'self_sale')::boolean AND (r->>'points')::int = 0
    AND EXISTS (SELECT 1 FROM public.loyalty_apply_audit WHERE ref_id = r->>'sale_id' AND result = 'self_sale'), 'self-sale: the pair leaves, 0 loyalty, audited as self_sale', r::text);

  -- unknown QR → the whole sale rolls back
  sold0 := pg_temp.sold(plenty);
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1), 'cash', NULL, 'NO-EXISTE');
  PERFORM pg_temp.ok(r->>'error' LIKE '%No encontramos esa tarjeta%' AND pg_temp.sold(plenty) = sold0, 'unknown customer QR → whole sale rolled back', r->>'error');

  -- no write to the f360 ledger, no public.inventory_events
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events) = ev0 AND (SELECT count(*) FROM f360.inventory_movements) = mv0, 'legacy branch writes NOTHING to the f360 ledger', '');
  PERFORM pg_temp.ok(to_regclass('public.inventory_events') IS NULL, 'public.inventory_events does not exist (D-X1)', '');
END $$;

-- loyalty failure → full rollback (a transient failure injected inside loyalty_apply's transaction insert)
CREATE FUNCTION pg_temp.boom() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'loyalty down (test)'; END $$;
CREATE TRIGGER zz_boom BEFORE INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION pg_temp.boom();
DO $$
DECLARE c1 uuid := current_setting('t.c1')::uuid; tok text := (SELECT t FROM t_ids WHERE k = 'tok'); plenty uuid := (SELECT v FROM t_ids WHERE k = 'plenty');
  r jsonb; sold0 int := pg_temp.sold(plenty); sales0 bigint := (SELECT count(*) FROM public.offline_sales); k uuid := gen_random_uuid();
BEGIN
  r := pg_temp.sell(c1, tok, k, pg_temp.line(plenty, 1), 'cash', NULL, 'STG-C2');
  PERFORM pg_temp.ok(r->>'error' LIKE '%loyalty down%' AND pg_temp.sold(plenty) = sold0 AND (SELECT count(*) FROM public.offline_sales) = sales0
    AND NOT EXISTS (SELECT 1 FROM public.offline_sales WHERE idempotency_key = k), 'loyalty failure → the WHOLE sale rolls back (no sale, no stock change)', r->>'error');
END $$;
DROP TRIGGER zz_boom ON public.transactions;

-- claim later, shift checks, dormant f360 branch
DO $$
DECLARE c1 uuid := current_setting('t.c1')::uuid; c2 uuid := current_setting('t.c2')::uuid; tok text := (SELECT t FROM t_ids WHERE k = 'tok');
  plenty uuid := (SELECT v FROM t_ids WHERE k = 'plenty'); r jsonb; err text; code text; tok2 jsonb;
BEGIN
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1));
  code := r->>'code';
  PERFORM pg_temp.as_user(c2, 'authenticated'); r := public.f360_claim_store_sale(code); RESET ROLE;
  PERFORM pg_temp.ok((r->>'points')::int = 100, 'customer claims later with HER OWN session → 100 points', r::text);
  PERFORM pg_temp.as_user(c2, 'authenticated');
  BEGIN PERFORM public.f360_claim_store_sale(code); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%ya utilizado%', 'double claim refused', err);
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1));
  PERFORM pg_temp.as_user(c1, 'authenticated'); r := public.f360_claim_store_sale(r->>'code'); RESET ROLE;
  PERFORM pg_temp.ok((r->>'self_sale')::boolean AND (r->>'points')::int = 0, 'the seller claiming her own sale → self_sale, 0 points', r::text);

  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  PERFORM public.f360_set_location_assignment(c1, (SELECT v FROM t_ids WHERE k = 'loc'), false);
  RESET ROLE;
  r := pg_temp.sell(c1, tok, gen_random_uuid(), pg_temp.line(plenty, 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%turno terminó%' OR r->>'error' LIKE '%no tienes acceso%', 'seller whose assignment was revoked cannot sell', r->>'error');

  PERFORM pg_temp.as_user(c1, 'authenticated'); tok2 := public.f360_start_seller_shift((SELECT v FROM t_ids WHERE k = 'locf'), '2468'); RESET ROLE;
  r := pg_temp.sell(c1, tok2->>'token', gen_random_uuid(), pg_temp.line(plenty, 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%campo "channel_inventory_id"%', 'f360 location (C3 active): legacy stock rows can never be sold there', r->>'error');
  UPDATE f360.seller_sessions SET expires_at = now() - interval '1 minute' WHERE token_hash = f360.token_hash(tok2->>'token');
  r := pg_temp.sell(c1, tok2->>'token', gen_random_uuid(), pg_temp.line(plenty, 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%venció%', 'expired shift cannot sell', r->>'error');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
