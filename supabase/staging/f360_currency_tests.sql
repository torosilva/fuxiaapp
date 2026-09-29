-- Currencies + prices per currency — database tests (STAGING). One transaction, ROLLED BACK.
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
SELECT auth_user_id AS owner FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS op FROM auth.users WHERE email = '15550100021@fuxia.app' \gset
SELECT id AS viewer FROM auth.users WHERE email = '15550100013@fuxia.app' \gset
SELECT id AS mac FROM f360.products WHERE name = 'Macarena' \gset
SELECT set_config('t.owner', :'owner', true), set_config('t.op', :'op', true), set_config('t.viewer', :'viewer', true), set_config('t.mac', :'mac', true) \gset t_

DO $$
DECLARE o uuid := current_setting('t.owner')::uuid; op uuid := current_setting('t.op')::uuid; vw uuid := current_setting('t.viewer')::uuid;
  mac uuid := current_setting('t.mac')::uuid; r jsonb; h0 text; h1 text; st text; j jsonb; snap jsonb;
BEGIN
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'operator', 'ZZ Operación')$q$, op));
  PERFORM pg_temp.as(o, format($q$SELECT public.f360_set_user_role(%L, 'viewer', 'ZZ Consulta')$q$, vw));

  r := pg_temp.as(vw, $q$SELECT public.f360_list_currencies()$q$);
  PERFORM pg_temp.ok((SELECT string_agg(x->>'code', ',' ORDER BY (x->>'sort')::int) FROM jsonb_array_elements(r->'currencies') x) = 'MXN,COP,USD'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'suggestions') s WHERE s->>'currency' = 'COP' AND (s->>'base')::numeric = 2800 AND (s->>'amount')::numeric = 420000),
    'currencies MXN (base), COP, USD; suggestion 2800 MXN → 420000 COP', r::text);
  PERFORM pg_temp.ok((SELECT woo_meta_key FROM f360.currencies WHERE code = 'COP') = '_price_cop' AND (SELECT woo_meta_key FROM f360.currencies WHERE code = 'USD') = '_price_usd'
    AND (SELECT woo_meta_key IS NULL AND is_base FROM f360.currencies WHERE code = 'MXN'), 'COP/USD map to the store fields the variation form uses; MXN = Woo price', '');

  r := pg_temp.as(vw, format($q$SELECT public.f360_product_prices(%L)$q$, mac));
  PERFORM pg_temp.ok((SELECT (x->>'amount')::numeric FROM jsonb_array_elements(r) x WHERE x->>'code' = 'MXN') = 2800
    AND (SELECT (x->>'suggested')::numeric FROM jsonb_array_elements(r) x WHERE x->>'code' = 'COP') = 420000
    AND (SELECT x->>'amount' FROM jsonb_array_elements(r) x WHERE x->>'code' = 'COP') IS NULL, 'Macarena: MXN 2800, COP empty with suggestion 420000 (prefill only)', r::text);

  -- publication state before any price (hash must not change for products without prices)
  st := (pg_temp.as(o, format($q$SELECT public.f360_publication_status(%L, 'woo_staging4')$q$, mac)))->>'state';
  PERFORM pg_temp.ok(st = 'publicado', 'adding currencies did not mark already-published products as changed', st);

  r := pg_temp.as(vw, format($q$SELECT public.f360_set_product_price(%L, 'COP', 420000)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%permiso%', 'viewer cannot set prices', r->>'error');
  r := pg_temp.as(NULL, format($q$SELECT public.f360_set_product_price(%L, 'COP', 420000)$q$, mac), 'anon');
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'anonymous refused', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'MXN', 3000)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%información del producto%', 'the base price is not edited here', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'COP', -5)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%mayor a cero%', 'no negative / zero price', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'COP', 420000.5)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%decimales%', 'decimals follow the currency (COP: 0)', r->>'error');
  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'XXX', 1)$q$, mac));
  PERFORM pg_temp.ok(r->>'error' LIKE '%Moneda no válida%', 'unknown currency refused', r->>'error');

  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'COP', 420000)$q$, mac));
  PERFORM pg_temp.ok((SELECT (x->>'amount')::numeric FROM jsonb_array_elements(r) x WHERE x->>'code' = 'COP') = 420000
    AND (SELECT x->>'updated_by_name' FROM jsonb_array_elements(r) x WHERE x->>'code' = 'COP') = 'ZZ Operación', 'operator sets COP 420000', coalesce(r->>'error', ''));
  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'USD', 170)$q$, mac));
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.price_changes WHERE product_id = mac AND what = 'price') = 2
    AND (SELECT after->>'amount' FROM f360.price_changes WHERE product_id = mac AND currency_code = 'COP' ORDER BY id DESC LIMIT 1) = '420000.00',
    'every price change is in the history (who, before, after)', '');
  st := (pg_temp.as(o, format($q$SELECT public.f360_publication_status(%L, 'woo_staging4')$q$, mac)))->>'state';
  PERFORM pg_temp.ok(st = 'cambios', 'a price change marks the online product as "Cambios pendientes"', st);

  -- the publisher snapshot carries the prices
  j := pg_temp.as(o, format($q$SELECT public.f360_request_publish(%L, gen_random_uuid(), 'woo_staging4')$q$, mac));
  snap := public.f360_pub_claim((j->>'id')::uuid, current_setting('t.owner')::uuid);
  PERFORM pg_temp.ok(snap->'product'->'prices' @> '[{"code":"COP","woo_meta_key":"_price_cop","amount":420000.00},{"code":"USD","woo_meta_key":"_price_usd","amount":170.00}]'::jsonb,
    'the publisher receives COP/USD with their store fields', (snap->'product'->'prices')::text);

  r := pg_temp.as(op, format($q$SELECT public.f360_set_product_price(%L, 'USD', NULL)$q$, mac));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.product_prices WHERE product_id = mac AND currency_code = 'USD')
    AND (SELECT after FROM f360.price_changes WHERE product_id = mac AND currency_code = 'USD' ORDER BY id DESC LIMIT 1) IS NULL, 'a price can be cleared (audited)', '');

  -- currencies
  r := pg_temp.as(op, $q$SELECT public.f360_save_currency('EUR', 'Euro', '€', 2, '_price_eur')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%permiso%', 'only an owner adds currencies', r->>'error');
  r := pg_temp.as(o, $q$SELECT public.f360_save_currency('EUR', 'Euro', '€', 2, 'price eur')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%campo de la tienda%', 'the store field must be a valid meta key', r->>'error');
  r := pg_temp.as(o, $q$SELECT public.f360_save_currency('EUR', 'Euro', '€', 2, '_price_eur')$q$);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(r->'currencies') x WHERE x->>'code' = 'EUR' AND x->>'woo_meta_key' = '_price_eur'),
    'owner adds EUR → _price_eur', coalesce(r->>'error', ''));
  r := pg_temp.as(o, $q$SELECT public.f360_save_currency('MXN', 'Peso', '$', 0, '_price_mxn')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%moneda base%', 'the base currency cannot be changed here', r->>'error');
  r := pg_temp.as(o, $q$SELECT public.f360_save_currency('COP', 'Peso colombiano', 'COP$', 0, '_precio_cop_nuevo')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%ya tiene precios%', 'a currency in use cannot change its store field', r->>'error');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM f360.price_changes WHERE what = 'currency' AND currency_code = 'EUR'), 'currency changes are in the history', '');
  BEGIN UPDATE f360.price_changes SET by_name = 'x'; r := '{"error":"accepted"}'; EXCEPTION WHEN OTHERS THEN r := jsonb_build_object('error', SQLERRM); END;
  PERFORM pg_temp.ok(r->>'error' LIKE '%no se puede modificar%', 'price history is append-only', r->>'error');
  r := pg_temp.as(o, $q$SELECT to_jsonb(count(*)) FROM f360.product_prices$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%permission denied%', 'clients cannot touch price tables directly', r->>'error');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
