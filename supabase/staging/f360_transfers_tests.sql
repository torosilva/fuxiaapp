-- Track C · Transfers — database tests (STAGING). One transaction, ROLLED BACK: every fixture (locations, roles,
-- assignments, stock, transfers) exists only inside it. Product "Paula" (existing staging test product) is only read.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon;
CREATE FUNCTION pg_temp.id(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v FROM t_ids WHERE k = p_k $$;
GRANT EXECUTE ON FUNCTION pg_temp.id(text) TO authenticated, anon;
-- run one statement as a user; returns its jsonb result or {"error": message}. A failure undoes only that attempt.
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
-- stock at a location (by key) for a variant (by key)
CREATE FUNCTION pg_temp.bal(p_loc text, p_var text) RETURNS int LANGUAGE sql AS
$$ SELECT coalesce((SELECT on_hand FROM f360.inventory_balances WHERE location_id = CASE WHEN p_loc = 'transit' THEN f360.transit_location() ELSE pg_temp.id(p_loc) END AND variant_id = pg_temp.id(p_var)), 0) $$;
-- balances = ledger, for EVERY (variant, location) in the database
CREATE FUNCTION pg_temp.ledger_mismatches() RETURNS int LANGUAGE sql AS $$
  WITH mv AS (
    SELECT variant_id, to_location_id AS loc, quantity AS q FROM f360.inventory_movements WHERE to_location_id IS NOT NULL
    UNION ALL SELECT variant_id, from_location_id, -quantity FROM f360.inventory_movements WHERE from_location_id IS NOT NULL),
  led AS (SELECT variant_id, loc, sum(q)::int AS q FROM mv GROUP BY 1, 2)
  SELECT count(*)::int FROM led FULL JOIN f360.inventory_balances b ON b.variant_id = led.variant_id AND b.location_id = led.loc
  WHERE coalesce(led.q, 0) <> coalesce(b.on_hand, 0)
$$;
CREATE FUNCTION pg_temp.ledger_ok(p_after text) RETURNS void LANGUAGE sql AS
$$ SELECT pg_temp.ok(pg_temp.ledger_mismatches() = 0, 'balances = ledger after: ' || p_after, 'mismatches=' || pg_temp.ledger_mismatches()) $$;
CREATE FUNCTION pg_temp.ci_hash() RETURNS text LANGUAGE sql AS
$$ SELECT md5(coalesce(string_agg(c::text, '|' ORDER BY c.id), '')) FROM public.channel_inventory c $$;

SELECT auth_user_id AS owner FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS op FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT id AS sel FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS sel2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS viewer FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
INSERT INTO t_ids VALUES ('owner', :'owner'), ('op', :'op'), ('sel', :'sel'), ('sel2', :'sel2'), ('viewer', :'viewer');
CREATE TEMP TABLE t_snap ON COMMIT DROP AS SELECT pg_temp.ci_hash() AS ci, (SELECT count(*) FROM public.offline_sales) AS sales;

-- ── Fixtures: 2 f360 locations + 1 legacy, roles, one assignment, stock at the origin ──
DO $$
DECLARE o uuid := pg_temp.id('owner'); ch uuid; r jsonb;
BEGIN
  INSERT INTO public.channels (name, type, active) VALUES ('ZZ T Canal legacy', 'store', true) RETURNING id INTO ch;
  INSERT INTO t_ids SELECT 'A', (pg_temp.as(o, $q$SELECT public.f360_create_location('ZZ T Bodega', 'warehouse')$q$)->>'id')::uuid;
  INSERT INTO t_ids SELECT 'B', (pg_temp.as(o, $q$SELECT public.f360_create_location('ZZ T Tienda', 'store')$q$)->>'id')::uuid;
  INSERT INTO t_ids SELECT 'L', (pg_temp.as(o, format($q$SELECT public.f360_create_location('ZZ T Legacy', 'store', %L)$q$, ch))->>'id')::uuid;
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'operator', 'ZZ Operación')$q$, pg_temp.id('op')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora B')$q$, pg_temp.id('sel')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'seller', 'ZZ Vendedora sin B')$q$, pg_temp.id('sel2')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'viewer', 'ZZ Consulta')$q$, pg_temp.id('viewer')));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('sel'), pg_temp.id('B')));
  PERFORM pg_temp.as(o, $q$SELECT public.f360_create_product('ZZ T Paula', ARRAY['35','36'], '[{"name":"Camel"}]'::jsonb)$q$);
  INSERT INTO t_ids SELECT 'v1', v.id FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
    WHERE p.name = 'ZZ T Paula' AND c.name = 'Camel' AND v.size_label = '35';
  INSERT INTO t_ids SELECT 'v2', v.id FROM f360.product_variants v JOIN f360.products p ON p.id = v.product_id JOIN f360.product_colors c ON c.id = v.color_id
    WHERE p.name = 'ZZ T Paula' AND c.name = 'Camel' AND v.size_label = '36';
  r := pg_temp.as(o, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":5},{"variant_id":"%s","quantity":1}]')$q$,
        pg_temp.id('A'), pg_temp.id('v1'), pg_temp.id('v2')));
  PERFORM pg_temp.ok(r->>'error' IS NULL AND pg_temp.bal('A', 'v1') = 5 AND pg_temp.bal('A', 'v2') = 1, 'fixture: origin has 5 + 1 pairs', coalesce(r->>'error', ''));
