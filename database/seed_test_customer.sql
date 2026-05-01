-- Test customer seed: info@fuxiaballerinas.com
-- Generates: 1 customer + loyalty_card + 5 completed historical purchases
--            + 2 in-progress (status = 'processing'/'shipped') purchases
--            + purchase_items for each
--            + recomputes total_points, pairs_count, tier
--
-- Idempotent: re-running upserts the customer and replaces transactions.

-- 1. Add `status` column to transactions if missing (for "en seguimiento" tracking).
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS status TEXT
    DEFAULT 'completed'
    CHECK (status IN ('processing', 'shipped', 'completed', 'cancelled', 'refunded'));

DO $$
DECLARE
  v_customer_id UUID;
  v_card_id     UUID;
  v_tx_id       UUID;
  v_total_pts   INTEGER;
  v_total_prs   INTEGER;
  v_tier        TEXT;
BEGIN
  -- ── 1. Customer ─────────────────────────────────────────────────────────
  INSERT INTO customers (phone, name, email, country)
  VALUES ('+525500000001', 'Fuxia Test', 'info@fuxiaballerinas.com', 'MX')
  ON CONFLICT (phone) DO UPDATE
    SET email = EXCLUDED.email,
        name  = EXCLUDED.name
  RETURNING id INTO v_customer_id;

  -- ── 2. Loyalty card ─────────────────────────────────────────────────────
  -- Wipe any prior card+transactions for clean re-seed
  DELETE FROM purchase_items
   WHERE transaction_id IN (
     SELECT t.id FROM transactions t
     JOIN loyalty_cards lc ON lc.id = t.loyalty_card_id
     WHERE lc.customer_id = v_customer_id
   );
  DELETE FROM transactions
   WHERE loyalty_card_id IN (SELECT id FROM loyalty_cards WHERE customer_id = v_customer_id);
  DELETE FROM loyalty_cards WHERE customer_id = v_customer_id;

  INSERT INTO loyalty_cards (customer_id, qr_code, total_points, pairs_count, tier)
  VALUES (v_customer_id, 'FX-TEST-INFO-' || floor(extract(epoch from now()))::TEXT, 0, 0, 'bronze')
  RETURNING id INTO v_card_id;

  -- ── 3. Completed historical purchases (5) ───────────────────────────────
  -- Points = floor(amount/50) + 10 * pairs

  -- #1  -120 días | $2,700 | 1 par | 64 pts
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90001, 2700.00, 64, 1, 'web', 'completed', NOW() - INTERVAL '120 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price)
  VALUES (v_tx_id, 'PAULA-23-BEIGE', 'Paula beige con talco', '23', 'Beige', 'Ballerinas', 1, 2700.00);

  -- #2  -90 días | $5,400 | 2 pares | 128 pts
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90002, 5400.00, 128, 2, 'web', 'completed', NOW() - INTERVAL '90 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price) VALUES
    (v_tx_id, 'PAULA-24-NEGRO',   'Paula negro patente',  '24', 'Negro', 'Ballerinas',     1, 2700.00),
    (v_tx_id, 'TACON-RMX-23',     'Tacones RMX H1',       '23', 'Nude',  'Sandalia Alta', 1, 2700.00);

  -- #3  -60 días | $3,200 | 1 par | 74 pts
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90003, 3200.00, 74, 1, 'store', 'completed', NOW() - INTERVAL '60 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price)
  VALUES (v_tx_id, 'BOTA-JO-24-NEGRO', 'Botas JO', '24', 'Negro', 'Botas', 1, 3200.00);

  -- #4  -30 días | $4,500 | 2 pares | 110 pts
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90004, 4500.00, 110, 2, 'web', 'completed', NOW() - INTERVAL '30 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price) VALUES
    (v_tx_id, 'SAND-CH2-24',  'Sandalia ch2',           '24', 'Dorado', 'Sandalia Plana', 1, 2200.00),
    (v_tx_id, 'TACON-RMX-24', 'Tacones RMX H1 (negro)', '24', 'Negro',  'Sandalia Alta',  1, 2300.00);

  -- #5  -7 días | $5,800 | 2 pares | 136 pts
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90005, 5800.00, 136, 2, 'web', 'completed', NOW() - INTERVAL '7 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price) VALUES
    (v_tx_id, 'PAULA-23-ROJO',   'Paula rojo carmín',  '23', 'Rojo',  'Ballerinas',     1, 2900.00),
    (v_tx_id, 'TACON-RMX-23-NU', 'Tacones RMX H1 nude','23', 'Nude',  'Sandalia Alta',  1, 2900.00);

  -- ── 4. In-progress purchases (en seguimiento) ───────────────────────────
  -- #6  -3 días | $3,500 | 1 par | shipped
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90006, 3500.00, 80, 1, 'web', 'shipped', NOW() - INTERVAL '3 days')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price)
  VALUES (v_tx_id, 'BOTA-JO-23-CAMEL', 'Botas JO camel', '23', 'Camel', 'Botas', 1, 3500.00);

  -- #7  -1 día | $2,700 | 1 par | processing
  INSERT INTO transactions (loyalty_card_id, wc_order_id, amount, points_earned, pairs_in_order, channel, status, created_at)
  VALUES (v_card_id, 90007, 2700.00, 64, 1, 'web', 'processing', NOW() - INTERVAL '1 day')
  RETURNING id INTO v_tx_id;
  INSERT INTO purchase_items (transaction_id, sku, product_name, size, color, category, quantity, unit_price)
  VALUES (v_tx_id, 'SAND-CH2-25', 'Sandalia ch2 plata', '25', 'Plata', 'Sandalia Plana', 1, 2700.00);

  -- ── 5. Recompute card totals (only completed counts toward points/tier) ─
  SELECT
    COALESCE(SUM(points_earned),  0),
    COALESCE(SUM(pairs_in_order), 0)
  INTO v_total_pts, v_total_prs
  FROM transactions
  WHERE loyalty_card_id = v_card_id
    AND status = 'completed';

  v_tier := CASE
    WHEN v_total_pts >= 1201 OR v_total_prs >= 13 THEN 'gold'
    WHEN v_total_pts >= 501  OR v_total_prs >= 6  THEN 'silver'
    ELSE 'bronze'
  END;

  UPDATE loyalty_cards
     SET total_points = v_total_pts,
         pairs_count  = v_total_prs,
         tier         = v_tier
   WHERE id = v_card_id;

  RAISE NOTICE 'Seeded customer % | card % | % pts | % pares | tier=%',
    v_customer_id, v_card_id, v_total_pts, v_total_prs, v_tier;
END $$;
