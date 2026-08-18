/**
 * WooCommerce client. Reads use the public WC Store API (`wc/store/v1`) — no auth,
 * exposes prices/stock. Authenticated calls (variations, future orders) go through
 * the Supabase Edge Function `woocommerce-proxy` so the consumer_key/secret never
 * ship in the mobile bundle.
 *
 * Multi-currency: WCPBC's Store API is inconsistent — the `/products` list endpoint
 * returns USD when no country is specified, while `/products/{id}` respects the
 * store's base. To avoid that mismatch we ALWAYS send `wcpbc-manual-country`:
 *   1. User's explicit pick from the country selector (if any).
 *   2. Device region from OS settings (MX → MX, US → US, CO → CO…).
 *   3. 'US' (USD) as international fallback when the region isn't supported.
 */
import { getCountryOverride, detectDeviceCountry } from '@/lib/CountryService';
import { supabase } from '@/lib/supabase';

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
  currency_code: string;
  currency_symbol: string;
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
  meta_data?: { key: string; value: string }[];
  /** Presente cuando viene de la edge function my-orders (rastreo ya extraído). */
  tracking?: { tracking_number: string | null; tracking_provider: string | null; tracking_url: string | null };
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

async function wcPost<T>(path: string, body: Record<string, unknown>): Promise<T | null> {
  try {
    const res = await fetch(PROXY_URL, {
      method: 'POST',
      headers: PROXY_HEADERS,
      body: JSON.stringify({ path, method: 'POST', body }),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.error(`wcPost ${path} → ${res.status} ${errText}`);
      return null;
    }
    return (await res.json()) as T;
  } catch (err) {
    console.error(`wcPost ${path} threw:`, err);
    return null;
  }
}

interface StorePrices {
  price: string;
  regular_price: string;
  sale_price: string;
  currency_minor_unit: number;
  currency_code: string;
  currency_symbol: string;
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
  attributes?: { id: number; name: string; value: string }[];
}

function formatPrice(minor: string | undefined, decimals: number): string {
  if (!minor) return '';
  const n = parseInt(minor, 10);
  if (Number.isNaN(n)) return '';
  return decimals === 0 ? String(n) : (n / Math.pow(10, decimals)).toFixed(decimals);
}

function mapStoreVariation(s: StoreProduct): WCVariation {
  const decimals = s.prices?.currency_minor_unit ?? 0;
  return {
    id: s.id,
    price: formatPrice(s.prices?.price, decimals),
    regular_price: formatPrice(s.prices?.regular_price, decimals),
    sale_price: formatPrice(s.prices?.sale_price, decimals),
    stock_status: s.is_in_stock ? 'instock' : 'outofstock',
    stock_quantity: null,
    attributes: (s.attributes ?? []).map((a) => ({ id: a.id, name: a.name, option: a.value ?? '' })),
  };
}

// ── Overrides de imagen (Supabase) ────────────────────────────────────────
// Mapa wc_product_id -> image_url que vos controlás (bucket Supabase u otra URL),
// para no depender de que la foto exista en WordPress. Se cachea en memoria por
// unos minutos para no consultar en cada fetch de productos.
let _overridesCache: { at: number; map: Map<number, string> } | null = null;
const OVERRIDES_TTL_MS = 5 * 60 * 1000;

async function getImageOverrides(): Promise<Map<number, string>> {
  if (_overridesCache && Date.now() - _overridesCache.at < OVERRIDES_TTL_MS) {
    return _overridesCache.map;
  }
  try {
    const { data, error } = await supabase
      .from('product_image_overrides')
      .select('wc_product_id, image_url');
    const map = new Map<number, string>();
    if (!error && data) {
      for (const r of data as { wc_product_id: number; image_url: string }[]) {
        if (r.image_url) map.set(r.wc_product_id, r.image_url);
      }
    }
    _overridesCache = { at: Date.now(), map };
    return map;
  } catch (err) {
    console.error('getImageOverrides threw:', err);
    return _overridesCache?.map ?? new Map();
  }
}

// Prepende el override (si existe) para que `images[0]` sea la foto elegida por
// nosotros; conserva las de la web como respaldo.
function applyImageOverride(p: WCProduct, overrides: Map<number, string>): WCProduct {
  const url = overrides.get(p.id);
  if (!url) return p;
  return {
    ...p,
    images: [{ id: -1, src: url, alt: p.name }, ...p.images.filter((i) => i.src !== url)],
  };
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
    currency_code: s.prices?.currency_code ?? 'MXN',
    currency_symbol: s.prices?.currency_symbol ?? '$',
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
  const override = await getCountryOverride();
  const country = override ?? detectDeviceCountry();
  url.searchParams.set('wcpbc-manual-country', country);
  try {
    // Android's HTTP client (OkHttp) caches GET responses by URL. If the first
    // request was made with a different country override, switching country
    // serves the stale response. Force a fresh fetch every time so WCPBC's
    // per-country pricing always reflects the current selection.
    const res = await fetch(url.toString(), { cache: 'no-store' as RequestCache });
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

/** Append the WCPBC country param to a permalink so the web shows the same currency as the app. */
export async function withCountryParam(url: string): Promise<string> {
  if (!url) return url;
  const country = (await getCountryOverride()) ?? detectDeviceCountry();
  const sep = url.includes('?') ? '&' : '?';
  return `${url}${sep}wcpbc-manual-country=${country}`;
}

class WooCommerceService {
  async getProducts(params: Record<string, string | number> = {}): Promise<WCProduct[]> {
    const [data, overrides] = await Promise.all([
      storeGet<StoreProduct[]>('products', { per_page: 100, ...params }),
      getImageOverrides(),
    ]);
    return (data ?? []).map(mapStoreProduct).map((p) => applyImageOverride(p, overrides));
  }

  async getProduct(id: string | number): Promise<WCProduct | null> {
    const [data, overrides] = await Promise.all([
      storeGet<StoreProduct>(`products/${id}`),
      getImageOverrides(),
    ]);
    return data ? applyImageOverride(mapStoreProduct(data), overrides) : null;
  }

  async getProductVariations(productId: number, variationIds: number[] = []): Promise<WCVariation[]> {
    if (variationIds.length === 0) return [];
    const results = await Promise.all(
      variationIds.slice(0, 30).map((vid) => storeGet<StoreProduct>(`products/${vid}`)),
    );
    return results.filter(Boolean).map((v) => mapStoreVariation(v!));
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

  /**
   * Pedidos de la clienta autenticada, via la edge function `my-orders`.
   * SEGURO: exige el JWT del usuario y WooCommerce se consulta server-side con
   * SU identidad. Reemplaza al viejo getOrdersByCustomer que descargaba órdenes
   * de toda la tienda y filtraba en el cliente.
   */
  async getMyOrders(opts: { statuses?: WCOrderStatus[]; limit?: number } = {}): Promise<WCOrder[]> {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.access_token) return [];
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/my-orders`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ statuses: opts.statuses, limit: opts.limit ?? 30 }),
      });
      if (!res.ok) {
        console.error(`getMyOrders → ${res.status}`);
        return [];
      }
      const data = await res.json();
      return (data?.orders ?? []) as WCOrder[];
    } catch (err) {
      console.error('getMyOrders threw:', err);
      return [];
    }
  }

  /** Find an existing WC customer by email, or create one. Returns wc_customer_id or null on failure. */
  async findOrCreateWCCustomer(email: string, name: string, phone: string): Promise<number | null> {
    // role=all finds any WP user (admins, editors, etc.), not just customers
    const found = await wcGet<{ id: number }[]>('customers', { email, per_page: 1, role: 'all' });
    if (found && found.length > 0) return found[0].id;

    const [firstName, ...rest] = name.trim().split(' ');
    const lastName = rest.join(' ');
    const created = await wcPost<{ id: number }>('customers', {
      email,
      first_name: firstName,
      last_name: lastName,
      billing: { first_name: firstName, last_name: lastName, email, phone },
    });
    return created?.id ?? null;
  }
}

export const wcService = new WooCommerceService();
