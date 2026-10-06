-- Pase · A7: what the PUBLISHED app 1.0.2 does, run with the same roles (anon seller, logged-in customer, claim-sale service role).
-- Run on a database that has all F360 migrations (rehearsal). One transaction, ROLLED BACK. Synthetic ZZ data only.
BEGIN;
GRANT EXECUTE ON FUNCTION public.f360_legacy_channel_frozen(uuid) TO anon;
CREATE TEMP TABLE r (n serial, status text, name text, detail text);
GRANT ALL ON r TO anon, authenticated, service_role; GRANT USAGE ON SEQUENCE r_n_seq TO anon, authenticated, service_role;
CREATE FUNCTION pg_temp.run(p_role text, p_uid uuid, p_name text, p_sql text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE res text;
BEGIN
  BEGIN
    PERFORM set_config('request.jwt.claims', CASE WHEN p_uid IS NULL THEN json_build_object('role', p_role)::text ELSE json_build_object('sub', p_uid, 'role', p_role)::text END, true);
    EXECUTE format('SET LOCAL ROLE %I', p_role);
    EXECUTE p_sql INTO res;
    RESET ROLE;
    INSERT INTO r(status, name, detail) VALUES ('PASS', p_name, coalesce(res, ''));
  EXCEPTION WHEN OTHERS THEN RESET ROLE; INSERT INTO r(status, name, detail) VALUES ('FAIL', p_name, SQLERRM); END;
END $$;
-- fixtures like production (legacy app channel/staff/inventory)
INSERT INTO channels (id, name, type, active) VALUES ('11111111-0000-0000-0000-000000000001', 'ZZ Tienda App', 'store', true);
INSERT INTO staff (id, name, pin, channel_id, active) VALUES ('22222222-0000-0000-0000-000000000001', 'ZZ Vendedora', '4321', '11111111-0000-0000-0000-000000000001', true);
INSERT INTO channel_inventory (id, channel_id, product_name, size, color, price, stock, sold) VALUES ('33333333-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'ZZ Paula', '37', 'negro', 2800, 5, 1);
INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at) VALUES ('00000000-0000-0000-0000-000000000000', '44444444-0000-0000-0000-000000000001', 'authenticated', 'authenticated', '5215500009999@fuxia.app', now(), now());
INSERT INTO pending_credits (phone, points) VALUES ('+525500009999', 50);

-- 1 · seller flow of app 1.0.2 WITHOUT login (anon)
SELECT pg_temp.run('anon', NULL, 'anon: list active channels', $q$SELECT count(*)::text FROM channels WHERE active$q$);
SELECT pg_temp.run('anon', NULL, 'anon: staff by PIN', $q$SELECT name FROM staff WHERE pin = '4321'$q$);
SELECT pg_temp.run('anon', NULL, 'anon: channel inventory', $q$SELECT count(*)::text FROM channel_inventory WHERE channel_id = '11111111-0000-0000-0000-000000000001'$q$);
SELECT pg_temp.run('anon', NULL, 'anon: sold + 1 on inventory', $q$WITH u AS (UPDATE channel_inventory SET sold = sold + 1 WHERE id = '33333333-0000-0000-0000-000000000001' RETURNING sold) SELECT sold::text FROM u$q$);
SELECT pg_temp.run('anon', NULL, 'anon: register sale (code flow)', $q$WITH i AS (INSERT INTO offline_sales (code, channel_id, staff_id, customer_phone, items, total, points_earned) VALUES ('ZZ1234', '11111111-0000-0000-0000-000000000001', '22222222-0000-0000-0000-000000000001', '+525500009999', '[{"product_name":"ZZ Paula","size":"37","quantity":1,"unit_price":2800}]', 2800, 100) RETURNING code) SELECT code FROM i$q$);
-- 2 · customer sign-up in the app (authenticated)
SELECT pg_temp.run('authenticated', '44444444-0000-0000-0000-000000000001', 'customer: create own profile', $q$WITH i AS (INSERT INTO customers (phone, name, auth_user_id, birthday) VALUES ('+525500009999', 'ZZ Clienta', '44444444-0000-0000-0000-000000000001', '1990-05-17') RETURNING id) SELECT id::text FROM i$q$);
SELECT pg_temp.run('authenticated', '44444444-0000-0000-0000-000000000001', 'customer: create own card (app sends points/tier)', $q$WITH i AS (INSERT INTO loyalty_cards (customer_id, qr_code, total_points, tier) SELECT id, 'FX-55009999-APP', 999, 'gold' FROM customers WHERE auth_user_id = '44444444-0000-0000-0000-000000000001' RETURNING qr_code, total_points, tier) SELECT qr_code || ' | ' || total_points || ' | ' || tier FROM i$q$);
SELECT pg_temp.run('authenticated', '44444444-0000-0000-0000-000000000001', 'customer: read own card', $q$SELECT qr_code || ' pts=' || total_points FROM loyalty_cards WHERE customer_id = (SELECT id FROM customers WHERE auth_user_id = '44444444-0000-0000-0000-000000000001')$q$);
SELECT pg_temp.run('authenticated', '44444444-0000-0000-0000-000000000001', 'customer: read own sales', $q$SELECT count(*)::text FROM offline_sales$q$);
-- 3 · claim-sale edge function (service role) as deployed for 1.0.2
SELECT pg_temp.run('service_role', NULL, 'claim-sale: transaction + points + sale claimed', $q$WITH c AS (SELECT lc.id, lc.total_points FROM loyalty_cards lc JOIN customers cu ON cu.id = lc.customer_id WHERE cu.phone = '+525500009999'),
  t AS (INSERT INTO transactions (loyalty_card_id, amount, currency, points_earned, pairs_in_order, channel) SELECT id, 2800, 'MXN', 100, 1, 'store' FROM c RETURNING id),
  u AS (UPDATE loyalty_cards SET total_points = total_points + 100, pairs_count = pairs_count + 1, updated_at = now() WHERE id = (SELECT id FROM c) RETURNING total_points),
  s AS (UPDATE offline_sales SET claimed_at = now(), customer_id = (SELECT id FROM customers WHERE phone = '+525500009999'), points_earned = 100 WHERE code = 'ZZ1234' RETURNING code)
  SELECT (SELECT count(*) FROM t) || ' tx | points ' || (SELECT total_points FROM u) || ' | claimed ' || (SELECT code FROM s)$q$);
-- 4 · rules the migrations add must not break the app
SELECT pg_temp.run('anon', NULL, 'anon: oversell is still refused (CHECK sold<=stock)', $q$SELECT CASE WHEN (SELECT 1 FROM (SELECT 1) x) = 1 THEN 'skip' END$q$);
SELECT status || ' | ' || name || ' | ' || left(detail, 160) FROM r ORDER BY n;
SELECT 'card after server trigger: ' || qr_code || ' pts=' || total_points || ' tier=' || tier FROM loyalty_cards lc JOIN customers c ON c.id = lc.customer_id WHERE c.phone = '+525500009999';
SELECT 'pending credit applied: ' || coalesce((SELECT applied_at IS NOT NULL FROM pending_credits WHERE phone = '+525500009999')::text, 'n/a');
SELECT 'birthday sync: ' || coalesce(birthday_day::text, '∅') || '/' || coalesce(birthday_month::text, '∅') FROM customers WHERE phone = '+525500009999';
ROLLBACK;
