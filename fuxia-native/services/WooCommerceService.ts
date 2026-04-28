/**
 * WooCommerce proxy client. All requests go through the Supabase Edge Function
 * `woocommerce-proxy` so the consumer_key/secret never ship in the mobile bundle.
 *
 * The proxy only allows read-only GETs on product endpoints. If you need more
 * endpoints (orders, customers, etc.) extend ALLOWED_PATTERNS in the edge function.
 */
const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY!;

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

class WooCommerceService {
  async getProducts(extraParams: Record<string, string | number> = { status: 'publish' }): Promise<WCProduct[]> {
    const all: WCProduct[] = [];
    const perPage = 100;
    let page = 1;
    while (true) {
      const batch = await wcGet<WCProduct[]>('products', {
        ...extraParams,
        per_page: perPage,
        page,
      });
      if (!batch || batch.length === 0) break;
      all.push(...batch);
      if (batch.length < perPage) break;
      page += 1;
      if (page > 20) break; // safety cap: 2000 products max
    }
    return all;
  }

  async getProduct(id: string | number): Promise<WCProduct | null> {
    return wcGet<WCProduct>(`products/${id}`);
  }

  async getProductVariations(productId: number): Promise<WCVariation[]> {
    const variations = await wcGet<WCVariation[]>(`products/${productId}/variations`, { per_page: 100 });
    return variations ?? [];
  }
}

export const wcService = new WooCommerceService();
