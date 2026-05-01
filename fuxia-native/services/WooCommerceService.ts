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

export interface WCCategory {
  id: number;
  name: string;
  slug: string;
  count: number;
  image: { src: string; alt: string } | null;
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

export type WCOrderStatus =
  | 'pending'
  | 'processing'
  | 'on-hold'
  | 'completed'
  | 'cancelled'
  | 'refunded'
  | 'failed';

export interface WCOrder {
  id: number;
  number: string;
  status: WCOrderStatus;
  date_created: string;
  date_modified: string;
  date_completed: string | null;
  date_paid: string | null;
  total: string;
  currency: string;
  payment_method_title: string;
  customer_id: number;
  billing: {
    first_name?: string;
    last_name?: string;
    email?: string;
    phone?: string;
    address_1?: string;
    city?: string;
    postcode?: string;
    country?: string;
  };
  shipping: {
    first_name?: string;
    last_name?: string;
    address_1?: string;
    city?: string;
    postcode?: string;
    country?: string;
  };
  shipping_lines: { method_title: string; total: string }[];
  line_items: {
    id: number;
    name: string;
    sku: string;
    quantity: number;
    total: string;
    image?: { src: string };
  }[];
  meta_data: { key: string; value: string }[];
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
    // If caller explicitly sets a small per_page, respect it and skip pagination
    const explicitLimit = extraParams.per_page ? Number(extraParams.per_page) : null;
    if (explicitLimit && explicitLimit <= 100) {
      const batch = await wcGet<WCProduct[]>('products', { ...extraParams });
      return batch ?? [];
    }
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

  /**
   * Pulls orders for a customer. WooCommerce REST API supports filtering by `customer`
   * (numeric WC user id) or by `search` against billing email. We try both routes:
   * if `customerId` is provided we use it (most reliable), otherwise we filter the
   * full list by billing email client-side. Returns most-recent first.
   */
  async getOrdersByCustomer(opts: {
    customerId?: number;
    email?: string;
    statuses?: WCOrderStatus[];
    limit?: number;
  }): Promise<WCOrder[]> {
    const { customerId, email, statuses, limit = 30 } = opts;
    const params: Record<string, string | number> = {
      per_page: Math.min(limit, 100),
      orderby: 'date',
      order: 'desc',
    };
    if (customerId) params.customer = customerId;
    if (statuses && statuses.length) params.status = statuses.join(',');

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

  async getCategories(): Promise<WCCategory[]> {
    const data = await wcGet<WCCategory[]>('products/categories', {
      per_page: 50,
      hide_empty: 1,
      orderby: 'count',
      order: 'desc',
    });
    return data ?? [];
  }
}

export const wcService = new WooCommerceService();
