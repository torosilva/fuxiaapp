-- Fuxia Ballerinas — Loyalty System Schema

-- customers: vinculado a WooCommerce
CREATE TABLE customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  email TEXT,
  country TEXT DEFAULT 'MX',
  wc_customer_id INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- loyalty_cards: una por cliente, contiene el QR
CREATE TABLE loyalty_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID REFERENCES customers(id) ON DELETE CASCADE,
  qr_code TEXT UNIQUE NOT NULL,
  total_points INTEGER DEFAULT 0,
  pairs_count INTEGER DEFAULT 0,
  tier TEXT DEFAULT 'bronze' CHECK (tier IN ('bronze', 'silver', 'gold')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- tier_config: configuración de niveles
CREATE TABLE tier_config (
  tier TEXT PRIMARY KEY,
  min_pairs INTEGER NOT NULL,
  min_points INTEGER NOT NULL,
  reward_description TEXT,
  reward_sku TEXT
);

-- transactions: sincronizadas desde WooCommerce via webhook
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  wc_order_id INTEGER UNIQUE,
  amount DECIMAL(10,2) NOT NULL,
  currency TEXT DEFAULT 'MXN',
  points_earned INTEGER NOT NULL,
  pairs_in_order INTEGER DEFAULT 0,
  channel TEXT DEFAULT 'web' CHECK (channel IN ('web', 'store', 'app')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- purchase_items: detalle de cada par comprado
CREATE TABLE purchase_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id UUID REFERENCES transactions(id),
  sku TEXT NOT NULL,
  product_name TEXT NOT NULL,
  size TEXT,
  color TEXT,
  category TEXT,
  quantity INTEGER DEFAULT 1,
  unit_price DECIMAL(10,2)
);

-- rewards: canjes y recompensas ganadas
CREATE TABLE rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  type TEXT CHECK (type IN ('tier_upgrade', 'points_redemption', 'special')),
  threshold_points INTEGER,
  product_sku TEXT,
  description TEXT,
  redeemed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- qr_scans: log de escaneos en tienda
CREATE TABLE qr_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  loyalty_card_id UUID REFERENCES loyalty_cards(id),
  store_id TEXT,
  staff_id TEXT,
  channel TEXT CHECK (channel IN ('store', 'web')),
  scanned_at TIMESTAMPTZ DEFAULT NOW()
);

-- Datos iniciales de niveles
INSERT INTO tier_config VALUES
  ('bronze', 0, 0, 'Accesorio gratis (hasta $300 MXN)', 'REWARD-BRONZE'),
  ('silver', 6, 501, '1 par de flats básico gratis', 'REWARD-SILVER'),
  ('gold', 13, 1201, '1 par de flats premium gratis', 'REWARD-GOLD');

-- Trigger: auto-update updated_at on loyalty_cards
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER loyalty_cards_updated_at
  BEFORE UPDATE ON loyalty_cards
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