END $$;

-- ═════ 1 · Request: no stock change, idempotent, permissions ═════
DO $$
DECLARE k uuid := gen_random_uuid(); r jsonb; r2 jsonb; n int;
BEGIN
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_request_transfer(%L, %L, %L, '[{"variant_id":"%s","quantity":2}]', 'para vitrina')$q$, k, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  INSERT INTO t_ids VALUES ('T1', (r->>'id')::uuid);
  PERFORM pg_temp.ok(r->>'status' = 'requested' AND pg_temp.bal('A', 'v1') = 5 AND pg_temp.bal('transit', 'v1') = 0 AND pg_temp.bal('B', 'v1') = 0,
    'request (seller assigned to destination) does NOT change stock', coalesce(r->>'error', r->>'number'));
  n := (SELECT count(*) FROM f360.transfers);
  r2 := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_request_transfer(%L, %L, %L, '[{"variant_id":"%s","quantity":2}]', 'para vitrina')$q$, k, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok((r2->>'replayed')::boolean AND r2->>'id' = r->>'id' AND (SELECT count(*) FROM f360.transfers) = n, 'double-click on request (same key) → one transfer', r2->>'number');
  r2 := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(%L, %L, %L, '[{"variant_id":"%s","quantity":2}]')$q$, k, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r2->>'error' LIKE '%otros datos%', 'a key already used by another person is refused', r2->>'error');

  r := pg_temp.as(pg_temp.id('sel2'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ubicación que tienes asignada%', 'seller WITHOUT assignment cannot request', r->>'error');
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]', NULL, true)$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo operación%' AND pg_temp.bal('A', 'v1') = 5, 'seller cannot request-and-send', r->>'error');
  r := pg_temp.as(pg_temp.id('viewer'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%permiso%', 'viewer cannot request', r->>'error');
  r := pg_temp.as(NULL, format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')), 'anon');
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'anonymous cannot call any transfer RPC', r->>'error');
  r := pg_temp.as(NULL, format($q$SELECT public.f360_list_transfers()$q$), 'anon');
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'anonymous cannot even list transfers', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1,"location_id":"%s"}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1'), pg_temp.id('L')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo se aceptan talla y cantidad%', 'lines accept only variant + quantity (no client location/role)', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":-1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%sin negativos%', 'negative quantities refused', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('L'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%sistema anterior%', 'legacy destination refused (no transfers for ledger_authority=legacy)', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('L'), pg_temp.id('A'), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%sistema anterior%', 'legacy origin refused', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), f360.transit_location(), pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ubicación válida%', '"En camino" cannot be chosen as origin/destination', r->>'error');
  PERFORM pg_temp.ledger_ok('requests');
END $$;

-- ═════ 2 · Send: only owner/operator, stock moves exactly once, destination unchanged ═════
DO $$
DECLARE k uuid := gen_random_uuid(); r jsonb; t uuid := pg_temp.id('T1'); ev int;
BEGIN
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo operación%' AND pg_temp.bal('A', 'v1') = 5, 'seller cannot send (not even her own request)', r->>'error');
  r := pg_temp.as(pg_temp.id('viewer'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('A', 'v1') = 5, 'viewer cannot send', r->>'error');
  ev := (SELECT count(*) FROM f360.inventory_events);
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(%L, %L)$q$, k, t));
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND pg_temp.bal('A', 'v1') = 3 AND pg_temp.bal('transit', 'v1') = 2 AND pg_temp.bal('B', 'v1') = 0,
    'send: origin −2 → En camino +2; destination NOT increased', coalesce(r->>'error', format('A=%s transit=%s B=%s', pg_temp.bal('A','v1'), pg_temp.bal('transit','v1'), pg_temp.bal('B','v1'))));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(%L, %L)$q$, k, t));
  PERFORM pg_temp.ok((r->>'replayed')::boolean AND pg_temp.bal('A', 'v1') = 3 AND (SELECT count(*) FROM f360.inventory_events) = ev + 1,
    'double-click on send (same key) → stock changed exactly once', r->>'status');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya no está pendiente%' AND pg_temp.bal('A', 'v1') = 3, 'second send with another key refused (status re-checked under lock)', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_cancel_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no se ha enviado%', 'cancel after send refused', r->>'error');
  PERFORM pg_temp.ok((SELECT event_type = 'TRANSFER' AND business_reference_type = 'transfer' FROM f360.inventory_events e JOIN f360.transfers x ON x.send_event_id = e.id WHERE x.id = t),
    'send is a TRANSFER event in the single ledger', '');
  PERFORM pg_temp.ledger_ok('send');
