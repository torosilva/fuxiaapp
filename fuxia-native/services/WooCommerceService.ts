/**
 * WooCommerce client. Reads use the public WC Store API (`wc/store/v1`) — no auth,
 * exposes prices/stock. Authenticated calls (variations, future orders) go through
 * the Supabase Edge Function `woocommerce-proxy` so the consumer_key/secret never
 * ship in the mobile bundle.
 */
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

const STORE_BASE = 'https://fuxiaballerinas.com/wp-json/wc/store/v1';
const PROXY_URL = `${SUPABASE_URL}/functions/v1/woocommerce-proxy`;
const PROXY_HEADERS = {
  'Content-Type': 'application/json',
  'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
};

export interface WCProduct {
  id: number;
  name: string;
  slug: string;
  permalink: string;
  type: string;
  status: string;
  description: string;
  short_description: string;
  price: string;
  regular_price: string;
  sale_price: string;
  stock_status: 'instock' | 'outofstock' | 'onbackorder';
  stock_quantity: number | null;
  images: { id: number; src: string; alt: string }[];
  categories: { id: number; name: string; slug: string }[];
  variations: number[];
}

export interface WCCategory {
  id: number;
  name: string;
  slug: string;
  count: number;
  image: { src: string; alt: string } | null;
}

export type WCOrderStatus =
  | 'pending' | 'processing' | 'on-hold' | 'completed'
  | 'cancelled' | 'refunded' | 'failed';

export interface WCOrder {
  id: number; number: string; status: WCOrderStatus;
  date_created: string; date_modified: string;
  date_completed: string | null; date_paid: string | null;
  total: string; currency: string; payment_method_title: string;
  customer_id: number;
  billing: { first_name?: string; last_name?: string; email?: string; phone?: string; address_1?: string; city?: string; postcode?: string; country?: string; };
  shipping: { first_name?: string; last_name?: string; address_1?: string; city?: string; postcode?: string; country?: string; };
  shipping_lines: { method_title: string; total: string }[];
  line_items: { id: number; name: string; sku: string; quantity: number; total: string; image?: { src: string } }[];
  meta_data: { key: string; value: string }[];
}

export interface WCVariation {
  id: number;
  price: string;
  regular_price: string;
  sale_price: string;
  stock_status: 'instock' | 'outofstock' | 'onbackorder';
  stock_quantity: number | null;
  attributes: { id: number; name: string; option: string }[];
}

async function wcGet<T>(path: string, params: Record<string, string | number> = {}): Promise<T | null> {
  try {
    const res = await fetch(PROXY_URL, {
      method: 'POST',
      headers: PROXY_HEADERS,
      body: JSON.stringify({ path, params }),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.error(`wcGet ${path} → ${res.status} ${errText}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (err) {
    console.error(`wcGet ${path} threw:`, err);
    return null;
  }
}

interface StorePrices {
  price: string;
  regular_price: string;
  sale_price: string;
  currency_minor_unit: number;
  currency_code: string;
}

interface StoreCategory {
  id: number; name: string; slug: string; count: number;
  image: { id: number; src: string; thumbnail: string; alt: string } | null;
}

interface StoreProduct {
  id: number;
  name: string;
  slug: string;
  permalink: string;
  type: string;
  short_description: string;
  description: string;
  on_sale: boolean;
  prices: StorePrices;
  images: { id: number; src: string; alt: string }[];
  categories: { id: number; name: string; slug: string }[];
  is_in_stock: boolean;
  variations: { id: number }[];
}

function formatPrice(minor: string | undefined, decimals: number): string {
  if (!minor) return '';
  const n = parseInt(minor, 10);
  if (Number.isNaN(n)) return '';
  return decimals === 0 ? String(n) : (n / Math.pow(10, decimals)).toFixed(decimals);
}

function mapStoreProduct(s: StoreProduct): WCProduct {
  const decimals = s.prices?.currency_minor_unit ?? 0;
  return {
    id: s.id,
    name: s.name,
    slug: s.slug,
    permalink: s.permalink,
    type: s.type,
    status: 'publish',
    description: s.description,
    short_description: s.short_description,
    price: formatPrice(s.prices?.price, decimals),
    regular_price: formatPrice(s.prices?.regular_price, decimals),
    sale_price: formatPrice(s.prices?.sale_price, decimals),
    stock_status: s.is_in_stock ? 'instock' : 'outofstock',
    stock_quantity: null,
    images: s.images || [],
    categories: s.categories || [],
    variations: (s.variations || []).map((v) => v.id),
  };
}

async function storeGet<T>(path: string, params: Record<string, string | number> = {}): Promise<T | null> {
  const url = new URL(`${STORE_BASE}/${path}`);
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, String(v));
  }
  try {
    const res = await fetch(url.toString());
    if (!res.ok) {
      console.error(`storeGet ${path} → ${res.status}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (err) {
    console.error(`storeGet ${path} threw:`, err);
    return null;
  }
}

class WooCommerceService {
  async getProducts(params: Record<string, string | number> = {}): Promise<WCProduct[]> {
    const data = await storeGet<StoreProduct[]>('products', { per_page: 100, ...params });
    return (data ?? []).map(mapStoreProduct);
  }

  async getProduct(id: string | number): Promise<WCProduct | null> {
    const data = await storeGet<StoreProduct>(`products/${id}`);
    return data ? mapStoreProduct(data) : null;
  }

  async getProductVariations(productId: number): Promise<WCVariation[]> {
    const variations = await wcGet<WCVariation[]>(`products/${productId}/variations`, { per_page: 100 });
    return variations ?? [];
  }

  /** Category images from fuxiaballerinas.com — UI provides local fallback if offline */
  async getCategories(): Promise<WCCategory[]> {
    const data = await storeGet<StoreCategory[]>('products/categories', {
      per_page: 50,
      hide_empty: 1,
    });
    if (!data) return [];
    return data.map((c) => ({
      id: c.id, name: c.name, slug: c.slug, count: c.count,
      image: c.image ? { src: c.image.src, alt: c.image.alt } : null,
    }));
  }

  async getOrdersByCustomer(opts: {
    customerId?: number; email?: string;
    statuses?: WCOrderStatus[]; limit?: number;
  }): Promise<WCOrder[]> {
    const { customerId, email, statuses, limit = 30 } = opts;
    const params: Record<string, string | number> = {
      per_page: Math.min(limit, 100), orderby: 'date', order: 'desc',
    };
    if (customerId) params.customer = customerId;
    if (statuses?.length) params.status = statuses.join(',');
    const orders = await wcGet<WCOrder[]>('orders', params);
    if (!orders) return [];
    if (customerId) return orders;
    if (email) {
      const lower = email.toLowerCase();
      return orders.filter((o) => o.billing?.email?.toLowerCase() === lower);
    }
    return orders;
  }

  async getOrder(id: number): Promise<WCOrder | null> {
    return wcGet<WCOrder>(`orders/${id}`);
  }
}

export const wcService = new WooCommerceService();
