-- Track C · C3 — cutover (legacy → f360 by verified physical count) + F360 store sale. STAGING. One transaction, ROLLED BACK.
-- Every fixture is synthetic and lives only inside this transaction: channels "ZZ C3 …", their legacy rows, locations
-- "ZZ C3 …", roles for lab users, PINs, shifts. The staging test product "Paula" gets a price only inside this transaction.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid, t text) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE TEMP TABLE t_snap (k text PRIMARY KEY, j jsonb) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM t_ids WHERE k = p_k $$;
CREATE FUNCTION pg_temp.tx(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT t FROM t_ids WHERE k = p_k $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; ph text;
BEGIN
  SELECT phone INTO ph FROM public.customers WHERE auth_user_id = p_uid;
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role, 'user_metadata', json_build_object('phone', ph))::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM); END;
  RETURN r;
END $$;
-- a statement as a user that returns no jsonb (direct table writes): {"ok":true,"rows":n} or {"error":…}
CREATE FUNCTION pg_temp.exec(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE n int; ph text; r jsonb;
BEGIN
  SELECT phone INTO ph FROM public.customers WHERE auth_user_id = p_uid;
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role, 'user_metadata', json_build_object('phone', ph))::text, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql; GET DIAGNOSTICS n = ROW_COUNT;
    RESET ROLE;
    r := jsonb_build_object('ok', true, 'rows', n);
    RAISE EXCEPTION 'undo';
  EXCEPTION WHEN OTHERS THEN RESET ROLE; IF SQLERRM <> 'undo' THEN r := jsonb_build_object('error', SQLERRM); END IF; END;
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.sell(p_uid uuid, p_tok text, p_key uuid, p_lines jsonb, p_qr text DEFAULT NULL, p_pay text DEFAULT 'cash') RETURNS jsonb LANGUAGE sql AS
$$ SELECT pg_temp.as(p_uid, format('SELECT public.f360_record_store_sale(%L, %L, %L, %L, NULL, %L)', p_tok, p_key, p_lines, p_pay, p_qr)) $$;
CREATE FUNCTION pg_temp.vline(p_var text, p_q int) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_array(jsonb_build_object('variant_id', pg_temp.id(p_var), 'quantity', p_q)) $$;
CREATE FUNCTION pg_temp.bal(p_loc text, p_var text) RETURNS int LANGUAGE sql AS
$$ SELECT coalesce((SELECT on_hand FROM f360.inventory_balances WHERE location_id = pg_temp.id(p_loc) AND variant_id = pg_temp.id(p_var)), 0) $$;
CREATE FUNCTION pg_temp.ledger_mismatches() RETURNS int LANGUAGE sql AS $$
  WITH mv AS (SELECT variant_id, to_location_id AS loc, quantity AS q FROM f360.inventory_movements WHERE to_location_id IS NOT NULL
    UNION ALL SELECT variant_id, from_location_id, -quantity FROM f360.inventory_movements WHERE from_location_id IS NOT NULL),
  led AS (SELECT variant_id, loc, sum(q)::int AS q FROM mv GROUP BY 1, 2)
  SELECT count(*)::int FROM led FULL JOIN f360.inventory_balances b ON b.variant_id = led.variant_id AND b.location_id = led.loc
  WHERE coalesce(led.q, 0) <> coalesce(b.on_hand, 0) $$;
