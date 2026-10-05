-- Fuxia 360 G2-B2.1 canonical identity resolution — database tests (STAGING). One transaction, ROLLED BACK.
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
DECLARE n int; m int; r jsonb; v uuid; vsku text; wv bigint; tid uuid; car uuid := current_setting('t.carolina')::uuid;
BEGIN
  SELECT id INTO tid FROM f360.sales_targets WHERE key = 'woo_staging4';

  -- ── one canonical identity per (channel, Woo variation) ──
  SELECT count(*), count(DISTINCT (sales_channel_id, woo_variation_id)) INTO n, m FROM f360.channel_variant_identity;
  PERFORM pg_temp.ok(n = m AND n > 0, 'resolved view: exactly one row per (channel, Woo variation)', format('%s rows', n));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.channel_variant_identity WHERE ambiguous),
    'no Woo variation points to two different canonical variants (no ambiguity)',
    (SELECT count(*)::text FROM f360.channel_variant_identity WHERE ambiguous));

  -- ── canonical keys are the F360 ones, never a Woo id ──
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.channel_variant_identity ci JOIN f360.product_variants pv ON pv.id = ci.canonical_variant_id
      JOIN f360.products p ON p.id = pv.product_id
      WHERE ci.canonical_sku IS DISTINCT FROM pv.sku OR ci.canonical_sku !~ '^F360-' OR ci.canonical_product_key IS DISTINCT FROM 'F360-' || p.code),
    'canonical_sku = product_variants.sku (F360-…) and canonical_product_key = F360-{code}', '');

  -- ── every source relation is represented (current, retired, confirmed homologation) ──
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.channel_variant_identity_all WHERE link_state = 'current') = (SELECT count(*) FROM f360.woo_variant_links)
    AND (SELECT count(*) FROM f360.channel_variant_identity_all WHERE link_state = 'retired') = (SELECT count(*) FROM f360.retired_woo_links)
    AND (SELECT count(*) FROM f360.channel_variant_identity_all WHERE link_state = 'homologated') = (SELECT count(*) FROM f360.legacy_woo_map WHERE status = 'confirmado'),
    'all relations come from the existing tables (no new source of truth)',
    format('current %s · retired %s · homologated %s', (SELECT count(*) FROM f360.woo_variant_links), (SELECT count(*) FROM f360.retired_woo_links),
           (SELECT count(*) FROM f360.legacy_woo_map WHERE status = 'confirmado')));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.legacy_woo_map WHERE status <> 'confirmado' AND woo_variation_id IN
      (SELECT woo_variation_id FROM f360.channel_variant_identity_all WHERE link_source = 'legacy_woo_map')),
    'unconfirmed homologation rows (requiere_revision / sin_correspondencia) never resolve', '');

  -- ── priority: current > retired > homologated ──
  SELECT a.woo_variation_id INTO wv FROM f360.channel_variant_identity_all a WHERE a.link_state = 'retired'
    AND EXISTS (SELECT 1 FROM f360.channel_variant_identity_all b WHERE b.sales_channel_id = a.sales_channel_id AND b.woo_variation_id = a.woo_variation_id AND b.link_state = 'homologated') LIMIT 1;
  PERFORM pg_temp.ok(wv IS NULL OR (SELECT link_state FROM f360.channel_variant_identity WHERE woo_variation_id = wv) = 'retired',
    'a variation both retired and homologated resolves as retired (priority)', coalesce(wv::text, 'no overlap in data'));

  -- ── one canonical variant, several Woo ids over time (current + retired) ──
  SELECT count(*) INTO n FROM (SELECT canonical_variant_id FROM f360.channel_variant_identity GROUP BY sales_channel_id, canonical_variant_id
                               HAVING count(DISTINCT woo_variation_id) > 1) x;
  PERFORM pg_temp.ok(n > 0, 'a canonical variant can own several historical Woo variation ids', format('%s variants', n));
  SELECT canonical_variant_id INTO v FROM f360.channel_variant_identity GROUP BY sales_channel_id, canonical_variant_id HAVING count(DISTINCT woo_variation_id) > 1 LIMIT 1;
  PERFORM pg_temp.ok((SELECT count(DISTINCT canonical_sku) FROM f360.channel_variant_identity WHERE canonical_variant_id = v) = 1,
    'all of those Woo ids resolve to the SAME canonical SKU', (SELECT min(canonical_sku) FROM f360.channel_variant_identity WHERE canonical_variant_id = v));

  -- ── Woo SKU semantics: published = canonical; legacy = parent reference only ──
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.channel_variant_identity WHERE link_origin = 'f360_published' AND woocommerce_sku IS DISTINCT FROM canonical_sku)
    AND NOT EXISTS (SELECT 1 FROM f360.channel_variant_identity WHERE link_origin <> 'f360_published' AND woocommerce_sku_scope = 'canonical_by_publisher'),
    'woocommerce_sku: canonical for F360-published, parent reference for legacy (scope labelled)', '');

  -- ── product level ──
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.channel_product_identity WHERE canonical_product_key !~ '^F360-')
    AND EXISTS (SELECT 1 FROM f360.channel_product_identity WHERE link_state = 'current'),
    'product identity view: Woo product ↔ F360-{MODELO}', format('ambiguous legacy parents: %s',
      (SELECT count(*) FROM (SELECT 1 FROM f360.channel_product_identity GROUP BY sales_channel_id, woo_product_id HAVING count(DISTINCT canonical_product_id) > 1) z)));

  -- ── Commerce Facts lines: identity appended, facts untouched ──
  PERFORM pg_temp.ok((SELECT count(*) FROM f360.commerce_order_lines WHERE source_system = 'woo') = (SELECT count(*) FROM f360.commerce_woo_order_lines),
    'commerce_order_lines: one row per captured Woo line (no duplication through the identity join)', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_order_lines c WHERE c.source_system = 'woo' AND c.variant_id IS NOT NULL
      AND (c.canonical_sku IS DISTINCT FROM (SELECT sku FROM f360.product_variants WHERE id = c.variant_id) OR c.channel_sku IS DISTINCT FROM c.sku)),
    'resolved lines show canonical_sku (F360) and keep the external channel_sku', '');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_order_lines WHERE source_system = 'woo' AND variant_id IS NULL AND (canonical_sku IS NOT NULL OR identity_link_state <> 'unresolved')),
    'unresolved lines stay unresolved (nothing guessed)', (SELECT count(*)::text FROM f360.commerce_order_lines WHERE source_system = 'woo' AND variant_id IS NULL));
  -- regression: same variant resolution as the G1 definition (coalesce current, retired, homologated)
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM f360.commerce_order_lines c JOIN f360.commerce_woo_order_lines l
        ON c.source_system = 'woo' AND c.line_ref = l.woo_line_id::text AND c.external_ref = 'woo_staging4:' || l.woo_order_id
      LEFT JOIN f360.woo_variant_links vl ON vl.target_id = l.target_id AND vl.woo_variation_id = l.woo_variation_id
      LEFT JOIN f360.retired_woo_links rl ON rl.target_id = l.target_id AND rl.woo_variation_id = l.woo_variation_id
      LEFT JOIN f360.legacy_woo_map lm ON lm.target_id = l.target_id AND lm.woo_variation_id = l.woo_variation_id AND lm.status = 'confirmado'
      WHERE c.variant_id IS DISTINCT FROM coalesce(vl.variant_id, rl.variant_id, lm.confirmed_variant_id)),
    'regression: variant resolution identical to G1', '');

  -- synthetic F360 order on a published variation → canonical_sku; capture/idempotency untouched
  SELECT vl.woo_variation_id, pv.sku INTO wv, vsku FROM f360.woo_variant_links vl JOIN f360.product_variants pv ON pv.id = vl.variant_id
    WHERE vl.target_id = tid AND vl.origin = 'f360_published' LIMIT 1;
  r := public.f360_capture_order_economics('woo_staging4', jsonb_build_object('id', 9920000001, 'status', 'processing', 'created_via', 'store-api',
         'currency', 'MXN', 'date_created_gmt', '2099-02-01T10:00:00', 'date_paid_gmt', '2099-02-01T10:01:00', 'date_modified_gmt', '2099-02-01T10:02:00',
         'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0', 'cart_tax', '0', 'total', '2800', 'total_tax', '0',
         'fees_total', 0, 'fees_tax', 0, 'payment_method', 'f360_prueba',
         'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'variation_id', wv, 'sku', vsku, 'quantity', 1, 'subtotal', '2800', 'subtotal_tax', '0', 'total', '2800', 'total_tax', '0')),
         'refunds', '[]'::jsonb), 'test');
  PERFORM pg_temp.ok((SELECT canonical_sku = vsku AND identity_link_state = 'current' FROM f360.commerce_order_lines WHERE external_ref = 'woo_staging4:9920000001'),
    'F360 order line → canonical SKU through the resolution layer', vsku);
  r := public.f360_capture_order_economics('woo_staging4', jsonb_build_object('id', 9920000001, 'status', 'processing', 'created_via', 'store-api',
         'currency', 'MXN', 'date_created_gmt', '2099-02-01T10:00:00', 'date_paid_gmt', '2099-02-01T10:01:00', 'date_modified_gmt', '2099-02-01T10:02:00',
         'discount_total', '0', 'discount_tax', '0', 'shipping_total', '0', 'shipping_tax', '0', 'cart_tax', '0', 'total', '2800', 'total_tax', '0',
         'fees_total', 0, 'fees_tax', 0, 'payment_method', 'f360_prueba',
         'line_items', jsonb_build_array(jsonb_build_object('id', 1, 'variation_id', wv, 'sku', vsku, 'quantity', 1, 'subtotal', '2800', 'subtotal_tax', '0', 'total', '2800', 'total_tax', '0')),
         'refunds', '[]'::jsonb), 'test');
  PERFORM pg_temp.ok(r->>'result' = 'unchanged' AND (SELECT count(*) FROM f360.commerce_order_lines WHERE external_ref = 'woo_staging4:9920000001') = 1,
    'capture idempotency unchanged (same order twice → unchanged, one line)', r::text);

  -- ── deprecation markers + access ──
  PERFORM pg_temp.ok(col_description('f360.products'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'f360.products'::regclass AND attname = 'wc_product_id')) LIKE 'DEPRECATED%'
    AND col_description('f360.product_variants'::regclass, (SELECT attnum FROM pg_attribute WHERE attrelid = 'f360.product_variants'::regclass AND attname = 'wc_variation_id')) LIKE 'DEPRECATED%',
    'wc_product_id / wc_variation_id marked DEPRECATED (kept)', '');
  PERFORM pg_temp.ok(pg_temp.as(car, $q$SELECT to_jsonb(count(*)) FROM f360.channel_variant_identity$q$) ? 'error'
    AND pg_temp.as(NULL, $q$SELECT to_jsonb(count(*)) FROM f360.channel_variant_identity$q$, 'anon') ? 'error',
    'identity views are not readable directly by app users or anon', '');
END $$;

SELECT status || ' | ' || name || ' | ' || left(coalesce(detail,''), 110) FROM t_results ORDER BY n;
ROLLBACK;
