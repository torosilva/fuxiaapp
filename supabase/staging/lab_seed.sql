-- S0.0A staging lab — SEED of synthetic fixtures (STAGING ONLY; never a migration).
-- See docs/fuxia360/audit/S0_0A_STAGING_LAB_MANIFEST.md (fixtures F0–F9, M1, S1, S2, C1–C3, E1, U1).
-- psql variables (auth user ids created first by scripts/s00a/lab.mjs): m1, s1, c1, c2, c3
BEGIN;

-- F0 tier_config (values from repo schema.sql / points_orders_migration.sql; not customer data)
INSERT INTO public.tier_config (tier, min_pairs, min_points, reward_description, reward_sku) VALUES
  ('bronze', 0, 0,   'Accesorio gratis (hasta $300 MXN)', 'REWARD-BRONZE'),
  ('silver', 3, 300, '1 par de flats básico gratis',       'REWARD-SILVER'),
  ('gold',   9, 900, '1 par de flats premium gratis',      'REWARD-GOLD')
ON CONFLICT (tier) DO NOTHING;

-- F1 buckets
INSERT INTO storage.buckets (id, name, public) VALUES
  ('avatars', 'avatars', true), ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- F2 / F3 channels
INSERT INTO public.channels (id, name, type, location, active) VALUES
  ('00000000-0000-4000-a000-000000000301', 'STAGING Tienda X', 'store', 'STAGING', true),
  ('00000000-0000-4000-a000-000000000302', 'STAGING Bazar Y',  'bazar', 'STAGING', true);

-- M1 / S1 / C1 / C2 / C3 customers (linked to their synthetic auth users)
INSERT INTO public.customers (id, phone, name, email, country, role, auth_user_id, referral_code, wc_customer_id) VALUES
  ('00000000-0000-4000-a000-000000000101', '+15550100001', 'STAGING Admin M1',   NULL,                 'MX', 'admin',    :'m1', 'STGM1', NULL),
  ('00000000-0000-4000-a000-000000000121', '+15550100021', 'STAGING Seller S1',  NULL,                 'MX', 'staff',    :'s1', 'STGS1', NULL),
  ('00000000-0000-4000-a000-000000000111', '+15550100011', 'STAGING Cliente C1', 'c1@staging.invalid', 'MX', 'customer', :'c1', 'STGC1', 990001),
  ('00000000-0000-4000-a000-000000000112', '+15550100012', 'STAGING Cliente C2', NULL,                 'MX', 'customer', :'c2', 'STGC2', NULL),
  ('00000000-0000-4000-a000-000000000113', '+15550100013', 'STAGING Cliente C3', NULL,                 'MX', 'customer', :'c3', 'STGC3', NULL);

-- Loyalty cards (C3 deliberately has none; C1 = 100 pts / 1 pair)
INSERT INTO public.loyalty_cards (id, customer_id, qr_code, total_points, pairs_count, tier) VALUES
  ('00000000-0000-4000-a000-000000000201', '00000000-0000-4000-a000-000000000101', 'STG-M1', 0,   0, 'bronze'),
  ('00000000-0000-4000-a000-000000000221', '00000000-0000-4000-a000-000000000121', 'STG-S1', 0,   0, 'bronze'),
  ('00000000-0000-4000-a000-000000000211', '00000000-0000-4000-a000-000000000111', 'STG-C1', 100, 1, 'bronze'),
  ('00000000-0000-4000-a000-000000000212', '00000000-0000-4000-a000-000000000112', 'STG-C2', 0,   0, 'bronze');

-- S1 / S2 staff
INSERT INTO public.staff (id, name, pin, channel_id, active) VALUES
  ('00000000-0000-4000-a000-000000000421', 'STAGING Seller S1', '1111', '00000000-0000-4000-a000-000000000301', true),
  ('00000000-0000-4000-a000-000000000422', 'STAGING Seller S2', '2222', '00000000-0000-4000-a000-000000000302', true);