END $$;

-- ═════ 3 · En camino is never sellable / operable / available ═════
DO $$
DECLARE r jsonb; tr uuid := f360.transit_location();
BEGIN
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_list_locations()$q$);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE (x->>'id')::uuid = tr), 'En camino is not listed as a location', '');
  PERFORM pg_temp.ok((SELECT (x->>'incoming')::int FROM jsonb_array_elements(r) x WHERE (x->>'id')::uuid = pg_temp.id('B')) = 2, 'destination shows 2 pairs incoming (apart from its stock)', '');
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_home()$q$);
  -- in transit = this test's 2 pairs + whatever is really travelling in staging right now (robust to open transfers)
  PERFORM pg_temp.ok((r->>'in_transit_pairs')::int = (SELECT sum(on_hand) FROM f360.inventory_balances WHERE location_id = tr) AND (r->>'in_transit_pairs')::int >= 2
    AND (r->>'available_pairs')::int = (SELECT sum(on_hand) FROM f360.inventory_balances WHERE location_id <> tr),
    'Inicio: available and in-transit are separate numbers', format('available=%s in_transit=%s', r->>'available_pairs', r->>'in_transit_pairs'));
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_inventory_by_location()$q$);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE (x->>'id')::uuid = tr), 'inventory by location excludes En camino', '');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_get_product(%L)$q$, (SELECT product_id FROM f360.product_variants WHERE id = pg_temp.id('v1'))));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'colors') c, jsonb_array_elements(c->'balances') b WHERE (b->>'location_id')::uuid = tr)
    AND (r->>'in_transit')::int >= 2, 'product: En camino not in location balances, shown as in_transit', r->>'in_transit');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('sel'), tr));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL, 'nobody can be assigned to En camino (so no shift / sale there)', r->>'error');
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1}]')$q$, tr, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('transit', 'v1') = 2, 'merchandise cannot be received directly into En camino', r->>'error');
  PERFORM pg_temp.ok((SELECT NOT sellable AND legacy_channel_id IS NULL FROM f360.locations WHERE id = tr)
    AND NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE fulfillment_location_id = tr), 'En camino: sellable=false, not an online fulfillment location', '');
  r := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_my_locations()$q$);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE (x->>'id')::uuid = tr), 'En camino never offered to start a shift', '');
END $$;

