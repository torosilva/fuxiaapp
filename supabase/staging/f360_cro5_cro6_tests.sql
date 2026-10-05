-- Fuxia 360 · CRO-5 (Avísame / demanda) + CRO-6 (promesa única) — database tests (STAGING). One transaction, ROLLED BACK.
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
SELECT auth_user_id AS c1 FROM public.customers WHERE phone = '+15550100011' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; c1 uuid := current_setting('t.c1')::uuid; r jsonb; loc uuid; tgt uuid; pid uuid; v36 uuid; v37 uuid; v38 uuid; n int;
  c1cust uuid; c1phone text;
BEGIN
  r := pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Promesa Bodega', 'warehouse')$q$);
  loc := (r->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_promesa', 'ZZ Promesa', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_promesa', '[{"woo_variation_id":960036,"woo_product_id":9600,"woo_product_name":"ZZ Promesa negro","woo_size":"36"},
    {"woo_variation_id":960037,"woo_product_id":9600,"woo_product_name":"ZZ Promesa negro","woo_size":"37"},
    {"woo_variation_id":960038,"woo_product_id":9600,"woo_product_name":"ZZ Promesa negro","woo_size":"38"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_promesa', ARRAY[960036, 960037, 960038], NULL, 'ZZ Promesa Modelo', 'ballerinas', 'Negro', NULL)$q$);
  pid := (r->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  SELECT id INTO v38 FROM f360.product_variants WHERE product_id = pid AND size_label = '38';
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_receive_inventory(gen_random_uuid(), %L, '[{"variant_id":"%s","quantity":2},{"variant_id":"%s","quantity":1}]')$q$, loc, v36, v37));
  PERFORM pg_temp.ok(pid IS NOT NULL AND f360.online_ats(v36, loc) = 2 AND f360.online_ats(v37, loc) = 1 AND f360.online_ats(v38, loc) = 0,
    'fixture: homologated model, 36 → 2 pairs, 37 → 1 pair, 38 → none', '');

  -- ══ CRO-6 · one rule ══
  r := public.f360_storefront_promise('zz_promesa', 9600, 'MX');
  PERFORM pg_temp.ok(r->'variations'->'960036'->>'case' = 'in_stock' AND r->'variations'->'960036'->>'headline' LIKE 'Entrega%en Zona Metropolitana'
      AND r->'variations'->'960036'->>'status' = 'known', 'MX in stock → "Entrega Inmediata en Zona Metropolitana" (known rule)', (r->'variations'->'960036')::text);
  PERFORM pg_temp.ok(r->'variations'->'960038'->>'case' = 'made_to_order' AND r->'variations'->'960038'->>'headline' = 'Producción: 10 días hábiles'
      AND (r->'variations'->'960038'->>'business_days')::int = 10, 'MX no stock + MTO → "Producción: 10 días hábiles"', (r->'variations'->'960038')::text);
  PERFORM pg_temp.ok((r->'variations'->'960037'->>'last_pair')::boolean = false, '"Último par" NOT shown when inventory is not certified (1 pair left)', (r->'variations'->'960037')::text);
  PERFORM pg_temp.ok(r->'trust' @> '[{"key":"cambios","text":"Cambios en 30 días"},{"key":"pago_seguro"}]' AND NOT (r->'trust')::text LIKE '%MSI%'
      AND NOT (r->'trust')::text ILIKE '%gratis%', 'trust: only verifiable claims (cambios, pago seguro); no MSI / free shipping without a source', (r->'trust')::text);
  r := public.f360_storefront_promise('zz_promesa', 9600, 'CO');
  PERFORM pg_temp.ok(r->'variations'->'960036'->>'status' = 'blocked' AND r->'variations'->'960036'->>'headline' NOT ILIKE '%inmediata%'
      AND r->'variations'->'960038'->>'headline' NOT ILIKE '%10 días%', 'CO: own rule — BLOCKED_BY_BUSINESS_RULE, conservative copy, never reuses MX promise', (r->'variations')::text);
  r := public.f360_storefront_promise('zz_promesa', 9600, 'XX');
  PERFORM pg_temp.ok(r->>'market' = 'OTHER' AND r->'variations'->'960036'->>'status' = 'blocked', 'unknown market → OTHER, blocked', r->>'market');
  UPDATE f360.products SET sale_price = regular_price - 100 WHERE id = pid AND regular_price IS NOT NULL;
  UPDATE f360.products SET regular_price = 2800, sale_price = 2500 WHERE id = pid AND regular_price IS NULL;
  r := public.f360_storefront_promise('zz_promesa', 9600, 'MX');
  PERFORM pg_temp.ok(r->'trust' @> '[{"key":"cambios","text":"Precio con descuento: sin cambio"}]', 'direct discount on the shoe → "sin cambio" (Mario''s rule)', (r->'trust')::text);
  PERFORM pg_temp.ok(public.f360_storefront_promise('zz_promesa', 123456789, 'MX')->'variations' = '{}'::jsonb, 'unknown Woo product → no promise (channel keeps its own state)', '');

  -- time window (rule data): 10:00 CDMX → immediate; 21:00 CDMX → tomorrow 8 a. m.
  PERFORM pg_temp.ok(f360.delivery_promise(v36, loc, 'MX', '2026-10-05 10:00 America/Mexico_City')->>'headline' = 'Entrega Inmediata en Zona Metropolitana'
      AND f360.delivery_promise(v36, loc, 'MX', '2026-10-05 21:00 America/Mexico_City')->>'headline' = 'Entrega mañana a partir de las 8 a. m. en Zona Metropolitana'
      AND f360.delivery_promise(v36, loc, 'MX', '2026-10-05 07:59 America/Mexico_City')->>'headline' LIKE 'Entrega mañana%',
    'MX in stock: 8–19 h CDMX immediate, otherwise "mañana a partir de las 8 a. m." (the PDP rule, now F360 data)', 'ok');
  PERFORM pg_temp.ok(f360.delivery_promise(v38, loc, 'MX', '2026-10-05 21:00 America/Mexico_City')->>'headline' = 'Producción: 10 días hábiles',
    'the window applies only to in-stock', 'ok');

  -- lines (checkout / thank-you): same rule per Woo variation; unknown variation → unknown
  r := public.f360_storefront_promise_lines('zz_promesa', ARRAY[960036, 960038, 999999999]::bigint[], 'MX');
  PERFORM pg_temp.ok(r->'lines'->'960036'->>'case' = 'in_stock' AND r->'lines'->'960038'->>'case' = 'made_to_order'
      AND r->'lines'->'999999999'->>'case' = 'unknown' AND r->'lines'->'960038' = f360.delivery_promise(v38, loc, 'MX'),
    'lines: each line gets EXACTLY the PDP rule (same function); unknown line → unknown', left((r->'lines')::text, 160));

  -- ══ CRO-5 · Avísame ══
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '55 9100 0001', 'Lu', true);
  PERFORM pg_temp.ok(r->>'code' = 'available' AND r->'promise'->>'case' = 'made_to_order', 'an orderable size (MTO) is not "agotada": intent refused, promise returned', r::text);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_set_make_to_order(%L, false, 'prueba agotada')$q$, pid));
  r := public.f360_storefront_promise('zz_promesa', 9600, 'MX');
  PERFORM pg_temp.ok(r->'variations'->'960038'->>'case' = 'unavailable' AND (r->'variations'->'960038'->>'can_notify')::boolean, 'MTO off + no stock → "Agotada" + can notify', (r->'variations'->'960038')::text);
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '55 9100 0001', 'Lu', false);
  PERFORM pg_temp.ok(r->>'code' = 'consent', 'operational consent is required (checkbox)', r::text);
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '123', 'Lu', true);
  PERFORM pg_temp.ok(r->>'code' = 'phone', 'phone validated', r::text);
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '55 9100 0001', 'Lu', true, 'pdp', 'iphash1', 'https://staging4/x');
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND r->>'already' = 'false', 'anonymous intent registered', r::text);
  PERFORM pg_temp.ok((SELECT variant_id = v38 AND product_id = pid AND canonical_sku IS NOT NULL AND product_key LIKE 'F360-%' AND color = 'Negro' AND size = '38'
       AND market = 'MX' AND contact_phone = '+525591000001' AND customer_id IS NULL AND consent_version_id IS NOT NULL
      FROM f360.stock_intents WHERE woo_variation_id = 960038), 'intent stores canonical model + SKU + color + size + market + operational consent version; phone normalized',
    (SELECT to_jsonb(s) - 'id' - 'ip_hash' FROM f360.stock_intents s WHERE woo_variation_id = 960038 LIMIT 1)::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.customers WHERE f360.normalize_phone(phone) = '+525591000001'), 'no customer row is created (Customer 360 not duplicated)', '');
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '+52 1 55 9100 0001', 'Lu', true);
  PERFORM pg_temp.ok(r->>'already' = 'true' AND (SELECT count(*) FROM f360.stock_intents WHERE woo_variation_id = 960038) = 1, 'same person + size (any phone format) → one intent', r::text);

  SELECT id, phone INTO c1cust, c1phone FROM public.customers WHERE auth_user_id = c1;
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', c1phone, NULL, true);
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND EXISTS (SELECT 1 FROM f360.stock_intents WHERE customer_id = c1cust AND contact_phone IS NULL),
    'existing customer → related by customer_id (no contact copy)', r::text);
  PERFORM pg_temp.ok((SELECT status FROM f360.customer_consent_state WHERE customer_id = c1cust AND purpose_key = 'stock_notification') = 'granted'
      AND (SELECT status FROM f360.customer_consent_state WHERE customer_id = c1cust AND purpose_key = 'marketing_whatsapp') <> 'granted',
    'operational consent recorded for her; marketing consent untouched', 'ok');
  PERFORM pg_temp.ok((SELECT kind FROM f360.consent_purposes WHERE key = 'stock_notification') = 'operational', 'purpose kind is operational (not marketing)', '');

  -- rate limit (ip)
  INSERT INTO f360.stock_intents (sales_channel_id, woo_product_id, woo_variation_id, market, source, contact_phone, consent_version_id, ip_hash)
    SELECT tgt, 9600, 960099 + g, 'MX', 'pdp', '+52559200' || lpad(g::text, 4, '0'), (SELECT id FROM f360.consent_notice_versions WHERE purpose_key = 'stock_notification'), 'iphash-burst'
    FROM generate_series(1, 30) g;
  r := public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '55 9300 0001', NULL, true, 'pdp', 'iphash-burst');
  PERFORM pg_temp.ok(r->>'code' = 'rate_limited', 'rate limit: 30 intents per ip per hour', r::text);
  DELETE FROM f360.stock_intents WHERE ip_hash = 'iphash-burst';

  -- ══ Demand view ══
  INSERT INTO f360.made_to_order (target_id, woo_order_id, woo_line_id, variant_id, quantity, on_hand_at_order, status)
    VALUES (tgt, 99001, 1, v38, 2, 0, 'pendiente');
  r := pg_temp.as(car, $q$SELECT public.f360_stock_demand('MX')$q$);
  PERFORM pg_temp.ok(r->'models' @> jsonb_build_array(jsonb_build_object('product', 'ZZ Promesa Modelo', 'waiting', 2, 'mto_pairs', 2,
      'sizes', jsonb_build_array(jsonb_build_object('color', 'Negro', 'size', '38', 'waiting', 2, 'mto_pairs', 2)))) AND jsonb_array_length(r->'models'->0->'sizes') = 1,
    'DEMANDA SIN INVENTARIO: "ZZ Promesa Modelo · Negro / 38 · 2 esperando" + 2 pares vendidos sobre pedido', left((r->'models')::text, 240));
  PERFORM pg_temp.ok(position('9100' IN r::text) = 0 AND position('+52' IN r::text) = 0, 'demand view has no personal data', '');
  r := pg_temp.as(NULL, $q$SELECT public.f360_stock_demand()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read demand', r->>'error');
  r := pg_temp.as(car, $q$SELECT public.f360_stock_intent_create('zz_promesa', 9600, 960038, 'MX', '5591000002', NULL, true)$q$);
  PERFORM pg_temp.ok(r ? 'error', 'intents are created only through the storefront service (not by app users)', r->>'error');
END $$;

SELECT status || ' | ' || name || ' | ' || coalesce(detail, '') FROM t_results ORDER BY n;
ROLLBACK;
