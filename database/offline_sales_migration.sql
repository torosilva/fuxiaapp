SET search_path = public;

-- Add role to customers
ALTER TABLE public.customers ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'customer' CHECK (role IN ('customer', 'staff', 'admin'));

-- Sales channels (tienda física / bazar)
CREATE TABLE IF NOT EXISTS public.channels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('store', 'bazar')),
  location TEXT,
  event_date DATE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Staff / vendedoras
CREATE TABLE IF NOT EXISTS public.staff (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  pin TEXT NOT NULL,
  channel_id UUID REFERENCES public.channels(id) ON DELETE SET NULL,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Channel inventory (independent from WooCommerce)
CREATE TABLE IF NOT EXISTS public.channel_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  channel_id UUID REFERENCES public.channels(id) ON DELETE CASCADE,
  product_name TEXT NOT NULL,
  sku TEXT,
  size TEXT NOT NULL,
  color TEXT,
  price DECIMAL(10,2) NOT NULL,
  stock INTEGER DEFAULT 0,
  sold INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Offline sales with claim codes
CREATE TABLE IF NOT EXISTS public.offline_sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  channel_id UUID REFERENCES public.channels(id),
  staff_id UUID REFERENCES public.staff(id),
  customer_phone TEXT,
  customer_id UUID REFERENCES public.customers(id),
  items JSONB NOT NULL,
  total DECIMAL(10,2) NOT NULL,
  points_earned INTEGER DEFAULT 0,
  claimed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