-- ═════ 4 · Receive: permissions, live assignment, exact receipt ═════
DO $$
DECLARE r jsonb; t uuid := pg_temp.id('T1');
BEGIN
  r := pg_temp.as(pg_temp.id('sel2'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('B', 'v1') = 0, 'seller NOT assigned to the destination cannot receive', r->>'error');
  r := pg_temp.as(pg_temp.id('viewer'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('B', 'v1') = 0, 'viewer cannot receive', r->>'error');
  PERFORM pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_set_location_assignment(%L, %L, false)$q$, pg_temp.id('sel'), pg_temp.id('B')));
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL AND pg_temp.bal('B', 'v1') = 0, 'revoked assignment cuts permission immediately', r->>'error');
  PERFORM pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_set_location_assignment(%L, %L, true)$q$, pg_temp.id('sel'), pg_temp.id('B')));
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":3}]')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%más pares de los que se enviaron%', 'received > sent refused', r->>'error');
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'status' = 'received' AND pg_temp.bal('transit', 'v1') = 0 AND pg_temp.bal('B', 'v1') = 2 AND pg_temp.bal('A', 'v1') = 3,
    'seller assigned to destination confirms → exact receipt: En camino −2, destination +2', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no está en camino%' AND pg_temp.bal('B', 'v1') = 2, 'second receipt refused', r->>'error');
  PERFORM pg_temp.ledger_ok('exact receipt');
END $$;

-- ═════ 5 · Partial receipt: with_difference; the gap stays identified until resolved ═════
DO $$
DECLARE r jsonb; t uuid; rs jsonb;
BEGIN
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":2},{"variant_id":"%s","quantity":1}]', NULL, true)$q$,
         pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1'), pg_temp.id('v2')));
  t := (r->>'id')::uuid; INSERT INTO t_ids VALUES ('T2', t);
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND pg_temp.bal('A', 'v1') = 1 AND pg_temp.bal('A', 'v2') = 0 AND pg_temp.bal('transit', 'v1') = 2 AND pg_temp.bal('transit', 'v2') = 1,
    'operator request+send in one step (atomic)', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1},{"variant_id":"%s","quantity":1}]')$q$, t, pg_temp.id('v1'), pg_temp.id('v2')));
  PERFORM pg_temp.ok(r->>'status' = 'with_difference' AND pg_temp.bal('B', 'v1') = 3 AND pg_temp.bal('B', 'v2') = 1 AND pg_temp.bal('transit', 'v1') = 1,
    'partial receipt → with_difference; received pairs reach destination', coalesce(r->>'error', r->>'status'));
  PERFORM pg_temp.ok((SELECT sent_qty = 2 AND received_qty = 1 FROM f360.transfer_lines WHERE transfer_id = t AND variant_id = pg_temp.id('v1'))
    AND (r->'totals'->>'outstanding')::int = 1, 'sent and received recorded per variant; 1 pair outstanding', r->>'totals');
  PERFORM pg_temp.ok(pg_temp.bal('transit', 'v1') = 1, 'the missing pair does NOT disappear: still in En camino, identified by the transfer', '');
  rs := pg_temp.as(pg_temp.id('owner'), $q$SELECT public.f360_list_transfers('with_difference')$q$);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(rs->'items') x WHERE (x->>'id')::uuid = t) AND (rs->'counts'->>'with_difference')::int >= 1,
    'listed under "Con diferencia" until resolved', rs->>'counts');
  PERFORM pg_temp.ledger_ok('partial receipt');

  -- resolution: explicit, authorized, with reason; only the outstanding quantity
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_resolve_transfer_difference(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1,"action":"return"}]', 'apareció en bodega')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo operación%', 'seller cannot resolve a difference', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_resolve_transfer_difference(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1,"action":"return"}]', '')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%motivo%', 'resolution without reason refused', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_resolve_transfer_difference(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2,"action":"return"}]', 'apareció')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Solo faltan 1%', 'cannot resolve more than the outstanding quantity', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_resolve_transfer_difference(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1,"action":"return"}]', 'Se quedó en bodega al empacar')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'status' = 'closed' AND pg_temp.bal('transit', 'v1') = 0 AND pg_temp.bal('A', 'v1') = 2,
    'resolve by RETURN: En camino → origin; transfer closed', coalesce(r->>'error', r->>'status'));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.inventory_events WHERE event_type = 'RETURN' AND business_reference_id = r->>'number' AND note LIKE '%Se quedó en bodega%'),
    'RETURN event in the ledger carries the reason', '');
  PERFORM pg_temp.ledger_ok('resolve by return');
END $$;

