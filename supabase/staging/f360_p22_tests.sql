-- Fuxia 360 P2.2 (Woo publishing infrastructure) — database tests (STAGING). One transaction, ROLLED BACK.
BEGIN;
CREATE TEMP TABLE t_results (n serial, status text, name text, detail text) ON COMMIT DROP;
GRANT ALL ON t_results TO authenticated, anon, service_role;
GRANT USAGE, SELECT ON SEQUENCE t_results_n_seq TO authenticated, anon, service_role;
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid) ON COMMIT DROP;
GRANT ALL ON t_ids TO authenticated, anon, service_role;

CREATE FUNCTION pg_temp.as_user(p_uid uuid, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
END $$;
GRANT EXECUTE ON FUNCTION pg_temp.as_user(uuid, text) TO authenticated, anon, service_role;
CREATE FUNCTION pg_temp.ok(p_cond boolean, p_name text, p_detail text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO t_results(status,name,detail) VALUES (CASE WHEN coalesce(p_cond, false) THEN 'PASS' ELSE 'FAIL' END, p_name, p_detail) $$;
GRANT EXECUTE ON FUNCTION pg_temp.ok(boolean, text, text) TO authenticated, anon, service_role;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT auth_user_id AS mario FROM f360.user_roles WHERE display_name = 'Mario' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT id AS c2 FROM auth.users WHERE email = '15550100012@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.mario', :'mario', true), set_config('t.c1', :'c1', true), set_config('t.c2', :'c2', true) \gset t_
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c1', 'viewer', 'Viewer de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'viewer', display_name = 'Viewer de prueba', granted_by = 'test (rolled back)';
INSERT INTO f360.user_roles (auth_user_id, role, display_name, granted_by) VALUES (:'c2', 'operator', 'Operadora de prueba', 'test (rolled back)')
  ON CONFLICT (auth_user_id) DO UPDATE SET role = 'operator', display_name = 'Operadora de prueba', granted_by = 'test (rolled back)';

-- Fixture: a test target (the only active one inside this transaction) + a ready product with photos
UPDATE f360.sales_targets SET active = false;
INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id) SELECT 'woo_test_tx', 'Prueba', 'http://localhost:9', id FROM f360.locations WHERE name = 'Bodega CDMX';
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; p jsonb; c jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Publicar Prueba', ARRAY['35','36'], '[{"name":"Nude"},{"name":"Negro"}]'::jsonb);
  RESET ROLE;
  INSERT INTO t_ids VALUES ('p', (p->>'id')::uuid);
  INSERT INTO storage.objects (bucket_id, name) SELECT 'product-images', 'f360/ZZ-PUBLICAR-PRUEBA/' || (x->>'code') || '/a.png' FROM jsonb_array_elements(p->'colors') x;
  PERFORM pg_temp.as_user(u, 'authenticated');
  PERFORM public.f360_update_product((p->>'id')::uuid, '{"regular_price":2800,"category_key":"ballerinas","description":"x"}');
  FOR c IN SELECT x FROM jsonb_array_elements(p->'colors') x LOOP
    PERFORM public.f360_add_media((p->>'id')::uuid, (c->>'id')::uuid, ARRAY['f360/ZZ-PUBLICAR-PRUEBA/' || (c->>'code') || '/a.png']);
  END LOOP;
  RESET ROLE;
END $$;

-- 1–3. Category must be linked to the target by ID before publishing
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); err text; st jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  st := public.f360_publication_status(pid);
  PERFORM pg_temp.ok(st->>'state' = 'listo' AND (st->>'can_publish')::boolean, 'ready product shows "listo" and owner can publish', st->>'state');
  BEGIN PERFORM public.f360_request_publish(pid, gen_random_uuid()); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err LIKE '%categoría%no está vinculada%', 'unlinked category blocks publishing', err);
  RESET ROLE;
  INSERT INTO f360.woo_category_links (target_id, category_key, woo_term_id, woo_slug) SELECT id, 'ballerinas', 30, 'ballerinas' FROM f360.sales_targets WHERE key = 'woo_test_tx';
  BEGIN INSERT INTO f360.woo_category_links (target_id, category_key, woo_term_id, woo_slug) SELECT id, 'botas', 30, 'botas' FROM f360.sales_targets WHERE key = 'woo_test_tx'; err := 'accepted';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'one Woo category id cannot map two F360 categories', err);
END $$;

