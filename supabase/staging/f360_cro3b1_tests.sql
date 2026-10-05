-- Fuxia 360 · CRO-3B1 (reseñas: verificación + ajuste) — database tests (STAGING). One transaction, ROLLED BACK. Synthetic fixtures only.
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
-- paid (or not) Woo order with one line, captured through the real Commerce Facts entry point
CREATE FUNCTION pg_temp.order(p_id bigint, p_status text, p_product bigint, p_variation bigint, p_customer bigint, p_at text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.f360_capture_order_economics('zz_resenas', jsonb_build_object('id', p_id, 'status', p_status, 'created_via', 'store-api', 'currency', 'MXN',
    'prices_include_tax', false, 'date_created_gmt', p_at, 'date_paid_gmt', CASE WHEN p_status IN ('processing', 'completed') THEN p_at END,
    'date_completed_gmt', NULL, 'date_modified_gmt', p_at, 'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0',
    'cart_tax', '0', 'total', '2800', 'total_tax', '0', 'fees_total', 0, 'fees_tax', 0, 'coupon_count', 0, 'payment_method', 'woo-mercado-pago-custom',
    'woo_customer_id', p_customer, 'billing_country', 'MX',
    'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'product_id', p_product, 'variation_id', p_variation, 'sku', NULL, 'quantity', 1,
      'subtotal', '2800', 'subtotal_tax', '0', 'total', '2800', 'total_tax', '0')), 'refunds', '[]'::jsonb, 'attribution', NULL), 'test') $$;
CREATE FUNCTION pg_temp.sync(p_review bigint, p_product bigint, p_at text, p_claims jsonb DEFAULT '{}', p_status text DEFAULT 'approved', p_rating int DEFAULT 5,
  p_media int DEFAULT 0) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.f360_review_sync('zz_resenas', jsonb_build_object('woo_review_id', p_review, 'woo_product_id', p_product, 'rating', p_rating, 'status', p_status,
    'media_count', p_media, 'woo_verified', false, 'reviewed_at', p_at, 'claims', p_claims)) $$;
CREATE FUNCTION pg_temp.rf(p_review bigint) RETURNS f360.review_facts LANGUAGE sql AS
$$ SELECT * FROM f360.review_facts WHERE sales_channel_id = (SELECT id FROM f360.sales_targets WHERE key = 'zz_resenas') AND woo_review_id = p_review $$;
CREATE FUNCTION pg_temp.fit(p_review bigint, p_fit jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN RETURN public.f360_review_set_fit('zz_resenas', p_review, p_fit); EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLERRM); END $$;

SELECT auth_user_id AS carolina FROM f360.user_roles WHERE display_name = 'Carolina' \gset
SELECT id AS c1 FROM auth.users WHERE email = '15550100011@fuxia.app' \gset
SELECT set_config('t.carolina', :'carolina', true), set_config('t.c1', :'c1', true) \gset t_

DO $$
DECLARE car uuid := current_setting('t.carolina')::uuid; op uuid := current_setting('t.c1')::uuid; r jsonb; loc uuid; tgt uuid; pid uuid; pid2 uuid;
  v36 uuid; v37 uuid; o36 uuid; cust uuid; sale uuid; legacy_sale uuid; cand uuid; f f360.review_facts; n int; s jsonb; i int; mail text := 'zz.resena@example.com';
  h text := encode(extensions.digest('zz.resena@example.com', 'sha256'), 'hex');