CREATE FUNCTION pg_temp.ledger_ok(p_after text) RETURNS void LANGUAGE sql AS
$$ SELECT pg_temp.ok(pg_temp.ledger_mismatches() = 0, 'balances = ledger after: ' || p_after, 'mismatches=' || pg_temp.ledger_mismatches()) $$;
CREATE FUNCTION pg_temp.ci_hash(p_ch text) RETURNS text LANGUAGE sql AS
$$ SELECT md5(coalesce(string_agg(c::text, '|' ORDER BY c.id), '')) FROM public.channel_inventory c WHERE c.channel_id = pg_temp.id(p_ch) $$;
CREATE FUNCTION pg_temp.loc_state(p_loc text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('ledger_authority', l.ledger_authority,
    'cutover', (SELECT status FROM f360.location_cutovers WHERE location_id = l.id ORDER BY started_at DESC LIMIT 1),
    'f360_balances', (SELECT coalesce(jsonb_object_agg(f360.variant_label(b.variant_id), b.on_hand) FILTER (WHERE b.on_hand <> 0), '{}'::jsonb) FROM f360.inventory_balances b WHERE b.location_id = l.id),
    'opening_events', (SELECT count(*) FROM f360.inventory_events WHERE event_type = 'OPENING_PHYSICAL_COUNT' AND business_reference_id = l.id::text),
    'legacy_units', (SELECT coalesce(jsonb_object_agg(ci.product_name || ' · ' || coalesce(ci.color, '') || ' · ' || coalesce(ci.size, ''), greatest(ci.stock - ci.sold, 0)), '{}'::jsonb)
                     FROM public.channel_inventory ci WHERE ci.channel_id = l.legacy_channel_id))
  FROM f360.locations l WHERE l.id = pg_temp.id(p_loc) $$;

SELECT auth_user_id AS owner FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS op FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT id AS a FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS b FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS viewer FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
INSERT INTO t_ids (k, v) VALUES ('owner', :'owner'), ('op', :'op'), ('A', :'a'), ('B', :'b'), ('viewer', :'viewer');

-- ── Fixtures ────────────────────────────────────────────────────────────────
DO $$
DECLARE o uuid := pg_temp.id('owner'); ch uuid; ch2 uuid; tok jsonb;
BEGIN
  INSERT INTO t_ids (k, v) SELECT 'v' || v.size_label, v.id FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id
    JOIN f360.product_colors c ON c.id = v.color_id WHERE p.name = 'Paula' AND c.name = 'Camel' AND v.size_label IN ('35', '36', '37', '38');
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ C3 Canal piloto', 'store', true) RETURNING id INTO ch;
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ C3 Canal sigue legacy', 'store', true) RETURNING id INTO ch2;
  INSERT INTO t_ids (k, v) VALUES ('ch', ch), ('ch2', ch2);
  -- legacy stock of the pilot store (the legacy numbers are NOT what the opening balance will be)
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch, 'Paula', '35', 'Camel', 1500, 3, 0) RETURNING id) INSERT INTO t_ids (k, v) SELECT 'r35', id FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch, 'Paula', '36', 'Camel', 1500, 2, 1) RETURNING id) INSERT INTO t_ids (k, v) SELECT 'r36', id FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch, 'Paula', '37', 'Camel', 1500, 1, 1) RETURNING id) INSERT INTO t_ids (k, v) SELECT 'r37', id FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch, 'ZZ Modelo viejo', '38', 'Rosa', 1200, 2, 0) RETURNING id) INSERT INTO t_ids (k, v) SELECT 'rX', id FROM x;
  WITH x AS (INSERT INTO public.channel_inventory (channel_id, product_name, size, color, price, stock, sold) VALUES (ch2, 'Paula', '35', 'Camel', 1500, 5, 0) RETURNING id) INSERT INTO t_ids (k, v) SELECT 'q35', id FROM x;
  INSERT INTO t_ids (k, v) SELECT 'L', (pg_temp.as(o, format($q$SELECT public.f360_create_location('ZZ C3 Tienda piloto', 'store', %L)$q$, ch))->>'id')::uuid;
  INSERT INTO t_ids (k, v) SELECT 'L2', (pg_temp.as(o, format($q$SELECT public.f360_create_location('ZZ C3 Tienda sigue legacy', 'store', %L)$q$, ch2))->>'id')::uuid;
  INSERT INTO t_ids (k, v) SELECT 'W', (pg_temp.as(o, $q$SELECT public.f360_create_location('ZZ C3 Bodega', 'warehouse')$q$)->>'id')::uuid;
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'operator', 'ZZ Operación')$q$, pg_temp.id('op')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Persona A')$q$, pg_temp.id('A')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Persona B')$q$, pg_temp.id('B')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'viewer', 'ZZ Consulta')$q$, pg_temp.id('viewer')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('A'), pg_temp.id('L')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('B'), pg_temp.id('L')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('B'), pg_temp.id('L2')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_seller_pin(%L, '2468')$q$, pg_temp.id('A')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_seller_pin(%L, '1357')$q$, pg_temp.id('B')));
  tok := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, pg_temp.id('L')));
  INSERT INTO t_ids (k, t) VALUES ('tokA', tok->>'token');
  tok := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_start_seller_shift(%L, '1357')$q$, pg_temp.id('L2')));
  INSERT INTO t_ids (k, t) VALUES ('tokB', tok->>'token');
  PERFORM pg_temp.ok(pg_temp.tx('tokA') IS NOT NULL AND pg_temp.tx('tokB') IS NOT NULL, 'fixture: seller shifts at the pilot (A) and the other legacy store (B)', '');
  -- stock at the synthetic f360 bodega (for transfers after the cutover)
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":3}]')$q$, pg_temp.id('W'), pg_temp.id('v37')));
END $$;

-- ═════ 0 · online_location: sort never decides the online source ═════
DO $$
DECLARE before uuid := (f360.online_location()).id; tgt uuid := (SELECT fulfillment_location_id FROM f360.sales_targets WHERE active ORDER BY is_production DESC, created_at LIMIT 1);
BEGIN
  UPDATE f360.locations SET sort = -100 WHERE id = pg_temp.id('W');                 -- a new warehouse now sorts FIRST
  UPDATE f360.locations SET sort = 999 WHERE id = before;                           -- and the online bodega sorts last
  PERFORM pg_temp.ok((f360.online_location()).id = tgt AND tgt = before, 'online location = the active sales target''s fulfillment location (new/reordered warehouses change nothing)',
    (f360.online_location()).name);
END $$;