-- 4–6. Owner-only (DW8): operator and viewer cannot request; anon cannot call
DO $$
DECLARE pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); err text; st jsonb;
BEGIN
  PERFORM pg_temp.as_user(current_setting('t.c2')::uuid, 'authenticated');
  st := public.f360_publication_status(pid);
  BEGIN PERFORM public.f360_request_publish(pid, gen_random_uuid()); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted' AND NOT (st->>'can_publish')::boolean, 'operator cannot publish (sees status, no button)', err);
  PERFORM pg_temp.as_user(current_setting('t.c1')::uuid, 'authenticated');
  BEGIN PERFORM public.f360_request_publish(pid, gen_random_uuid()); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'viewer cannot publish', err);
  PERFORM pg_temp.as_user(NULL, 'anon');
  BEGIN PERFORM public.f360_publication_status(pid); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'anon cannot read publication status', err);
END $$;

-- 7–11. Request: idempotent, one active job, worker RPCs are NOT callable by users
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); k uuid := gen_random_uuid();
  j1 jsonb; j2 jsonb; j3 jsonb; err text; st jsonb;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  j1 := public.f360_request_publish(pid, k);
  j2 := public.f360_request_publish(pid, k);
  j3 := public.f360_request_publish(pid, gen_random_uuid());
  st := public.f360_publication_status(pid);
  PERFORM pg_temp.ok(j1->>'status' = 'queued' AND j2->>'id' = j1->>'id' AND (j2->>'replayed')::boolean, 'same request key → same job (double click safe)', j1->>'status');
  PERFORM pg_temp.ok(j3->>'id' = j1->>'id' AND (j3->>'already_active')::boolean, 'a second publish while one is active returns the active job', '');
  PERFORM pg_temp.ok(st->>'state' = 'publicando' AND NOT (st->>'can_publish')::boolean, 'status "publicando" while active', st->>'state');
  BEGIN PERFORM public.f360_pub_claim((j1->>'id')::uuid, u); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'an owner cannot call the worker claim directly', err);
  BEGIN PERFORM public.f360_pub_link((j1->>'id')::uuid, 'product', pid, 5); err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'an owner cannot write Woo links directly', err);
  RESET ROLE;
  INSERT INTO t_ids VALUES ('job', (j1->>'id')::uuid);
END $$;

-- 12–15. Worker (service_role): claim checks requester + owner, locks codes, returns the snapshot
DO $$
DECLARE pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); jid uuid := (SELECT v FROM t_ids WHERE k = 'job'); s jsonb; err text;
BEGIN
  PERFORM pg_temp.as_user(NULL, 'service_role');
  BEGIN PERFORM public.f360_pub_claim(jid, current_setting('t.mario')::uuid); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'claim refuses a caller who did not request the job', err);
  s := public.f360_pub_claim(jid, current_setting('t.carolina')::uuid);
  PERFORM pg_temp.ok(jsonb_array_length(s->'variants') = 4 AND s->'product'->'woo_category'->>'id' = '30' AND s->'product'->>'code' = 'ZZ-PUBLICAR-PRUEBA'
    AND (SELECT bool_and(v->>'sku' LIKE 'F360-ZZ-PUBLICAR-PRUEBA-%') FROM jsonb_array_elements(s->'variants') v),
    'snapshot: 2 colors × 2 sizes, SKUs, category id', jsonb_array_length(s->'variants')::text);
  BEGIN PERFORM public.f360_pub_claim(jid, current_setting('t.carolina')::uuid); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'a running job cannot be claimed twice', err);
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT codes_locked_at IS NOT NULL FROM f360.products WHERE id = pid), 'claim locks product/color codes (DW9)', '');
END $$;

