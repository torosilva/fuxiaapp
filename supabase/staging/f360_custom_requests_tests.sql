-- "Lo hacemos a la medida" — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
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
SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT set_config('t.carolina', :'carolina', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; r jsonb; req jsonb := '{"target_key":"woo_staging4","woo_product_id":"145","product_name":"x","color":"Verde olivo","size":"25 MX","store_size":"38","name":"Ana","phone":"+15550100077","country":"mx"}';
BEGIN
  r := public.f360_custom_request_create(req);
  PERFORM pg_temp.ok(r->>'product' = 'Botas Largas' AND EXISTS (SELECT 1 FROM f360.custom_requests WHERE id = (r->>'id')::uuid AND product_id IS NOT NULL AND status = 'nueva'),
    'service records the request, model resolved from the store product', r::text);
  r := pg_temp.as(NULL, format($q$SELECT public.f360_custom_request_create(%L::jsonb)$q$, req), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous visitors cannot write directly', r::text);
  PERFORM public.f360_custom_request_create(req); PERFORM public.f360_custom_request_create(req);
  BEGIN PERFORM public.f360_custom_request_create(req); r := '{}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%solicitudes de hoy%', 'max 3 per phone per day', r::text);
  BEGIN PERFORM public.f360_custom_request_create(jsonb_set(req, '{phone}', '"5512"')); r := '{}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r ? 'error', 'invalid phone refused', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_custom_requests_list()$q$);
  PERFORM pg_temp.ok(r->0->>'phone' = '+15550100077' AND r->0->>'color' = 'Verde olivo', 'team sees the request with the phone to call back', left(r::text, 120));
  r := pg_temp.as(car, format($q$SELECT public.f360_custom_request_set(%L, 'contactada')$q$, r->0->>'id'));
  PERFORM pg_temp.ok(r->>'status' = 'contactada', 'operator marks it contacted', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_custom_requests_list()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anonymous cannot list requests', r::text);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