-- ═════ 1 · BEFORE: the pilot is legacy and sells through the legacy branch ═════
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('r35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'ledger' = 'legacy' AND (SELECT sold FROM public.channel_inventory WHERE id = pg_temp.id('r35')) = 1,
    'BEFORE: legacy store sells through the legacy branch (channel_inventory)', coalesce(r->>'error', r->>'ledger'));
  INSERT INTO t_snap VALUES ('before', pg_temp.loc_state('L'));
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_start_cutover(gen_random_uuid(), %L)$q$, pg_temp.id('W')))->>'error' LIKE '%ya lleva su inventario en Fuxia 360%',
    'a cutover only applies to a legacy location', '');
END $$;

-- ═════ 2 · C2 mapping (gate only) + start the cutover ═════
DO $$
DECLARE r jsonb; k uuid := gen_random_uuid();
BEGIN
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_propose_legacy_mapping(%L)$q$, pg_temp.id('L')));
  PERFORM pg_temp.ok((r->>'unmatched_with_units')::int = 1 AND NOT (r->>'catalog_ready')::boolean, 'C2: 3 Paula rows proposed, 1 legacy model with stock has no F360 match', r::text);
  PERFORM pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_review_legacy_mapping(%L, 'confirmar')$q$, pg_temp.id(x))) FROM unnest(ARRAY['r35', 'r36', 'r37']) x;
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_start_cutover(%L, %L)$q$, k, pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL, 'a seller cannot start a cutover', r->>'error');
  r := pg_temp.as(NULL, format($q$SELECT public.f360_start_cutover(%L, %L)$q$, k, pg_temp.id('L')), 'anon');
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'anonymous cannot start a cutover', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_start_cutover(%L, %L, 'Piloto sintético')$q$, k, pg_temp.id('L')));
  INSERT INTO t_ids (k, v) VALUES ('C', (r->>'id')::uuid);
  PERFORM pg_temp.ok(r->>'status' = 'preparing' AND (r->'history'->0->>'actor_name') = 'ZZ Operación', 'start: status preparing; who/when audited', r->>'status');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_start_cutover(%L, %L)$q$, k, pg_temp.id('L')));
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND r->>'id' = pg_temp.id('C')::text, 'start is idempotent (same key)', '');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_start_cutover(gen_random_uuid(), %L)$q$, pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya tiene un corte en curso%', 'only one cutover in progress per location', r->>'error');
END $$;

-- ═════ 3 · During the cutover: nothing moves at that location ═════
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('r35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'sale during the cutover refused', r->>'error');
  r := pg_temp.exec(pg_temp.id('op'), format('UPDATE public.channel_inventory SET sold = sold + 1 WHERE id = %L', pg_temp.id('r35')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'old app path (legacy staff decrements stock) refused during the cutover', r->>'error');
  BEGIN UPDATE public.channel_inventory SET stock = 99 WHERE id = pg_temp.id('r36'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'even a privileged write to the legacy stock is refused during the cutover', r->>'error');
  r := pg_temp.exec(pg_temp.id('op'), format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('ZZC3X1', %L, '[]', 1500, 100)$q$, pg_temp.id('ch')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'old app path (client inserts a sale) refused during the cutover', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('L'), pg_temp.id('v35')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'receipt refused during the cutover', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]', NULL, true)$q$, pg_temp.id('W'), pg_temp.id('L'), pg_temp.id('v37')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%' AND pg_temp.bal('W', 'v37') = 3, 'transfer to/from a location in cutover refused', r->>'error');
  BEGIN UPDATE f360.locations SET ledger_authority = 'f360' WHERE id = pg_temp.id('L'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%conteo físico verificado%', 'ledger_authority cannot become f360 without a completed verified cutover (even directly)', r->>'error');
END $$;

-- ═════ 4 · Count (A) and verification (B): double control, blind, mismatch → recount ═════
DO $$
DECLARE r jsonb; c uuid := pg_temp.id('C');
BEGIN
  r := pg_temp.as(pg_temp.id('viewer'), format($q$SELECT public.f360_cutover_count(%L, '[{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v35')));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL, 'viewer cannot count', r->>'error');
  -- physical count: 35 → 2 pairs (legacy says 2), 36 → 1 (legacy says 1). 37 has 0 legacy units: not required.
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_count(%L, '[{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v35')));
  PERFORM pg_temp.ok(r->>'status' = 'counting', 'A counts by variant (model → color → size → quantity)', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_finish_count(%L)$q$, c));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Faltan 1 tallas%', 'cannot finish while a size with legacy units is uncounted', r->>'error');
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_count(%L, '[{"variant_id":"%s","quantity":1}]')$q$, c, pg_temp.id('v36')));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_finish_count(%L)$q$, c));
  PERFORM pg_temp.ok(r->>'status' = 'verification', 'count finished → verification', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_verify(%L, '[{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v35')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Doble control%', 'the same person cannot count AND verify', r->>'error');
  r := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_get_cutover(%L)$q$, c));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'lines') x WHERE x->>'counted_qty' IS NOT NULL), 'blind verification: B cannot see A''s numbers', '');
  -- B counts 36 as 2 (A said 1) → mismatch
  r := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_cutover_verify(%L, '[{"variant_id":"%s","quantity":2},{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v35'), pg_temp.id('v36')));
  PERFORM pg_temp.ok(r->>'status' = 'counting' AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'lines') x WHERE x->>'status' = 'mismatch' AND (x->>'counted_qty')::int = 1 AND (x->>'verified_qty')::int = 2),
    'mismatch detected (A 1 vs B 2): back to counting, both numbers shown for that size', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(gen_random_uuid(), %L)$q$, c));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no está listo%' AND pg_temp.loc_state('L')->>'ledger_authority' = 'legacy', 'a mismatch blocks the cutover', r->>'error');
  -- recount 36: it really is 1; B verifies again
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_count(%L, '[{"variant_id":"%s","quantity":1}]')$q$, c, pg_temp.id('v36')));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_finish_count(%L)$q$, c));
  r := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_cutover_verify(%L, '[{"variant_id":"%s","quantity":1}]')$q$, c, pg_temp.id('v36')));
  PERFORM pg_temp.ok(r->>'status' = 'ready', 'recount + verification complete → ready', coalesce(r->>'error', r->>'status'));