-- 16–20. Links scoped to the job's product; steps append-only; finish → publicado; edit → cambios; failure → error
DO $$
DECLARE pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); jid uuid := (SELECT v FROM t_ids WHERE k = 'job'); err text; st jsonb; other uuid; j2 jsonb; vid uuid;
BEGIN
  SELECT id INTO other FROM f360.product_variants WHERE product_id <> pid LIMIT 1;
  SELECT id INTO vid FROM f360.product_variants WHERE product_id = pid LIMIT 1;
  PERFORM pg_temp.as_user(NULL, 'service_role');
  PERFORM public.f360_pub_step(jid, 'product', 'F360-ZZ-PUBLICAR-PRUEBA', 'create', 501, true, 'Creado como draft');
  PERFORM public.f360_pub_link(jid, 'product', pid, 501, '{"status":"draft"}');
  PERFORM public.f360_pub_link(jid, 'variant', vid, 601, '{"stock":4}');
  IF other IS NOT NULL THEN
    BEGIN PERFORM public.f360_pub_link(jid, 'variant', other, 602); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
    PERFORM pg_temp.ok(err <> 'accepted', 'worker cannot link a variant of another product', err);
  END IF;
  PERFORM public.f360_pub_finish(jid, 'succeeded', NULL, '{"woo_status":"draft"}');
  RESET ROLE;
  BEGIN UPDATE f360.sync_job_steps SET message = 'x' WHERE job_id = jid; err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  PERFORM pg_temp.ok(err <> 'accepted', 'publication history is append-only', err);
  PERFORM pg_temp.ok((SELECT last_pushed_stock FROM f360.woo_variant_links WHERE variant_id = vid) = 4, 'variant link stores Woo id + pushed stock', '');

  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  st := public.f360_publication_status(pid);
  PERFORM pg_temp.ok(st->>'state' = 'publicado' AND st->>'woo_product_id' = '501' AND jsonb_array_length(st->'jobs'->0->'steps') = 1, 'status "publicado" with Woo id and step history', st->>'state');
  PERFORM public.f360_update_product(pid, '{"description":"otra"}');
  st := public.f360_publication_status(pid);
  PERFORM pg_temp.ok(st->>'state' = 'cambios', 'editing after publishing → "cambios pendientes"', st->>'state');
  j2 := public.f360_request_publish(pid, gen_random_uuid());
  RESET ROLE;
  PERFORM pg_temp.as_user(NULL, 'service_role');
  PERFORM public.f360_pub_claim((j2->>'id')::uuid, current_setting('t.carolina')::uuid);
  PERFORM public.f360_pub_finish((j2->>'id')::uuid, 'failed', 'Error de la tienda: timeout');
  RESET ROLE;
  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  st := public.f360_publication_status(pid);
  PERFORM pg_temp.ok(st->>'state' = 'error' AND st->'jobs'->0->>'error_message' LIKE '%timeout%' AND (st->>'can_publish')::boolean, 'failed job → "error" with message, retry allowed', st->>'state');
  RESET ROLE;
  -- a failed job does NOT overwrite the last good published hash
  PERFORM pg_temp.ok((SELECT last_job_id FROM f360.woo_product_links WHERE product_id = pid) = jid, 'a failed run keeps the last successful publication', '');
END $$;

-- 21. Stale running job (worker died) → expires, a new request is allowed
DO $$
DECLARE pid uuid := (SELECT v FROM t_ids WHERE k = 'p'); j jsonb; j2 jsonb;
BEGIN
  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  j := public.f360_request_publish(pid, gen_random_uuid());
  RESET ROLE;
  UPDATE f360.sync_jobs SET status = 'running', heartbeat_at = now() - interval '11 minutes', created_at = now() - interval '11 minutes' WHERE id = (j->>'id')::uuid;
  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  j2 := public.f360_request_publish(pid, gen_random_uuid());
  RESET ROLE;
  PERFORM pg_temp.ok(j2->>'id' <> j->>'id' AND (SELECT status FROM f360.sync_jobs WHERE id = (j->>'id')::uuid) = 'failed', 'interrupted job expires after 10 min; new request allowed', '');
END $$;

-- 22. Not ready → cannot publish
DO $$
DECLARE u uuid := current_setting('t.carolina')::uuid; p jsonb; err text;
BEGIN
  PERFORM pg_temp.as_user(u, 'authenticated');
  p := public.f360_create_product('ZZ Sin Fotos', ARRAY['35'], '[{"name":"Nude"}]'::jsonb);
  BEGIN PERFORM public.f360_request_publish((p->>'id')::uuid, gen_random_uuid()); err := 'accepted'; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err LIKE '%no está listo%', 'a draft (not ready) product cannot be published', err);
END $$;

-- 23. New tables are not directly accessible
DO $$ DECLARE err text; BEGIN
  PERFORM pg_temp.as_user(current_setting('t.carolina')::uuid, 'authenticated');
  BEGIN PERFORM count(*) FROM f360.woo_product_links; err := 'accepted'; EXCEPTION WHEN insufficient_privilege THEN err := SQLERRM; END;
  RESET ROLE;
  PERFORM pg_temp.ok(err <> 'accepted', 'no direct access to link/job tables', err);
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 90) FROM t_results ORDER BY n;
ROLLBACK;