-- ═════ 6 · Nothing arrived → write-off with reason ═════
DO $$
DECLARE r jsonb; t uuid;
BEGIN
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]', NULL, true)$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')));
  t := (r->>'id')::uuid;
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":0}]')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'status' = 'with_difference' AND pg_temp.bal('transit', 'v1') = 1 AND pg_temp.bal('B', 'v1') = 3, 'receipt of 0 → with_difference, pair stays En camino', coalesce(r->>'error', r->>'status'));
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_resolve_transfer_difference(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1,"action":"write_off"}]', 'Caja dañada en paquetería')$q$, t, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'status' = 'closed' AND pg_temp.bal('transit', 'v1') = 0 AND pg_temp.bal('A', 'v1') = 1,
    'resolve by WRITE_OFF (baja con motivo): leaves En camino, closed', coalesce(r->>'error', r->>'status'));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.inventory_events e JOIN f360.inventory_movements m ON m.event_id = e.id WHERE e.event_type = 'WRITE_OFF'
    AND e.business_reference_id = r->>'number' AND m.to_location_id IS NULL AND e.note LIKE '%Caja dañada%'), 'WRITE_OFF event recorded with reason', '');
  PERFORM pg_temp.ledger_ok('write-off');
END $$;

-- ═════ 7 · No reservation; insufficient stock at send; last pair; cancel ═════
DO $$
DECLARE r jsonb; t4 uuid; t5 uuid; t6 uuid;
BEGIN
  -- origin now: v1 = 1, v2 = 0. Two requests for the same last pair both succeed (a request reserves nothing)…
  t4 := (pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')))->>'id')::uuid;
  t5 := (pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('A'), pg_temp.id('B'), pg_temp.id('v1')))->>'id')::uuid;
  PERFORM pg_temp.ok(t4 IS NOT NULL AND t5 IS NOT NULL AND pg_temp.bal('A', 'v1') = 1, 'two requests for the last pair: both recorded, nothing reserved', '');
  -- …but only one send can take it
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t4));
  PERFORM pg_temp.ok(r->>'status' = 'in_transit', 'first send takes the last pair', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t5));
  PERFORM pg_temp.ok(r->>'error' LIKE '%No hay suficientes pares%No se envió nada%' AND pg_temp.bal('A', 'v1') = 0 AND (SELECT status FROM f360.transfers WHERE id = t5) = 'requested',
    'second send refused; origin never negative; request stays pending', r->>'error');
  -- multi-line send is all-or-nothing
  t6 := (pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":2},{"variant_id":"%s","quantity":1}]')$q$, pg_temp.id('B'), pg_temp.id('A'), pg_temp.id('v1'), pg_temp.id('v2')))->>'id')::uuid;
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":1},{"variant_id":"%s","quantity":1}]')$q$, t6, pg_temp.id('v1'), pg_temp.id('v2')));
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND pg_temp.bal('B', 'v1') = 2 AND pg_temp.bal('B', 'v2') = 0, 'partial send quantities (≤ requested) accepted', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1},{"variant_id":"%s","quantity":5}]', NULL, true)$q$, pg_temp.id('B'), pg_temp.id('A'), pg_temp.id('v1'), pg_temp.id('v2')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%No hay suficientes pares%' AND pg_temp.bal('B', 'v1') = 2, 'one short line → whole send refused, nothing moved (and no request left behind)', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2}]')$q$, t5, pg_temp.id('v1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%más pares de los solicitados%', 'cannot send more than requested', r->>'error');
  -- cancel: the requester (seller) or operation, only while requested
  r := pg_temp.as(pg_temp.id('sel2'), format($q$SELECT public.f360_cancel_transfer(gen_random_uuid(), %L)$q$, t5));
  PERFORM pg_temp.ok(r->>'error' IS NOT NULL, 'unrelated seller cannot cancel', r->>'error');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_cancel_transfer(gen_random_uuid(), %L, 'ya no se necesita')$q$, t5));
  PERFORM pg_temp.ok(r->>'status' = 'cancelled' AND pg_temp.bal('A', 'v1') = 0, 'cancel a pending request (no stock effect)', coalesce(r->>'error', ''));
  PERFORM pg_temp.ledger_ok('last pair / cancel');
END $$;