END $$;

-- ═════ 5 · Completion guards: C2 gate, mid-way failure, then success; idempotent; never twice ═════
DO $$
DECLARE r jsonb; c uuid := pg_temp.id('C'); k uuid := gen_random_uuid();
BEGIN
  -- the legacy store still has 2 units of a model with NO mapping → refused, everything rolled back, attempt audited
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(%L, %L)$q$, k, c));
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%C2 incompleto%' AND r->>'status' = 'ready'
    AND pg_temp.loc_state('L')->>'ledger_authority' = 'legacy' AND (pg_temp.loc_state('L')->>'opening_events')::int = 0,
    'legacy product with stock but no C2 mapping → cutover refused; location still legacy; no opening event', r->>'error');
  -- map it (it is really Paula Camel 38) → now 38 must be counted too
  PERFORM pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_review_legacy_mapping(%L, 'confirmar', %L, 'Es Paula Camel 38 con nombre viejo')$q$, pg_temp.id('rX'), pg_temp.id('v38')));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(%L, %L)$q$, k, c));
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%Faltan tallas%', 'newly mapped size must be physically counted before completing', r->>'error');
  r := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_cutover_count(%L, '[{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v38')));
  PERFORM pg_temp.ok(r->>'status' = 'counting', 'counting reopens from ready when a size is added', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('B'), format($q$SELECT public.f360_cutover_finish_count(%L)$q$, c));
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cutover_verify(%L, '[{"variant_id":"%s","quantity":2}]')$q$, c, pg_temp.id('v38')));
  PERFORM pg_temp.ok(r->>'status' = 'ready', 'double control holds per line (B counted 38, A verified it)', coalesce(r->>'error', r->>'status'));

  -- failure at the LAST step (after event, movements and balances were written): simulated with a trigger on locations
  CREATE FUNCTION pg_temp.boom() RETURNS trigger LANGUAGE plpgsql AS $b$ BEGIN RAISE EXCEPTION 'fallo simulado al cambiar la autoridad'; END $b$;
  CREATE TRIGGER zz_boom BEFORE UPDATE OF ledger_authority ON f360.locations FOR EACH ROW WHEN (NEW.ledger_authority = 'f360') EXECUTE FUNCTION pg_temp.boom();
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(%L, %L)$q$, k, c));
  DROP TRIGGER zz_boom ON f360.locations;
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%fallo simulado%' AND pg_temp.loc_state('L')->>'ledger_authority' = 'legacy'
    AND (pg_temp.loc_state('L')->>'opening_events')::int = 0 AND pg_temp.loc_state('L')->'f360_balances' = '{}'::jsonb AND r->>'status' = 'ready',
    'failure mid-cutover → complete rollback: still legacy, no opening event, no balances, still ready', r->>'error');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.cutover_changes WHERE cutover_id = c AND action = 'complete_failed') = 3, 'every failed attempt is audited', '');
  PERFORM pg_temp.ledger_ok('failed cutover attempts');

  -- success
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(%L, %L)$q$, k, c));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'status' = 'completed', 'cutover completed', coalesce(r->>'error', ''));
  INSERT INTO t_snap VALUES ('after', pg_temp.loc_state('L'));
  PERFORM pg_temp.ok(pg_temp.bal('L', 'v35') = 2 AND pg_temp.bal('L', 'v36') = 1 AND pg_temp.bal('L', 'v38') = 2 AND pg_temp.bal('L', 'v37') = 0
    AND (SELECT sum(on_hand) FROM f360.inventory_balances WHERE location_id = pg_temp.id('L')) = 5,
    'opening balances EXACTLY equal the verified count (35:2, 36:1, 38:2)', (pg_temp.loc_state('L')->'f360_balances')::text);
  PERFORM pg_temp.ok(pg_temp.loc_state('L')->>'ledger_authority' = 'f360' AND (pg_temp.loc_state('L')->>'opening_events')::int = 1
    AND (SELECT event_type FROM f360.inventory_events WHERE id = (r->>'opening_event_id')::uuid) = 'OPENING_PHYSICAL_COUNT',
    'ledger_authority = f360; exactly one OPENING_PHYSICAL_COUNT event', '');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_complete_cutover(%L, %L)$q$, k, c));
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND (pg_temp.loc_state('L')->>'opening_events')::int = 1, 'complete is idempotent (same key → same result, nothing new)', '');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_complete_cutover(gen_random_uuid(), %L)$q$, c));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya se ejecutó%', 'cutover cannot run twice', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_start_cutover(gen_random_uuid(), %L)$q$, pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya lleva su inventario%', 'a migrated location cannot start another cutover (no second opening balance)', r->>'error');
  BEGIN
    INSERT INTO f360.inventory_events (event_type, idempotency_key, actor_name, actor_role, business_reference_type, business_reference_id)
      VALUES ('OPENING_PHYSICAL_COUNT', gen_random_uuid(), 'x', 'owner', 'location_cutover', pg_temp.id('L')::text);
    r := '{"error":"accepted"}';
  EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%duplicate key%', 'a second opening event for the same location is impossible (unique)', r->>'error');
  PERFORM pg_temp.ok((SELECT c2_readiness->>'catalog_ready' FROM f360.location_cutovers WHERE id = c) = 'true', 'C2 gate evidence stored with the cutover', '');
  PERFORM pg_temp.ledger_ok('cutover');
