-- App welcome photo (20261018000100) — database tests (STAGING). One transaction, ROLLED BACK.
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
DECLARE car uuid := current_setting('t.carolina')::uuid; r jsonb; v_path text; v_pid uuid; n int; seller uuid;
BEGIN
  SELECT m.storage_path, m.product_id INTO v_path, v_pid FROM f360.product_media m
    JOIN storage.objects o ON o.bucket_id = 'product-images' AND o.name = m.storage_path LIMIT 1;
  PERFORM pg_temp.ok(v_path IS NOT NULL, 'fixture: a catalog photo that exists in storage', coalesce(v_path, 'none'));

  -- anon can read, cannot set, cannot read admin
  r := pg_temp.as(NULL, $q$SELECT public.f360_app_welcome_photo()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'path' AND NOT r ? 'error', 'anon reads the current photo', r::text);
  r := pg_temp.as(NULL, format($q$SELECT public.f360_set_app_welcome_photo(%L)$q$, v_path), 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot set the photo', r::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_app_welcome_admin()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read admin view', r::text);
  r := pg_temp.as(NULL, $q$SELECT to_jsonb(count(*)) FROM f360.app_welcome_photos$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read the table directly', r::text);

  -- an authenticated account without an f360 role cannot set
  r := pg_temp.as(gen_random_uuid(), format($q$SELECT public.f360_set_app_welcome_photo(%L)$q$, v_path));
  PERFORM pg_temp.ok(r ? 'error', 'no-role account cannot set', r::text);

  -- validation
  r := pg_temp.as(car, $q$SELECT public.f360_set_app_welcome_photo('f360/no/existe.jpg')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%no se subió%', 'missing file rejected', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_app_welcome_photo('otros/x.jpg')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%no es válida%', 'path outside f360/ rejected', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_app_welcome_photo('f360/../x.jpg')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%no es válida%', 'path traversal rejected', r::text);

  -- Carolina sets a catalog photo: anon sees it, history records who
  r := pg_temp.as(car, format($q$SELECT public.f360_set_app_welcome_photo(%L, %L::uuid)$q$, v_path, v_pid));
  PERFORM pg_temp.ok(r->'current'->>'path' = v_path AND r->'current'->>'by' = 'Carolina' AND r->'current'->>'product' IS NOT NULL,
    'owner sets catalog photo (who + which model recorded)', left((r->'current')::text, 200));
  PERFORM pg_temp.ok(jsonb_array_length(r->'catalog') > 0, 'admin view lists catalog photos', jsonb_array_length(r->'catalog')::text);
  r := pg_temp.as(NULL, $q$SELECT public.f360_app_welcome_photo()$q$, 'anon');
  PERFORM pg_temp.ok(r->>'path' = v_path AND (SELECT count(*) FROM jsonb_object_keys(r)) = 1, 'anon gets only the path', r::text);

  -- back to the store photo
  r := pg_temp.as(car, $q$SELECT public.f360_set_app_welcome_photo(NULL)$q$);
  PERFORM pg_temp.ok(r->'current'->>'path' IS NULL AND jsonb_array_length(r->'history') >= 2, 'revert to store photo keeps history', left(r::text, 160));
  r := pg_temp.as(NULL, $q$SELECT public.f360_app_welcome_photo()$q$, 'anon');
  PERFORM pg_temp.ok(r->'path' = 'null'::jsonb, 'anon sees no own photo after revert', r::text);

  -- append-only
  BEGIN
    UPDATE f360.app_welcome_photos SET set_by_name = 'x';
    PERFORM pg_temp.ok(false, 'history is append-only (update)', 'update went through');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'history is append-only (update)', SQLERRM); END;
  BEGIN
    DELETE FROM f360.app_welcome_photos;
    PERFORM pg_temp.ok(false, 'history is append-only (delete)', 'delete went through');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'history is append-only (delete)', SQLERRM); END;
END $$;

SELECT status, name, detail FROM t_results ORDER BY n;
SELECT count(*) FILTER (WHERE status = 'PASS') AS pass, count(*) FILTER (WHERE status = 'FAIL') AS fail FROM t_results;
ROLLBACK;
