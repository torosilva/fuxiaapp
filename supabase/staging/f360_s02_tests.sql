-- Fuxia 360 · S0.2 seller session — database tests (STAGING). One transaction, ROLLED BACK.
-- Synthetic fixtures only (lab users 555-01xx, "ZZ" locations), all inside this transaction.
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
CREATE FUNCTION pg_temp.shift(p_uid uuid, p_loc uuid, p_pin text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; BEGIN PERFORM pg_temp.as_user(p_uid, 'authenticated'); r := public.f360_start_seller_shift(p_loc, p_pin); RESET ROLE; RETURN r; END $$;
CREATE FUNCTION pg_temp.sess(p_uid uuid, p_token text, p_claim uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb; BEGIN PERFORM pg_temp.as_user(p_uid, 'authenticated'); r := public.f360_seller_session(p_token, p_claim); RESET ROLE; RETURN r; END $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT id AS e1 FROM auth.users WHERE email = 'e1.attacker@staging.invalid' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true), set_config('t.e1', :'e1', true) \gset t_

-- Fixture: two sellable f360 stores, c1 = seller assigned ONLY to A, c2 = viewer
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; a jsonb; b jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  a := public.f360_create_location('ZZ Tienda S02 A', 'store');
  b := public.f360_create_location('ZZ Tienda S02 B', 'store');
  PERFORM public.f360_set_user_role(current_setting('t.c1')::uuid, 'seller', 'Vendedora S02');
  PERFORM public.f360_set_user_role(current_setting('t.c2')::uuid, 'viewer', 'Consulta S02');
  PERFORM public.f360_set_location_assignment(current_setting('t.c1')::uuid, (a->>'id')::uuid, true);
  RESET ROLE;
  INSERT INTO t_ids VALUES ('A', (a->>'id')::uuid, NULL), ('B', (b->>'id')::uuid, NULL);
  -- legacy authority must NOT count: give c2's customer row role 'staff' (the old authority)
  UPDATE public.customers SET role = 'staff' WHERE auth_user_id = current_setting('t.c2')::uuid;
END $$;

DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; A uuid := (SELECT v FROM t_ids WHERE k = 'A'); B uuid := (SELECT v FROM t_ids WHERE k = 'B');
  r jsonb; err text; i int; tok text; tok2 text;
BEGIN
  -- anonymous cannot even call
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_start_seller_shift(A, '1234'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anonymous cannot start a seller shift', err);

  r := pg_temp.shift(current_setting('t.e1')::uuid, A, '1234');
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%no puede iniciar turno%', 'authenticated user with no f360 role cannot', r::text);
  r := pg_temp.shift(current_setting('t.c2')::uuid, A, '1234');
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean, 'customers.role=staff (legacy authority) and f360 viewer cannot', r::text);

  DELETE FROM f360.seller_credentials WHERE auth_user_id = c1;   -- the lab user may carry a demo PIN (rolled back anyway)
  r := pg_temp.shift(c1, A, '1234');
  PERFORM pg_temp.ok(r->>'error' LIKE '%no tienes PIN%', 'seller without PIN cannot', r::text);

  PERFORM pg_temp.as_user(c1, 'authenticated');
  BEGIN PERFORM public.f360_set_seller_pin(c1, '4321'); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'a seller cannot set PINs', err);
  PERFORM pg_temp.as_user(u, 'authenticated');
  BEGIN PERFORM public.f360_set_seller_pin(c1, '12a4'); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  r := public.f360_set_seller_pin(c1, '4321');
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%4 dígitos%' AND r::text NOT LIKE '%4321%', 'PIN: 4 digits; the response never contains the PIN', r::text);
  PERFORM pg_temp.ok((SELECT pin_hash LIKE '$2%' AND pin_hash NOT LIKE '%4321%' FROM f360.seller_credentials WHERE auth_user_id = c1), 'PIN stored ONLY as a bcrypt hash', '');

  r := pg_temp.shift(c1, B, '4321');
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%No tienes asignada%'
    AND (SELECT failed_attempts FROM f360.seller_credentials WHERE auth_user_id = c1) = 0, 'unassigned location refused BEFORE the PIN (no attempt consumed)', r::text);

  FOR i IN 1..4 LOOP r := pg_temp.shift(c1, A, '0000'); END LOOP;
  PERFORM pg_temp.ok(r->>'error' LIKE '%Te quedan 1%', 'wrong PIN counts down', r->>'error');
  r := pg_temp.shift(c1, A, '0000');
  PERFORM pg_temp.ok(r->>'error' LIKE '%Bloqueado por 15%', '5th wrong PIN → temporary lock (15 min)', r->>'error');
  r := pg_temp.shift(c1, A, '4321');
  PERFORM pg_temp.ok((r->>'locked')::boolean AND NOT (r->>'ok')::boolean, 'correct PIN while locked is still refused', r->>'error');

  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_unlock_seller(c1); RESET ROLE;
  r := pg_temp.shift(c1, A, '4321');
  tok := r->>'token';
  PERFORM pg_temp.ok((r->>'ok')::boolean AND length(tok) = 64 AND r->'location'->>'name' = 'ZZ Tienda S02 A', 'after unlock: seller → assigned location → valid shift', (r->'location')::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.seller_sessions WHERE token_hash = tok) AND EXISTS (SELECT 1 FROM f360.seller_sessions WHERE token_hash = f360.token_hash(tok)),
    'only the token HASH is stored', '');

  r := pg_temp.sess(c1, tok);
  PERFORM pg_temp.ok((r->>'ok')::boolean AND r->'location'->>'id' = A::text, 'session check: location comes from the SESSION', '');
  r := pg_temp.sess(c1, tok, B);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%no es la de tu turno%', 'a location sent by the client that differs from the shift is refused', r->>'error');
  r := pg_temp.sess(u, tok);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean, 'another person cannot use the token', r->>'error');

  -- READ vs OPERATE
  PERFORM pg_temp.as_user(c1, 'authenticated');
  r := public.f360_inventory_by_location(B);
  RESET ROLE;
  PERFORM pg_temp.ok(r IS NOT NULL, 'seller can READ stock of a location she is not assigned to', '');
  r := pg_temp.shift(c1, B, '4321');
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean, '...but cannot OPERATE there (no shift)', r->>'error');

  -- location change = new shift; previous one revoked
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_set_location_assignment(c1, B, true); RESET ROLE;
  r := pg_temp.shift(c1, B, '4321'); tok2 := r->>'token';
  PERFORM pg_temp.ok((r->>'ok')::boolean AND NOT (pg_temp.sess(c1, tok)->>'ok')::boolean AND (pg_temp.sess(c1, tok2)->>'ok')::boolean,
    'changing location closes the previous shift (one active shift)', '');

  -- immediate revocation
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_set_location_assignment(c1, B, false); RESET ROLE;
  r := pg_temp.sess(c1, tok2);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND (SELECT revoked_at IS NOT NULL FROM f360.seller_sessions WHERE token_hash = f360.token_hash(tok2)),
    'revoking the assignment kills the active shift immediately', r->>'error');

  r := pg_temp.shift(c1, A, '4321'); tok := r->>'token';
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_set_user_role(c1, 'viewer', 'Vendedora S02'); RESET ROLE;
  PERFORM pg_temp.ok(NOT (pg_temp.sess(c1, tok)->>'ok')::boolean, 'changing the role away from seller kills the shift immediately', '');
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_set_user_role(c1, 'seller', 'Vendedora S02'); RESET ROLE;

  -- expiry and idle
  r := pg_temp.shift(c1, A, '4321'); tok := r->>'token';
  UPDATE f360.seller_sessions SET last_seen_at = now() - interval '121 minutes' WHERE token_hash = f360.token_hash(tok);
  r := pg_temp.sess(c1, tok);
  PERFORM pg_temp.ok(NOT (r->>'ok')::boolean AND r->>'error' LIKE '%venció%', 'idle > 120 min → shift expired', r->>'error');
  r := pg_temp.shift(c1, A, '4321'); tok := r->>'token';
  UPDATE f360.seller_sessions SET expires_at = now() - interval '1 minute' WHERE token_hash = f360.token_hash(tok);
  PERFORM pg_temp.ok(NOT (pg_temp.sess(c1, tok)->>'ok')::boolean, 'absolute expiry (12 h) enforced', '');

  -- PIN reset revokes shifts
  r := pg_temp.shift(c1, A, '4321'); tok := r->>'token';
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_set_seller_pin(c1, '9876'); RESET ROLE;
  PERFORM pg_temp.ok(NOT (pg_temp.sess(c1, tok)->>'ok')::boolean AND NOT (pg_temp.shift(c1, A, '4321')->>'ok')::boolean, 'PIN reset: old shifts and old PIN stop working', '');

  -- hard lock after 10 failures in 24 h (even with unlocks in between)
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_unlock_seller(c1); RESET ROLE;
  FOR i IN 1..4 LOOP r := pg_temp.shift(c1, A, '1111'); END LOOP;
  PERFORM pg_temp.as_user(u, 'authenticated'); PERFORM public.f360_unlock_seller(c1); RESET ROLE;
  FOR i IN 1..5 LOOP r := pg_temp.shift(c1, A, '1111'); END LOOP;
  PERFORM pg_temp.ok((SELECT hard_locked FROM f360.seller_credentials WHERE auth_user_id = c1), '10 failures in 24 h → hard lock until an owner/operator unlocks', r->>'error');

  -- audit: person + location on every attempt; append-only
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.seller_auth_events WHERE auth_user_id = c1 AND event = 'bad_pin' AND person_name = 'Vendedora S02' AND location_name = 'ZZ Tienda S02 A') >= 10
    AND EXISTS (SELECT 1 FROM f360.seller_auth_events WHERE auth_user_id = c1 AND event = 'not_assigned' AND location_name = 'ZZ Tienda S02 B')
    AND EXISTS (SELECT 1 FROM f360.seller_auth_events WHERE auth_user_id = c1 AND event = 'location_mismatch')
    AND EXISTS (SELECT 1 FROM f360.seller_auth_events WHERE auth_user_id = c1 AND event = 'revoked')
    AND EXISTS (SELECT 1 FROM f360.seller_auth_events WHERE auth_user_id = current_setting('t.e1')::uuid AND event = 'not_seller'),
    'audit identifies person AND location for attempts, denials, mismatches and revocations', '');
  BEGIN UPDATE f360.seller_auth_events SET event = 'x'; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'seller audit is append-only', err);
  PERFORM pg_temp.as_user(c1, 'authenticated');
  BEGIN PERFORM count(*) FROM f360.seller_sessions; err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'no direct access to credentials/sessions tables', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