END $$;

-- ═════ 6 · After: legacy frozen forever; no way back ═════
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.exec(pg_temp.id('op'), format('UPDATE public.channel_inventory SET sold = sold + 1 WHERE id = %L', pg_temp.id('r35')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%congelado%', 'legacy write rejected after the cutover (old app path)', r->>'error');
  BEGIN DELETE FROM public.channel_inventory WHERE id = pg_temp.id('r37'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%congelado%', 'legacy rows of a migrated store cannot be deleted either', r->>'error');
  r := pg_temp.exec(pg_temp.id('op'), format($q$INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('ZZC3X2', %L, '[]', 1500, 100)$q$, pg_temp.id('ch')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Fuxia 360%', 'old app path cannot record a sale for a migrated store', r->>'error');
  r := pg_temp.exec(pg_temp.id('op'), format($q$INSERT INTO public.offline_sales (code, items, total, points_earned, created_by_rpc, location_id) VALUES ('ZZC3X3', '[]', 1, 100, true, %L)$q$, pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%solo se puede registrar%', 'a client cannot forge an RPC sale row', r->>'error');
  BEGIN UPDATE f360.locations SET ledger_authority = 'legacy' WHERE id = pg_temp.id('L'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%no vuelve al sistema anterior%', 'f360 → legacy is impossible (corrections = compensating events)', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_propose_legacy_mapping(%L)$q$, pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya se migró%', 'C2 evidence frozen after the cutover', r->>'error');
  BEGIN UPDATE f360.location_cutovers SET counted_pairs = 99 WHERE id = pg_temp.id('C'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya terminó%', 'a completed cutover is immutable', r->>'error');
  BEGIN UPDATE f360.cutover_counts SET counted_qty = 9 WHERE cutover_id = pg_temp.id('C'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%se cerró%', 'its counts are immutable', r->>'error');
  BEGIN UPDATE f360.cutover_changes SET detail = 'x' WHERE cutover_id = pg_temp.id('C'); r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%no se puede modificar%', 'cutover audit is append-only', r->>'error');
END $$;

-- ═════ 7 · First F360 sale (closed loop) ═════
DO $$
DECLARE r jsonb; r2 jsonb; k uuid := gen_random_uuid(); card uuid; pts0 int; ci0 text := pg_temp.ci_hash('ch'); sid uuid;
BEGIN
  SELECT id, total_points INTO card, pts0 FROM public.loyalty_cards WHERE qr_code = 'STG-M1';
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('r35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'error' LIKE '%campo "channel_inventory_id"%', 'a migrated store never sells legacy rows', r->>'error');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v35', 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no tiene precio%' AND pg_temp.bal('L', 'v35') = 2, 'a product without a master price cannot be sold (nothing moves)', r->>'error');
  UPDATE f360.products SET regular_price = 2400 WHERE name = 'Paula';        -- rolled back with everything else
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('variant_id', pg_temp.id('v35'), 'quantity', 1, 'unit_price', 1)));
  PERFORM pg_temp.ok(r->>'error' LIKE '%campo "unit_price"%', 'manipulated price refused', r->>'error');

  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), k, pg_temp.vline('v35', 1), 'STG-M1', 'card');
  sid := (r->>'sale_id')::uuid; INSERT INTO t_ids (k, v) VALUES ('sale1', sid);
  PERFORM pg_temp.ok(r->>'ledger' = 'f360' AND (r->>'total')::numeric = 2400 AND pg_temp.bal('L', 'v35') = 1,
    'FIRST F360 SALE: ledger branch, master price 2400 (not the legacy 1500), stock 2 → 1', coalesce(r->>'error', r::text));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.offline_sales WHERE idempotency_key = k) = 1
    AND (SELECT count(*) FROM public.offline_sale_items WHERE sale_id = sid AND variant_id = pg_temp.id('v35') AND price_source = 'f360_master_price') = 1,
    'exactly one store_sale with its line item (variant, price source)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.inventory_events e JOIN f360.inventory_movements m ON m.event_id = e.id
      WHERE e.event_type = 'SALE' AND e.business_reference_id = sid::text AND m.from_location_id = pg_temp.id('L') AND m.to_location_id IS NULL AND m.quantity = 1) = 1
    AND (SELECT sale_event_id FROM public.offline_sales WHERE id = sid) IS NOT NULL, 'exactly one SALE event in the single ledger (location → out)', '');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.transactions WHERE idempotency_key = 'offline_sale:' || sid) = 1
    AND (SELECT total_points FROM public.loyalty_cards WHERE id = card) = pts0 + 100 AND (r->>'points')::int = 100, 'exactly one loyalty credit (+100)', r->>'points');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.store_sale_facts WHERE sale_id = sid AND source = 'store_f360' AND units = 1 AND customer_id IS NOT NULL) = 1,
    'exactly one Customer 360 / Growth fact (source store_f360, customer linked)', '');
  PERFORM pg_temp.ok(pg_temp.ci_hash('ch') = ci0, 'no write to channel_inventory', '');
  r2 := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), k, pg_temp.vline('v35', 1), 'STG-M1', 'card');
  PERFORM pg_temp.ok((r2->>'replayed')::boolean AND r2->>'sale_id' = sid::text AND pg_temp.bal('L', 'v35') = 1
    AND (SELECT count(*) FROM public.transactions WHERE idempotency_key = 'offline_sale:' || sid) = 1 AND (SELECT total_points FROM public.loyalty_cards WHERE id = card) = pts0 + 100
    AND (SELECT count(*) FROM f360.inventory_events WHERE business_reference_id = sid::text) = 1, 'retry of the sale duplicates nothing (stock, sale, loyalty, ledger)', '');
  PERFORM pg_temp.ledger_ok('first F360 sale');