-- ═════ 8 · Seller visibility ═════
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.as(pg_temp.id('sel2'), $q$SELECT public.f360_list_transfers('all')$q$);
  PERFORM pg_temp.ok(jsonb_array_length(r->'items') = 0 OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'items') x WHERE x->'to'->>'id' = pg_temp.id('B')::text),
    'seller without assignment sees none of B''s transfers', jsonb_array_length(r->'items')::text);
  r := pg_temp.as(pg_temp.id('sel2'), format($q$SELECT public.f360_get_transfer(%L)$q$, pg_temp.id('T1')));
  PERFORM pg_temp.ok(r->>'error' LIKE '%no encontrada%', 'seller without assignment cannot open a B transfer', r->>'error');
  r := pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_get_transfer(%L)$q$, pg_temp.id('T1')));
  PERFORM pg_temp.ok(r->>'number' IS NOT NULL AND NOT (r->'can'->>'send')::boolean, 'assigned seller sees her transfer; "send" not offered', r->>'can');
END $$;


-- Test fixture (this transaction only): "ZZ Publicado", an F360 model already published to channel p_target
-- (Nude 37, 2800 MXN, ready, linked to Woo product 990001 / variation 990011, published hash current), p_pairs in Bodega CDMX.
CREATE FUNCTION pg_temp.zz_published(p_target text, p_pairs int DEFAULT 0) RETURNS uuid LANGUAGE plpgsql AS $fx$
DECLARE pid uuid; cid uuid; vid uuid; t uuid := (SELECT id FROM f360.sales_targets WHERE key = p_target);
BEGIN
  INSERT INTO f360.products (name, slug, code, category_key, regular_price, description)
    VALUES ('ZZ Publicado', 'zz-publicado', 'ZZ-PUBLICADO', 'ballerinas', 2800, 'Fixture de prueba') RETURNING id INTO pid;
  INSERT INTO f360.product_sizes (product_id, label, sort) VALUES (pid, '37', 1);
  INSERT INTO f360.product_colors (product_id, name, code, sort) VALUES (pid, 'Nude', 'NUDE', 1) RETURNING id INTO cid;
  INSERT INTO f360.product_variants (product_id, color_id, size_label) VALUES (pid, cid, '37') RETURNING id INTO vid;
  PERFORM f360.refresh_skus(pid);
  INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', 'f360/ZZ-PUBLICADO/NUDE/a.png');
  INSERT INTO f360.product_media (product_id, color_id, storage_path, sort) VALUES (pid, cid, 'f360/ZZ-PUBLICADO/NUDE/a.png', 1);
  INSERT INTO f360.woo_product_links (target_id, product_id, woo_product_id, woo_status, published_hash, last_success_at)
    VALUES (t, pid, 990001, 'publish', f360.publish_hash(pid), now());
  INSERT INTO f360.woo_variant_links (target_id, variant_id, woo_variation_id) VALUES (t, vid, 990011);
  IF p_pairs > 0 THEN
    INSERT INTO f360.inventory_balances (variant_id, location_id, on_hand) SELECT vid, id, p_pairs FROM f360.locations WHERE name = 'Bodega CDMX';
  END IF;
  RETURN pid;
END $fx$;