BEGIN
  -- ══ fixtures: channel, two homologated models (Woo 9700 = model A, 9800 = model B) ══
  r := pg_temp.as(car, $q$SELECT public.f360_create_location('ZZ Reseñas Bodega', 'warehouse')$q$); loc := (r->>'id')::uuid;
  INSERT INTO f360.sales_targets (key, name, base_url, fulfillment_location_id, active) VALUES ('zz_resenas', 'ZZ Reseñas', 'https://zz.invalid', loc, true) RETURNING id INTO tgt;
  PERFORM public.f360_legacy_load_snapshot('zz_resenas', '[{"woo_variation_id":970036,"woo_product_id":9700,"woo_product_name":"ZZ Reseña negro","woo_size":"36"},
    {"woo_variation_id":970037,"woo_product_id":9700,"woo_product_name":"ZZ Reseña negro","woo_size":"37"},
    {"woo_variation_id":980036,"woo_product_id":9800,"woo_product_name":"ZZ Otro negro","woo_size":"36"}]');
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_resenas', ARRAY[970036, 970037], NULL, 'ZZ Reseña Modelo', 'ballerinas', 'Negro', NULL)$q$); pid := (r->>'product_id')::uuid;
  r := pg_temp.as(car, $q$SELECT public.f360_legacy_confirm('zz_resenas', ARRAY[980036], NULL, 'ZZ Otro Modelo', 'ballerinas', 'Negro', NULL)$q$); pid2 := (r->>'product_id')::uuid;
  SELECT id INTO v36 FROM f360.product_variants WHERE product_id = pid AND size_label = '36';
  SELECT id INTO v37 FROM f360.product_variants WHERE product_id = pid AND size_label = '37';
  SELECT id INTO o36 FROM f360.product_variants WHERE product_id = pid2;
  PERFORM pg_temp.ok(pid IS NOT NULL AND pid2 IS NOT NULL AND v36 IS NOT NULL AND v37 IS NOT NULL, 'fixture: two homologated models', '');
  INSERT INTO f360.user_roles (auth_user_id, role, display_name) VALUES (op, 'operator', 'ZZ Operadora');

  -- ══ sizes and statistics ══
  PERFORM pg_temp.ok(f360.size_mx('36') = '23' AND f360.size_mx('35.5') = '22.5' AND f360.size_from_mx('24') = '37' AND f360.size_mx('XL') IS NULL,
    'size: Fuxia ↔ MX (− 13), one function in the database', '');
  PERFORM pg_temp.ok(f360.wilson_lower(9, 10) BETWEEN 0.59 AND 0.60 AND f360.wilson_lower(23, 25) BETWEEN 0.74 AND 0.76 AND f360.wilson_lower(0, 0) IS NULL,
    'Wilson lower bound: 9/10 ≈ 0.596, 23/25 ≈ 0.750', f360.wilson_lower(9, 10) || ' / ' || f360.wilson_lower(23, 25));

  -- ══ sync + model resolution ══
  r := pg_temp.sync(970001, 9700, '2026-09-01T12:00:00Z');
  f := pg_temp.rf(970001);
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED' AND f.product_id = pid AND r->'detail'->>'reason' = 'no_purchase_found' AND r->>'product_key' LIKE 'F360-%',
    'review without purchase → UNVERIFIED, model resolved through the canonical identity', r::text);
  r := pg_temp.sync(970002, 123456, '2026-09-01T12:00:00Z');
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED' AND (pg_temp.rf(970002)).product_id IS NULL AND r->'detail'->>'reason' = 'model_not_homologated',
    'Woo product not homologated → no model, UNVERIFIED (never guessed)', r::text);

  -- ══ online verification ══
  PERFORM pg_temp.order(97100001, 'completed', 9700, 970036, NULL, '2026-08-20T10:00:00');
  PERFORM pg_temp.order(97100002, 'pending', 9700, 970037, NULL, '2026-08-20T10:00:00');
  PERFORM pg_temp.order(97100003, 'completed', 9800, 980036, NULL, '2026-08-20T10:00:00');
  PERFORM pg_temp.order(97100004, 'completed', 9700, 970037, NULL, '2026-09-10T10:00:00');
  r := pg_temp.sync(970010, 9700, '2026-09-01T12:00:00Z', '{"woo_order_ids":[97100002]}');
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED', 'unpaid order → not verified', r::text);
  r := pg_temp.sync(970011, 9700, '2026-09-01T12:00:00Z', '{"woo_order_ids":[97100003]}');
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED', 'paid order of ANOTHER model → not verified', r::text);
  r := pg_temp.sync(970012, 9700, '2026-09-01T12:00:00Z', '{"woo_order_ids":[97100004]}');
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED', 'order paid AFTER the review → not verified', r::text);
  r := pg_temp.sync(970013, 9700, '2026-09-01T12:00:00Z', ('{"woo_order_ids":[97100001], "email_sha256":"' || h || '"}')::jsonb);
  f := pg_temp.rf(970013);
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_ONLINE' AND f.woo_order_id = 97100001 AND f.purchased_variant_id = v36 AND f.purchased_size = '36'
    AND f.evidence->>'identity' = 'wp_order_email' AND f.verified_by = 'system',
    'paid order with the model, before the review → VERIFIED_ONLINE with the purchased variant and size', f.evidence::text);
  PERFORM pg_temp.ok(f.evidence::text !~ '@' AND f.evidence::text !~ '[0-9a-f]{64}' AND NOT EXISTS (SELECT 1 FROM f360.review_facts_log WHERE detail::text ~ '[0-9a-f]{64}|@'),
    'no e-mail or e-mail hash stored anywhere (evidence, log)', '');
  PERFORM pg_temp.order(97100005, 'processing', 9700, 970037, 5551, '2026-08-21T10:00:00');
  r := pg_temp.sync(970014, 9700, '2026-09-01T12:00:00Z', '{"woo_user_id":5551}');
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_ONLINE' AND (pg_temp.rf(970014)).evidence->>'identity' = 'woo_customer_id' AND (pg_temp.rf(970014)).purchased_size = '37',
    'Woo account id match (no order list) → VERIFIED_ONLINE by woo_customer_id', r::text);
  PERFORM pg_temp.ok((pg_temp.rf(970013)).evidence->>'match' = 'same_product', 'evidence says she bought the reviewed product itself', '');
  -- same model, another colour (another Woo product of the SAME canonical model)
  PERFORM public.f360_legacy_load_snapshot('zz_resenas', '[{"woo_variation_id":970136,"woo_product_id":9701,"woo_product_name":"ZZ Reseña rojo","woo_size":"36"}]');
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_legacy_confirm('zz_resenas', ARRAY[970136], %L, NULL, 'ballerinas', 'Rojo', NULL)$q$, pid));
  PERFORM pg_temp.order(97100006, 'completed', 9701, 970136, 5552, '2026-08-22T10:00:00');
  r := pg_temp.sync(970015, 9700, '2026-09-01T12:00:00Z', '{"woo_user_id":5552}');
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_ONLINE' AND (pg_temp.rf(970015)).evidence->>'match' = 'same_model',
    'bought the same MODEL in another colour → verified, marked same_model (never implies the reviewed colour)', ((pg_temp.rf(970015)).evidence)::text);
  r := pg_temp.sync(970013, 9700, '2026-09-01T12:00:00Z', '{}', 'approved', 4);
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_ONLINE' AND (pg_temp.rf(970013)).rating = 4, 're-sync without claims keeps the verification (sticky) and updates the stars', r::text);

  -- ══ store verification ══
  INSERT INTO public.customers (phone, name, email, source) VALUES ('+525500009701', 'ZZ Reseña', mail, 'store') RETURNING id INTO cust;
  INSERT INTO public.offline_sales (code, items, total, customer_id, created_at) VALUES ('ZZ-R-1', '[]', 2800, cust, '2026-08-15T10:00:00Z') RETURNING id INTO sale;
  INSERT INTO public.offline_sale_items (sale_id, line_no, product_name, size, color, quantity, unit_price, line_total, price_source, variant_id)
  VALUES (sale, 1, 'ZZ Reseña Modelo', '37', 'Negro', 1, 2800, 2800, 'test', v37);
  r := pg_temp.sync(970020, 9700, '2026-09-02T12:00:00Z', ('{"email_sha256":"' || upper(h) || '"}')::jsonb);
  f := pg_temp.rf(970020);
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_STORE' AND f.offline_sale_id = sale AND f.purchased_variant_id = v37 AND f.purchased_size = '37'
    AND f.evidence->>'identity' = 'email_hash' AND f.woo_order_id IS NULL,
    'store sale of the same customer (e-mail hash), canonical item → VERIFIED_STORE', f.evidence::text);
  INSERT INTO public.customers (phone, name, email, source) VALUES ('+525500009702', 'ZZ Vendedora', 'zz.vendedora@example.com', 'store') RETURNING id INTO cust;
  INSERT INTO public.offline_sales (code, items, total, customer_id, created_at, self_sale) VALUES ('ZZ-R-2', '[]', 2800, cust, '2026-08-15T10:00:00Z', true) RETURNING id INTO sale;
  INSERT INTO public.offline_sale_items (sale_id, line_no, product_name, quantity, unit_price, line_total, price_source, variant_id) VALUES (sale, 1, 'ZZ', 1, 2800, 2800, 'test', v36);
  r := pg_temp.sync(970021, 9700, '2026-09-02T12:00:00Z', jsonb_build_object('email_sha256', encode(extensions.digest('zz.vendedora@example.com', 'sha256'), 'hex')));
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED', 'a seller''s own purchase (self_sale) never verifies her review', r::text);
  r := pg_temp.sync(970022, 9700, '2026-09-02T12:00:00Z', jsonb_build_object('email_sha256', encode(extensions.digest('otra@example.com', 'sha256'), 'hex')));
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED', 'different e-mail → not verified (no name matching)', r::text);

  -- ══ legacy store sale (old app, items only in jsonb): proven buyer → NEEDS_REVIEW; Carolina identifies the ITEM ══
  INSERT INTO public.customers (phone, name, email, source) VALUES ('+525500009703', 'ZZ Legado', 'zz.legado@example.com', 'store') RETURNING id INTO cust;
  INSERT INTO public.offline_sales (code, items, total, customer_id, created_at)
  VALUES ('ZZ-R-3', '[{"name":"Reseña negro","size":"36","color":"negro","qty":1}]', 2800, cust, '2026-07-01T10:00:00Z') RETURNING id INTO legacy_sale;
  r := pg_temp.sync(970030, 9700, '2026-09-03T12:00:00Z', jsonb_build_object('email_sha256', encode(extensions.digest('zz.legado@example.com', 'sha256'), 'hex')));
  SELECT id INTO cand FROM f360.review_purchase_candidates WHERE woo_review_id = 970030;
  PERFORM pg_temp.ok(r->>'verification' = 'NEEDS_REVIEW' AND cand IS NOT NULL
    AND (SELECT item_snapshot->>'product_name' = 'Reseña negro' AND identity_evidence = 'email_hash' FROM f360.review_purchase_candidates WHERE id = cand),
    'proven buyer + legacy item without canonical variant → NEEDS_REVIEW with a candidate (item snapshot only)', r::text);
  r := pg_temp.as(op, format('SELECT public.f360_review_confirm_candidate(%L, %L)', cand, v36));
  PERFORM pg_temp.ok(r ? 'error' AND (pg_temp.rf(970030)).verification = 'NEEDS_REVIEW', 'an operator cannot confirm (owner only)', r::text);
  r := pg_temp.as(car, format('SELECT public.f360_review_confirm_candidate(%L, %L)', cand, o36));
  PERFORM pg_temp.ok(r->>'error' LIKE '%mismo modelo%', 'Carolina cannot pick a variant of another model', r::text);
  r := pg_temp.as(car, format('SELECT public.f360_review_confirm_candidate(%L, %L, %L)', cand, v36, 'ticket Polanco'));
  f := pg_temp.rf(970030);
  PERFORM pg_temp.ok(r->>'verification' = 'VERIFIED_STORE' AND f.verified_by = 'Carolina' AND f.offline_sale_id = legacy_sale AND f.purchased_size = '36'
    AND f.evidence->>'item' = 'identified_by_owner'
    AND EXISTS (SELECT 1 FROM f360.review_facts_log WHERE woo_review_id = 970030 AND action = 'candidate_confirmed' AND by_name = 'Carolina'),
    'Carolina identifies the item of the proven purchase → VERIFIED_STORE, audited', f.evidence::text);
  r := pg_temp.as(car, format('SELECT public.f360_review_confirm_candidate(%L, %L)', cand, v36));
  PERFORM pg_temp.ok(r ? 'error', 'a candidate cannot be confirmed twice', r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname ~ '^f360_review_(mark|set)_verified'),
    'there is NO function to mark a review verified by hand (only via a proven purchase)', '');
  -- reject path
  r := pg_temp.sync(970031, 9700, '2026-09-04T12:00:00Z', jsonb_build_object('email_sha256', encode(extensions.digest('zz.legado@example.com', 'sha256'), 'hex')));
  SELECT id INTO cand FROM f360.review_purchase_candidates WHERE woo_review_id = 970031;
  r := pg_temp.as(car, format('SELECT public.f360_review_reject_candidate(%L, %L)', cand, 'no corresponde'));
  PERFORM pg_temp.ok(r->>'verification' = 'UNVERIFIED' AND (pg_temp.rf(970031)).verification = 'UNVERIFIED', 'Carolina rejects the only candidate → UNVERIFIED', r::text);
  -- revoke
  r := pg_temp.as(car, $q$SELECT public.f360_review_revoke_verification('zz_resenas', 970014, 'x')$q$);
  PERFORM pg_temp.ok(r->>'error' LIKE '%motivo%', 'revoke needs a reason', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_review_revoke_verification('zz_resenas', 970014, 'pedido de prueba interno')$q$);
  PERFORM pg_temp.ok((pg_temp.rf(970014)).verification = 'UNVERIFIED' AND (pg_temp.rf(970014)).woo_order_id IS NULL
    AND EXISTS (SELECT 1 FROM f360.review_facts_log WHERE woo_review_id = 970014 AND action = 'revoked'), 'owner revokes a verification, audited', r::text);

  -- ══ fit capture ══
  PERFORM pg_temp.ok(pg_temp.fit(970013, '{"scale":"mx","usual_size":"23","fit":"medium","comfort":5,"would_recommend":true,"via":"review_form"}') ? 'error',
    'invalid fit value refused', '');
  PERFORM pg_temp.ok(pg_temp.fit(970013, '{"scale":"mx","usual_size":"23","purchased_size":"24","fit":"true","comfort":5,"would_recommend":true,"via":"review_form"}')->>'error' LIKE '%no coincide%',
    'purchased size different from the verified purchase is refused', '');
  r := pg_temp.fit(970013, '{"scale":"mx","usual_size":"23","fit":"true","comfort":5,"would_recommend":true,"via":"review_form"}');
  f := pg_temp.rf(970013);
  PERFORM pg_temp.ok((r->>'counts_for_fit')::boolean AND f.usual_size = '36' AND f.purchased_size = '36' AND f.fit = 'true' AND f.comfort = 5,
    'fit captured in MX scale, stored canonical (23 MX → 36), purchased size from the purchase', r::text);
  PERFORM pg_temp.ok(pg_temp.fit(970013, '{"scale":"mx","usual_size":"23","fit":"small","comfort":4,"would_recommend":true,"via":"review_form"}')->>'error' LIKE '%ya tiene%',
    'fit cannot be overwritten', '');
  r := pg_temp.fit(970001, '{"scale":"fuxia","usual_size":"37","fit":"large","comfort":2,"would_recommend":false,"via":"review_form"}');
  PERFORM pg_temp.ok(r->>'ok' = 'true' AND NOT (r->>'counts_for_fit')::boolean, 'fit of an UNVERIFIED review is kept but does not count', r::text);

  -- ══ display rule (progressive + Wilson) — model A: 970013 verified (true) so far; build up to 25 verified ══
  s := f360.review_summary(pid);
  PERFORM pg_temp.ok(NOT (s ? 'fit') AND (s->'reviews'->>'count')::int >= 1, 'n < 5 and no validated editorial fit → no fit line at all (never invented)', s::text);
  PERFORM pg_temp.as(car, format($q$SELECT public.f360_product_knowledge_save(%L, '{"fit_category":"true_to_size"}', true)$q$, pid));
  s := f360.review_summary(pid);
  PERFORM pg_temp.ok(s->'fit'->>'tier' = 'editorial' AND s->'fit'->>'headline' = 'Horma: talla exacta' AND s->'fit'->>'basis' = 'Según Fuxia',
    'n < 5 → only Carolina''s validated editorial fit', (s->'fit')::text);
  FOR i IN 2..25 LOOP
    PERFORM pg_temp.order(97200000 + i, 'completed', 9700, 970036, 6000 + i, '2026-08-01T10:00:00');
    PERFORM pg_temp.sync(971000 + i, 9700, '2026-09-05T12:00:00Z', jsonb_build_object('woo_user_id', 6000 + i), 'approved', 5, CASE WHEN i % 5 = 0 THEN 1 ELSE 0 END);
    PERFORM pg_temp.fit(971000 + i, jsonb_build_object('scale', 'mx', 'usual_size', '23', 'fit', CASE WHEN i IN (3, 17) THEN 'small' ELSE 'true' END,
                                                       'comfort', CASE WHEN i % 4 = 0 THEN 4 ELSE 5 END, 'would_recommend', i <> 7, 'via', 'review_form'));
    s := f360.review_summary(pid);
    IF i = 4 THEN PERFORM pg_temp.ok(s->'fit'->>'tier' = 'editorial', 'n = 4 verified → still editorial', (s->'fit')::text); END IF;
    IF i = 5 THEN PERFORM pg_temp.ok(s->'fit'->>'tier' = 'count' AND s->'fit'->>'headline' = '4 de 5 compradoras verificadas dicen que viene a talla exacta'
                                     AND s->'fit'->>'basis' = 'Basado en 5 compras verificadas' AND NOT (s->'fit'->>'claim')::boolean,
                                     'n = 5 → count tier, with sample size, no strong claim', (s->'fit')::text); END IF;
    IF i = 10 THEN PERFORM pg_temp.ok(s->'fit'->>'tier' = 'percent' AND s->'fit'->>'headline' = '90% dice que viene a talla exacta' AND NOT (s->'fit'->>'claim')::boolean,
                                      'n = 10, 9 exact → 90% shown with n, but Wilson (0.60 < 0.70) blocks the strong claim', (s->'fit')::text); END IF;
  END LOOP;
  PERFORM pg_temp.ok(s->'fit'->>'headline' = '92% dice que viene a talla exacta' AND s->'fit'->>'basis' = 'Basado en 25 compras verificadas' AND (s->'fit'->>'claim')::boolean
    AND s->'fit'->'editorial'->>'category' = 'true_to_size',
    'n = 25, 23 exact → 92% + strong claim allowed (Wilson 0.75 ≥ 0.70), editorial kept for comparison', (s->'fit')::text);
  PERFORM pg_temp.ok(s->'comfort'->>'headline' ~ '^Comodidad 4\.\d/5$' AND (s->'comfort'->>'n')::int = 25 AND s->'recommend'->>'headline' = '96% la recomendaría',
    'comfort and recommendation with their own sample size (verified only)', s::text);
  PERFORM pg_temp.ok((SELECT fit_n = 25 AND verified_online = 26 AND verified_store = 2 AND photo_reviews = 5 AND fit_large = 0 FROM f360.review_model_metrics WHERE product_id = pid),
    'metrics: unverified fit (large) excluded; online/store split; photo reviews counted', (SELECT to_jsonb(m)::text FROM f360.review_model_metrics m WHERE product_id = pid));
  -- moderation: spam leaves the aggregates
  PERFORM pg_temp.sync(971002, 9700, '2026-09-05T12:00:00Z', '{}', 'spam');
  PERFORM pg_temp.ok((SELECT fit_n FROM f360.review_model_metrics WHERE product_id = pid) = 24, 'a review moved to spam leaves the aggregates', '');

  -- ══ security ══
  r := pg_temp.as(NULL, $q$SELECT public.f360_review_sync('zz_resenas', '{"woo_review_id":1,"woo_product_id":9700,"rating":5,"status":"approved","reviewed_at":"2026-09-01"}')$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot sync reviews', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_review_sync('zz_resenas', '{"woo_review_id":1,"woo_product_id":9700,"rating":5,"status":"approved","reviewed_at":"2026-09-01"}')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'even an owner session cannot call the server sync (service role only)', r::text);
  r := pg_temp.as(car, $q$SELECT public.f360_review_set_fit('zz_resenas', 970001, '{}')$q$);
  PERFORM pg_temp.ok(r ? 'error', 'fit capture is server only', r::text);
  r := pg_temp.as(car, $q$SELECT count(*)::text::jsonb FROM f360.review_facts$q$);
  PERFORM pg_temp.ok(r ? 'error', 'review tables are not readable by app users', r::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'f360' AND table_name IN ('review_facts', 'review_purchase_candidates', 'review_facts_log')
      AND column_name ~ '^(email|phone|author.*|reviewer.*|customer.*|name|first_name|last_name|comment.*|content|review_text|body|.*_hash|ip.*)$'),
    'no PII / review text columns in the F360 review tables', '');
  BEGIN UPDATE f360.review_facts_log SET by_name = 'x' WHERE true; PERFORM pg_temp.ok(false, 'review log is append-only', '');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.ok(true, 'review log is append-only', SQLERRM); END;

  -- ══ Carolina's queue ══
  r := pg_temp.sync(970040, 9700, '2026-09-06T12:00:00Z', '{}', 'hold');
  r := pg_temp.as(car, $q$SELECT public.f360_review_work_queue()$q$);
  PERFORM pg_temp.ok(jsonb_typeof(r->'models_without_fit') = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'reviews_pending_moderation') e WHERE (e->>'woo_review_id')::bigint = 970040)
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'reviews_without_model') e WHERE (e->>'woo_review_id')::bigint = 970002)
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'models_without_fit') e WHERE e->>'product_key' = (SELECT 'F360-' || code FROM f360.products WHERE id = pid))
    AND r::text !~ '@',
    'work queue: pending moderation, reviews without model, models without validated fit — no PII', left(r::text, 300));
  r := pg_temp.as(NULL, $q$SELECT public.f360_review_work_queue()$q$, 'anon');
  PERFORM pg_temp.ok(r ? 'error', 'anon cannot read the queue', r::text);
END $$;

SELECT status || ' | ' || name || CASE WHEN status = 'FAIL' THEN ' | ' || detail ELSE '' END FROM t_results ORDER BY n;
ROLLBACK;