END $$;

-- ═════ 8 · More F360 sale cases ═════
DO $$
DECLARE r jsonb; cardA uuid; ptsA int;
BEGIN
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v36', 2));
  PERFORM pg_temp.ok(r->>'error' LIKE '%quedan 1%' AND pg_temp.bal('L', 'v36') = 1, 'cannot sell more than there is', r->>'error');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v36', 1));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->>'code' IS NOT NULL AND NOT (r->>'claimed')::boolean AND pg_temp.bal('L', 'v36') = 0,
    'anonymous customer: sale ok, claim code returned, no loyalty', coalesce(r->>'error', ''));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v36', 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%quedan 0%' AND pg_temp.bal('L', 'v36') = 0, 'stock zero: refused, never negative', r->>'error');
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v37', 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%quedan 0%', 'a size with no balance row at all: refused', r->>'error');
  SELECT id, total_points INTO cardA, ptsA FROM public.loyalty_cards WHERE qr_code = 'STG-C1';
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v38', 1), 'STG-C1');
  PERFORM pg_temp.ok((r->>'self_sale')::boolean AND (r->>'points')::int = 0 AND (SELECT total_points FROM public.loyalty_cards WHERE id = cardA) = ptsA
    AND pg_temp.bal('L', 'v38') = 1 AND EXISTS (SELECT 1 FROM public.loyalty_apply_audit WHERE ref_id = r->>'sale_id' AND result = 'self_sale'),
    'self-sale: the pair leaves, 0 loyalty, audited as self_sale', coalesce(r->>'error', r->>'points'));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v38', 1), 'NO-EXISTE');
  PERFORM pg_temp.ok(r->>'error' LIKE '%No encontramos esa tarjeta%' AND pg_temp.bal('L', 'v38') = 1, 'unknown customer QR → whole sale rolled back (stock untouched)', r->>'error');
  -- assignment revoked → cut immediately; then an expired shift
  PERFORM pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_set_location_assignment(%L, %L, false)$q$, pg_temp.id('A'), pg_temp.id('L')));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v38', 1));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('L', 'v38') = 1, 'assignment revoked → cannot sell', r->>'error');
  PERFORM pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('A'), pg_temp.id('L')));
  UPDATE t_ids SET t = (pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, pg_temp.id('L')))->>'token') WHERE k = 'tokA';
  UPDATE f360.seller_sessions SET expires_at = now() - interval '1 minute' WHERE token_hash = f360.token_hash(pg_temp.tx('tokA'));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v38', 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%venció%' AND pg_temp.bal('L', 'v38') = 1, 'expired shift → cannot sell', r->>'error');
  UPDATE t_ids SET t = (pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_start_seller_shift(%L, '2468')$q$, pg_temp.id('L')))->>'token') WHERE k = 'tokA';
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_shift_catalog(%L)$q$, pg_temp.tx('tokA')));
  PERFORM pg_temp.ok(r->>'ledger' = 'f360' AND jsonb_array_length(r->'items') = 2 AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x ? 'channel_inventory_id'),
    'seller catalog at a migrated store = ledger stock + master price', (r->'items')::text);
  PERFORM pg_temp.ledger_ok('F360 sale cases');