-- F4 inventory
INSERT INTO public.channel_inventory (id, channel_id, product_name, sku, size, color, price, stock, sold) VALUES
  ('00000000-0000-4000-a000-000000000501', '00000000-0000-4000-a000-000000000301', 'STAGING Ballerina Test', 'STG-BAL-23', '23', 'Negro', 999.00, 5, 0),
  ('00000000-0000-4000-a000-000000000502', '00000000-0000-4000-a000-000000000301', 'STAGING Ballerina Test', 'STG-BAL-24', '24', 'Negro', 999.00, 5, 0),
  ('00000000-0000-4000-a000-000000000503', '00000000-0000-4000-a000-000000000301', 'STAGING Ballerina Test', 'STG-BAL-25', '25', 'Negro', 999.00, 5, 0),
  ('00000000-0000-4000-a000-000000000504', '00000000-0000-4000-a000-000000000302', 'STAGING Ballerina Test', 'STG-BAL-24', '24', 'Negro', 999.00, 3, 0);

-- C1-tx: one web purchase
INSERT INTO public.transactions (id, loyalty_card_id, wc_order_id, amount, currency, points_earned, pairs_in_order, channel, wc_status) VALUES
  ('00000000-0000-4000-a000-000000000901', '00000000-0000-4000-a000-000000000211', 990000001, 999.00, 'MXN', 100, 1, 'web', 'completed');
INSERT INTO public.purchase_items (id, transaction_id, sku, product_name, size, color, quantity, unit_price) VALUES
  ('00000000-0000-4000-a000-000000000902', '00000000-0000-4000-a000-000000000901', 'STG-BAL-24', 'STAGING Ballerina Test', '24', 'Negro', 1, 999.00);

-- F5 store sales
INSERT INTO public.offline_sales (id, code, channel_id, staff_id, customer_phone, customer_id, items, total, points_earned, claimed_at) VALUES
  ('00000000-0000-4000-a000-000000000601', 'STGA01', '00000000-0000-4000-a000-000000000301', '00000000-0000-4000-a000-000000000421', '+15550100011', NULL,
   '[{"inventory_id":"00000000-0000-4000-a000-000000000502","product_name":"STAGING Ballerina Test","size":"24","color":"Negro","quantity":1,"unit_price":999}]', 999.00, 100, NULL),
  ('00000000-0000-4000-a000-000000000602', 'STGA02', '00000000-0000-4000-a000-000000000301', '00000000-0000-4000-a000-000000000421', '+15550100011', '00000000-0000-4000-a000-000000000111',
   '[{"inventory_id":"00000000-0000-4000-a000-000000000501","product_name":"STAGING Ballerina Test","size":"23","color":"Negro","quantity":1,"unit_price":999}]', 999.00, 100, now());

-- F6 orphan web orders (C1's phone; U1's phone)
INSERT INTO public.unmatched_orders (wc_order_id, phone, email, total, currency, pairs, points, items, wc_status) VALUES
  (990000101, '+15550100011', NULL, 999.00, 'MXN', 1, 100, '[{"sku":"STG-BAL-24","product_name":"STAGING Ballerina Test","quantity":1,"unit_price":999}]', 'completed'),
  (990000199, '+15550100099', NULL, 999.00, 'MXN', 1, 100, '[{"sku":"STG-BAL-25","product_name":"STAGING Ballerina Test","quantity":1,"unit_price":999}]', 'completed');

-- F7 pending inventory change request by S1
INSERT INTO public.inventory_change_requests (id, channel_id, requested_by_staff_id, requested_by_name, action, payload, status) VALUES
  ('00000000-0000-4000-a000-000000000701', '00000000-0000-4000-a000-000000000301', '00000000-0000-4000-a000-000000000421', 'STAGING Seller S1', 'adjust_stock',
   '{"channel_inventory_id":"00000000-0000-4000-a000-000000000503","target_stock":6,"current_stock":5,"product_name":"STAGING Ballerina Test","size":"25"}', 'pending');

-- F8 admin fake push token (not Expo format: prefix-filtering functions never call Expo)
INSERT INTO public.push_tokens (id, customer_id, expo_token, platform) VALUES
  ('00000000-0000-4000-a000-000000000801', '00000000-0000-4000-a000-000000000101', 'StagingFakeToken-M1', 'ios');

COMMIT;
