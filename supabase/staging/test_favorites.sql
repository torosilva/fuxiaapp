-- Favoritos V1 / V1.1 (20261012000800 + 0900; report gate operator since SB0 D13 20261015000400) — minimal suite (STAGING).
-- One transaction, ALWAYS rolled back. Output: one row per check, PASS/FAIL | name | detail. Synthetic visitors only.
-- Run: psql "$STAGING_DB_URL" -X -A -t -f supabase/staging/test_favorites.sql
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon, service_role;
GRANT USAGE ON SEQUENCE t_results_n_seq TO authenticated, anon, service_role;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text DEFAULT '') RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status, name, detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
CREATE FUNCTION pg_temp.as(p_uid uuid, p_sql text, p_role text DEFAULT 'authenticated') RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text
      ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO r;
    RESET ROLE;
  EXCEPTION WHEN OTHERS THEN RESET ROLE; r := jsonb_build_object('error', SQLERRM, 'sqlstate', SQLSTATE); END;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.new_user(p_role text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE u uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fav-' || u || '@test.invalid', '', now(), now(), now());
  IF p_role IS NOT NULL THEN INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (u, p_role, 'ZZ fav ' || p_role, 'test_favorites'); END IF;
  RETURN u;
END $$;

DO $$
DECLARE wp int; prod uuid; v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid(); v3 uuid := gen_random_uuid();
  r jsonb; row jsonb; op uuid := pg_temp.new_user('operator'); sel uuid := pg_temp.new_user('seller'); i int;
  ev text := '{"target_key":"woo_staging4","market":"mx"}';
BEGIN
  SELECT l.woo_product_id, l.product_id INTO wp, prod FROM f360.woo_product_links l JOIN f360.sales_targets t ON t.id = l.target_id
    WHERE t.key = 'woo_staging4' ORDER BY l.woo_product_id LIMIT 1;
  PERFORM pg_temp.ok(wp IS NOT NULL, 'fixture: a published product on woo_staging4', coalesce(wp::text, 'none'));

  -- who can record (the store endpoint uses the service role; browsers never call it directly)
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v1, 'woo_product_id', wp)), 'anon');
  PERFORM pg_temp.ok(r->>'sqlstate' = '42501', 'record: anon cannot call f360_favorite_record directly', coalesce(r->>'sqlstate', r::text));
  r := pg_temp.as(sel, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v1, 'woo_product_id', wp)));
  PERFORM pg_temp.ok(r->>'sqlstate' = '42501', 'record: an authenticated user cannot call it either', coalesce(r->>'sqlstate', r::text));

  -- validation
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_hack', 'anon_id', v1, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok(r ? 'error', 'record: unknown event refused', coalesce(r->>'error', ''));
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', 'not-a-uuid', 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok(r ? 'error', 'record: invalid visitor id refused', coalesce(r->>'error', ''));
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v1, 'woo_product_id', wp, 'market', 'us')), 'service_role');
  PERFORM pg_temp.ok(r ? 'error', 'record: unknown market refused', coalesce(r->>'error', ''));
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', '{"target_key":"no_existe","market":"mx"}'::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v1, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok(r ? 'error', 'record: unknown channel refused', coalesce(r->>'error', ''));

  -- capture: v1 adds then removes, v2 adds and adds to bag, v3 adds
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v1, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok((r->>'ok')::boolean AND (r->>'identified')::boolean, 'record: add resolved to the canonical model (server-side identity)', r::text);
  PERFORM pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_removed', 'anon_id', v1, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v2, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_add_to_cart', 'anon_id', v2, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v3, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.favorite_events e WHERE e.anon_id IN (v1, v2, v3)) = 5, 'record: 5 append-only events stored', '');
  BEGIN
    UPDATE f360.favorite_events SET event = 'favorite_added' WHERE anon_id = v1;
    PERFORM pg_temp.ok(false, 'events are append-only');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'events are append-only (update refused)', SQLERRM); END;

  -- report: operator yes, seller no (SB0 D13); active = latest add per visitor; add-to-cart keeps the favourite
  r := pg_temp.as(sel, 'SELECT public.f360_favorites_report(''woo_staging4'', 30)');
  PERFORM pg_temp.ok(r->>'sqlstate' = '42501', 'report: seller denied (D13)', coalesce(r->>'sqlstate', ''));
  r := pg_temp.as(op, 'SELECT public.f360_favorites_report(''woo_staging4'', 30)');
  SELECT x INTO row FROM jsonb_array_elements(r->'rows') x WHERE x->>'product_id' = prod::text;
  PERFORM pg_temp.ok(row IS NOT NULL AND (row->>'active')::int >= 2 AND (row->>'adds')::int >= 3 AND (row->>'removes')::int >= 1 AND (row->>'atc')::int >= 1,
    'report: v1 removed → not active; v2 (added + to bag) and v3 active; adds/removes/ATC counted', coalesce(row::text, r::text));
  PERFORM pg_temp.ok(NOT (r::text ~* '"(phone|email|anon_id|customer_id|name_full|address)"'), 'report: no PII / visitor ids in the output', '');

  -- rate limit: 120 events per visitor per hour
  FOR i IN 1..118 LOOP
    PERFORM pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v2, 'woo_product_id', wp)), 'service_role');
  END LOOP;
  r := pg_temp.as(NULL, format('SELECT public.f360_favorite_record(%L)', ev::jsonb || jsonb_build_object('event', 'favorite_added', 'anon_id', v2, 'woo_product_id', wp)), 'service_role');
  PERFORM pg_temp.ok((r->>'limited')::boolean, 'record: the 121st event of a visitor in one hour is rate-limited', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail, ''), 120) FROM t_results ORDER BY n;
ROLLBACK;