END $$;

-- ═════ 9 · Transfers from / to the migrated store; En camino never sellable ═════
DO $$
DECLARE r jsonb; t uuid;
BEGIN
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":2}]', NULL, true)$q$, pg_temp.id('W'), pg_temp.id('L'), pg_temp.id('v37')));
  t := (r->>'id')::uuid;
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND pg_temp.bal('W', 'v37') = 1 AND pg_temp.bal('L', 'v37') = 0, 'transfer INTO the migrated store: sent, not yet there', coalesce(r->>'error', ''));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v37', 1));
  PERFORM pg_temp.ok(r->>'error' LIKE '%quedan 0%', 'pairs en camino cannot be sold at the destination', r->>'error');
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'status' = 'received' AND pg_temp.bal('L', 'v37') = 2, 'seller of the migrated store confirms receipt → +2', coalesce(r->>'error', ''));
  r := pg_temp.sell(pg_temp.id('A'), pg_temp.tx('tokA'), gen_random_uuid(), pg_temp.vline('v37', 1));
  PERFORM pg_temp.ok((r->>'ok')::boolean AND pg_temp.bal('L', 'v37') = 1, 'received pairs are sellable', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]', NULL, true)$q$, pg_temp.id('L'), pg_temp.id('W'), pg_temp.id('v38')));
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND pg_temp.bal('L', 'v38') = 0, 'transfer OUT of the migrated store works', coalesce(r->>'error', ''));
  PERFORM pg_temp.ledger_ok('transfers after cutover');
END $$;