-- ═════ 9b · Online store: a send FROM the online fulfillment location queues a Woo stock push at send; TO it, only at receipt ═════
DO $$
DECLARE r jsonb; t uuid; v uuid; pub uuid; bod uuid := (SELECT fulfillment_location_id FROM f360.sales_targets WHERE active ORDER BY created_at LIMIT 1);
BEGIN
  -- the online store's linked variant: this test's own published model (rolled back)
  pub := pg_temp.zz_published((SELECT key FROM f360.sales_targets WHERE active AND fulfillment_location_id = bod ORDER BY created_at LIMIT 1));
  SELECT id INTO v FROM f360.product_variants WHERE product_id = pub;
  PERFORM pg_temp.ok(v IS NOT NULL, 'fixture: a variant linked to the online store exists', '');
  -- 2 pairs into the online bodega for this test only (rolled back)
  PERFORM pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2}]')$q$, bod, v));
  DELETE FROM f360.stock_sync_queue WHERE variant_id = v;          -- rolled back with everything else
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]')$q$, bod, pg_temp.id('B'), v));
  t := (r->>'id')::uuid;
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v), 'request from the online bodega: no Woo push (nothing moved)', '');
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_send_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v),
    'send from the online bodega queues a Woo stock push immediately (pairs no longer sellable online)', coalesce(r->>'error', ''));
  PERFORM pg_temp.ok(f360.online_ats(v, bod) = (SELECT on_hand FROM f360.inventory_balances WHERE variant_id = v AND location_id = bod),
    'online availability = bodega on hand (En camino never counted)', f360.online_ats(v, bod)::text);
  -- the other direction: B → online bodega; the push happens only when the bodega confirms receipt
  PERFORM pg_temp.as(pg_temp.id('sel'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  DELETE FROM f360.stock_sync_queue WHERE variant_id = v;
  r := pg_temp.as(pg_temp.id('op'), format($q$SELECT public.f360_request_transfer(gen_random_uuid(), %L, %L, '[{"variant_id":"%s","quantity":1}]', NULL, true)$q$, pg_temp.id('B'), bod, v));
  t := (r->>'id')::uuid;
  PERFORM pg_temp.ok(r->>'status' = 'in_transit' AND NOT EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v), 'sent TO the online bodega: no push while en camino', coalesce(r->>'error', ''));
  r := pg_temp.as(pg_temp.id('owner'), format($q$SELECT public.f360_receive_transfer(gen_random_uuid(), %L)$q$, t));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.stock_sync_queue WHERE variant_id = v), 'push queued when the online bodega confirms receipt', coalesce(r->>'error', ''));
  PERFORM pg_temp.ledger_ok('online bodega round trip');
END $$;

-- ═════ 9 · Audit + immutability ═════
DO $$
DECLARE err text; t uuid := pg_temp.id('T2');
BEGIN
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.transfer_changes h WHERE h.actor_name IS NULL OR h.at IS NULL OR h.from_location_name IS NULL OR h.to_location_name IS NULL
      OR (h.action IN ('request', 'send', 'receive', 'resolve') AND jsonb_array_length(h.lines) = 0))
    AND (SELECT array_agg(action ORDER BY id) FROM f360.transfer_changes WHERE transfer_id = t) = ARRAY['request', 'send', 'receive', 'resolve'],
    'every transition audited: actor, time, origin, destination, variants and quantities', (SELECT array_agg(action ORDER BY id)::text FROM f360.transfer_changes WHERE transfer_id = t));
  BEGIN UPDATE f360.transfers SET to_location_id = pg_temp.id('A') WHERE id = t; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede editar%', 'transfer origin/destination cannot be edited (even by the database owner)', err);
  BEGIN UPDATE f360.transfers SET status = 'requested' WHERE id = t; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no permitido%', 'status cannot go backwards', err);
  BEGIN UPDATE f360.transfer_lines SET received_qty = 2 WHERE transfer_id = t AND variant_id = pg_temp.id('v1'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede editar%', 'received quantity cannot be rewritten', err);
  BEGIN DELETE FROM f360.transfers WHERE id = t; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede borrar%', 'transfer cannot be deleted', err);
  BEGIN UPDATE f360.transfer_changes SET actor_name = 'x' WHERE transfer_id = t; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%', 'transfer audit is append-only', err);
  BEGIN DELETE FROM f360.inventory_movements WHERE event_id = (SELECT send_event_id FROM f360.transfers WHERE id = t); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%no se puede modificar%', 'ledger movements of a transfer are append-only', err);
  err := (pg_temp.as(pg_temp.id('owner'), format($q$SELECT to_jsonb(count(*)) FROM f360.transfers$q$)))->>'error';
  PERFORM pg_temp.ok(err LIKE '%permission denied%', 'clients cannot touch transfer tables directly', err);
END $$;

-- ═════ 10 · Isolation from the legacy system ═════
SELECT pg_temp.ok((SELECT ci FROM t_snap) = pg_temp.ci_hash(), 'no write to public.channel_inventory in any scenario', '');
SELECT pg_temp.ok((SELECT sales FROM t_snap) = (SELECT count(*) FROM public.offline_sales), 'no legacy sale created', '');
SELECT pg_temp.ok(to_regclass('public.inventory_events') IS NULL, 'no second ledger (public.inventory_events does not exist)', '');
SELECT pg_temp.ledger_ok('all scenarios');

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 100) FROM t_results ORDER BY n;
ROLLBACK;
