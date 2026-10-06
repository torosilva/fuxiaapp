-- Fuxia 360 · U1 channel capabilities — database tests (STAGING). One transaction, ROLLED BACK. Synthetic ZZ channels only.
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
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; op uuid := current_setting('t.c1')::uuid; r jsonb; loc uuid; s4 f360.sales_targets; e text;
BEGIN
  SELECT * INTO s4 FROM f360.sales_targets WHERE key = 'woo_staging4';
  -- ══ existing channels unchanged ══
  PERFORM pg_temp.ok(s4.catalog_mode = 'on' AND s4.stock_sync_mode = 'on' AND s4.storefront_enabled AND s4.stock_policy = 'f360_owned' AND s4.allow_term_create AND NOT s4.auto_propagate,
    'staging4 keeps every capability it uses today (catalog, stock, storefront)', to_jsonb(s4)::text);
  PERFORM pg_temp.ok((f360.catalog_target('woo_staging4')).id = s4.id AND (f360.resolve_target('woo_staging4')).id = s4.id AND (f360.target_by_key('woo_staging4')).id = s4.id
    AND (f360.content_target('woo_staging4')).id = s4.id,
    'staging4 resolves for catalog, publishing, stock and content exactly as before', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.sales_targets WHERE NOT is_production AND (catalog_mode <> 'on' OR stock_sync_mode <> 'on' OR NOT storefront_enabled)),
    'every non-production channel was backfilled to its current behaviour', '');

  -- ══ a production channel: everything off by default ══
  SELECT id INTO loc FROM f360.locations WHERE type = 'warehouse' AND status = 'active' LIMIT 1;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active, is_production, is_test)
  VALUES ('zz_prod', 'ZZ Producción', 'https://zz-prod.example', loc, false, true, false);
  PERFORM pg_temp.ok((SELECT catalog_mode = 'off' AND stock_sync_mode = 'off' AND NOT storefront_enabled AND stock_policy = 'woo_owned' AND NOT allow_term_create FROM f360.sales_targets WHERE key = 'zz_prod'),
    'a new production channel starts with every capability OFF', '');
  e := pg_temp.err($q$SELECT f360.catalog_target('zz_prod')$q$);
  PERFORM pg_temp.ok(e LIKE '%no está encendido%', 'catalog refused while production catalog is off', e);
  e := pg_temp.err($q$SELECT f360.content_target('zz_prod')$q$);
  PERFORM pg_temp.ok(e IS NOT NULL, 'content push refused while production catalog is off', e);

  -- ══ turning it on: owner only, typed domain, never stock/storefront ══
  r := pg_temp.as(op, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"catalog_mode":"on"}', 'zz-prod.example')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'a non-owner cannot change channel capabilities', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"catalog_mode":"on"}', 'otra.example')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%dominio%', 'production needs the exact domain typed', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"stock_sync_mode":"on"}', 'zz-prod.example')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%stock de producción%', 'production stock cannot be turned on here', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"storefront_enabled":true}', 'zz-prod.example')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%tienda pública%', 'production storefront cannot be turned on here', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"is_production":false}', 'zz-prod.example')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%no permitidos%', 'only capability fields can be changed', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_set_channel_capabilities('zz_prod', '{"catalog_mode":"on"}', 'ZZ-PROD.example')$q$);
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND r->'capabilities'->>'catalog_mode' = 'on'
    AND EXISTS (SELECT 1 FROM f360.channel_capability_changes c JOIN f360.sales_targets t ON t.id = c.target_id WHERE t.key = 'zz_prod' AND c.by_name = 'Carolina' AND c.after->>'catalog_mode' = 'on'),
    'owner turns the production catalog on with the domain; audited', r::text);

  -- ══ with catalog on: catalog works, everything else still refused ══
  PERFORM pg_temp.ok((f360.catalog_target('zz_prod')).key = 'zz_prod' AND (f360.resolve_target('zz_prod')).key = 'zz_prod' AND (f360.content_target('zz_prod')).key = 'zz_prod',
    'production catalog on → catalog / publishing / content resolve the channel (still inactive)', '');
  e := pg_temp.err($q$SELECT f360.target_by_key('zz_prod')$q$);
  PERFORM pg_temp.ok(e IS NOT NULL, 'stock / orders / counts still refuse the production channel', e);
  e := pg_temp.err($q$SELECT f360.storefront_target('zz_prod')$q$);
  PERFORM pg_temp.ok(e IS NOT NULL, 'the storefront (anon) still cannot see an inactive production channel', e);
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.sales_targets WHERE active) = (SELECT count(*) FROM f360.sales_targets WHERE active AND key <> 'zz_prod'),
    'turning the catalog on does not activate the channel', '');

  -- ══ audit and visibility ══
  BEGIN UPDATE f360.channel_capability_changes SET by_name = 'x' WHERE true; PERFORM pg_temp.ok(false, 'capability changes are append-only', '');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'capability changes are append-only', SQLERRM); END;
  r := pg_temp.as(car, $q$SELECT public.f360_channel_capabilities()$q$);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'key' = 'zz_prod' AND x->>'catalog_mode' = 'on'), 'owners can read every channel''s capabilities', left(r::text, 200));
  r := pg_temp.as(NULL, $q$SELECT public.f360_channel_capabilities()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read channel capabilities', r::text);
END $$;

SELECT status || ' | ' || name || CASE WHEN status = 'FAIL' THEN ' | ' || detail ELSE '' END FROM t_results ORDER BY n;
ROLLBACK;