-- ═════ 10 · A store that stays legacy keeps working; a cancelled cutover unblocks it ═════
DO $$
DECLARE r jsonb; c2 uuid;
BEGIN
  r := pg_temp.sell(pg_temp.id('B'), pg_temp.tx('tokB'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('q35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'ledger' = 'legacy' AND (SELECT sold FROM public.channel_inventory WHERE id = pg_temp.id('q35')) = 1, 'the other store (still legacy) sells through the legacy branch', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_start_cutover(gen_random_uuid(), %L)$q$, pg_temp.id('L2')));
  c2 := (r->>'id')::uuid;
  r := pg_temp.sell(pg_temp.id('B'), pg_temp.tx('tokB'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('q35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'error' LIKE '%corte de inventario%', 'its sales stop while a cutover is open', r->>'error');
  r := pg_temp.as(pg_temp.id('A'), format($q$SELECT public.f360_cancel_cutover(%L, 'fecha cambiada')$q$, c2));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL, 'a seller cannot cancel a cutover', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_cancel_cutover(%L, 'fecha cambiada')$q$, c2));
  PERFORM pg_temp.ok(r->>'status' = 'cancelled' AND pg_temp.loc_state('L2')->>'ledger_authority' = 'legacy', 'cancel: status cancelled, still legacy', coalesce(r->>'error', ''));
  r := pg_temp.sell(pg_temp.id('B'), pg_temp.tx('tokB'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('channel_inventory_id', pg_temp.id('q35'), 'quantity', 1)));
  PERFORM pg_temp.ok(r->>'ledger' = 'legacy' AND (SELECT sold FROM public.channel_inventory WHERE id = pg_temp.id('q35')) = 2, 'after cancel the legacy store sells again', coalesce(r->>'error', ''));
  PERFORM pg_temp.ok(pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_create_location('ZZ C3 trampa', 'store', %L)$q$, pg_temp.id('ch2')))->>'error' IS NOT NULL,
    'a legacy channel can be linked to only one location', '');
END $$;


-- ═════ 12 · C3.3 Ventas: the same authoritative sales, readable by owner/operator ═════
DO $$
DECLARE r jsonb; d jsonb; exp record; sid uuid := pg_temp.id('sale1');
BEGIN
  -- an old-client-path sale (not authoritative) must NOT appear in Ventas
  INSERT INTO public.offline_sales (code, channel_id, items, total, points_earned) VALUES ('ZZC3OLD', pg_temp.id('ch2'), '[]', 99999, 0);
  SELECT count(*) AS n, coalesce(sum(total), 0) AS rev, coalesce(sum(units), 0) AS pairs INTO exp FROM f360.store_sale_facts
    WHERE created_at >= (now() AT TIME ZONE 'America/Mexico_City')::date::timestamp AT TIME ZONE 'America/Mexico_City';
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_list_sales((now() AT TIME ZONE 'America/Mexico_City')::date, (now() AT TIME ZONE 'America/Mexico_City')::date)$q$);
  PERFORM pg_temp.ok((r->'summary'->>'sales')::int = exp.n AND (r->'summary'->>'revenue')::numeric = exp.rev AND (r->'summary'->>'pairs')::int = exp.pairs
    AND (r->'summary'->>'avg_ticket')::numeric = round(exp.rev / exp.n, 2),
    'Ventas summary = only real RPC sales (revenue, count, pairs, avg ticket)', (r->'summary')::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE (x->>'total')::numeric = 99999), 'old client-path sale is not shown nor counted', '');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'id' = sid::text AND x->>'customer' IS NOT NULL AND x->>'location' = 'ZZ C3 Tienda piloto'),
    'the first closed-loop sale appears in Ventas with location and customer', '');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_list_sales(NULL, NULL, %L, NULL)$q$, pg_temp.id('L2')));
  PERFORM pg_temp.ok((r->'summary'->>'sales')::int = 2 AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'location' <> 'ZZ C3 Tienda sigue legacy'),
    'location filter (the legacy store: its 2 RPC sales)', (r->'summary')::text);
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_list_sales(NULL, NULL, NULL, %L)$q$, pg_temp.id('B')));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->>'seller' <> 'ZZ Persona B') AND (r->'summary'->>'sales')::int >= 2, 'seller filter', '');
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_list_sales(NULL, NULL, NULL, NULL, 'online')$q$);
  PERFORM pg_temp.ok((r->'summary'->>'sales')::int = 0, 'channel filter ready for online (P2.3B): none yet', '');
  d := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_get_sale(%L)$q$, sid));
  PERFORM pg_temp.ok(d->>'ledger' = 'f360' AND d->'inventory'->>'kind' = 'f360' AND (d->'inventory'->'event'->>'type') = 'SALE'
    AND d->'loyalty'->>'state' = 'credited' AND (d->'loyalty'->>'points')::int = 100 AND jsonb_array_length(d->'items') = 1
    AND d->'items'->0->>'product_name' = 'Paula' AND (d->'items'->0->>'unit_price')::numeric = 2400 AND d->'customer'->>'phone' LIKE '••••%'
    AND d->'support'->>'idempotency_key' IS NOT NULL, 'sale detail: items, SALE movement, loyalty credited, masked phone, support ids', d->>'loyalty');
  d := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_get_sale(%L)$q$, (SELECT id FROM public.offline_sales WHERE self_sale AND location_id = pg_temp.id('L') LIMIT 1)));
  PERFORM pg_temp.ok(d->'loyalty'->>'state' = 'self_sale', 'detail explains why loyalty did not apply (self-sale)', d->'loyalty'->>'text');
  d := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_get_sale(%L)$q$, (SELECT id FROM public.offline_sales WHERE location_id = pg_temp.id('L') AND customer_id IS NULL AND claimed_at IS NULL LIMIT 1)));
  PERFORM pg_temp.ok(d->'loyalty'->>'state' = 'pending_claim' AND d->'loyalty'->>'code' IS NOT NULL, 'detail: unidentified customer → claim code pending', d->'loyalty'->>'text');
  d := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_get_sale(%L)$q$, (SELECT id FROM public.offline_sales WHERE location_id = pg_temp.id('L2') AND created_by_rpc LIMIT 1)));
  PERFORM pg_temp.ok(d->>'ledger' = 'legacy' AND d->'inventory'->>'kind' = 'legacy', 'a legacy-branch sale shows it discounted the legacy stock', '');
  r := pg_temp.as(pg_temp.id('A'), $q$SELECT public.f360_list_sales()$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%permiso%', 'seller: no access to the global sales screen', r->>'error');
  r := pg_temp.as(pg_temp.id('viewer'), format($q$SELECT public.f360_get_sale(%L)$q$, sid));
  PERFORM pg_temp.ok(r->>'error' LIKE '%permiso%', 'viewer: no access to sale details', r->>'error');
  r := pg_temp.as(NULL, $q$SELECT public.f360_list_sales()$q$, 'anon');
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'anonymous: refused', r->>'error');
END $$;

-- ═════ 11 · Invariants overall ═════
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.locations l WHERE l.ledger_authority = 'f360' AND l.legacy_channel_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM f360.location_cutovers c WHERE c.location_id = l.id AND c.status = 'completed')),
  'no location is f360 with a legacy channel unless a verified cutover completed', '');
SELECT pg_temp.ok(to_regclass('public.inventory_events') IS NULL, 'no second ledger', '');
SELECT pg_temp.ledger_ok('all C3 scenarios');
SELECT 'SNAP | before | ' || (SELECT j::text FROM t_snap WHERE k = 'before');
SELECT 'SNAP | after  | ' || (SELECT j::text FROM t_snap WHERE k = 'after');

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
