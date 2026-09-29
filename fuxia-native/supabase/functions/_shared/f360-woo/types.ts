// Fuxia 360 → WooCommerce publisher: shared types. Runtime-agnostic (Deno Edge Functions and Node tests).
// Only erasable TypeScript (no enums / namespaces / parameter properties) so Node can run it with type stripping.

// ── Snapshot returned by public.f360_pub_claim (the database is the single source of truth) ──
export type SnapMedia = { id: string; path: string; alt: string | null; woo_media_id: number | null };
export type SnapColor = { id: string; code: string; name: string; hex: string | null; media: SnapMedia[] };
export type SnapVariant = {
  id: string; color_id: string; size: string; sku: string; status: 'active' | 'archived';
  ats: number; woo_variation_id: number | null; last_pushed_stock: number | null;
};
export type SnapPrice = { code: string; woo_meta_key: string; amount: number | string };
export type Snapshot = {
  job: { id: string; attempt: number; requested_by_name: string; content_hash: string };
  target: { id: string; key: string; base_url: string; is_production: boolean; fulfillment_location_id: string };
  product: {
    id: string; code: string; name: string; slug: string; description: string | null; short_description: string | null;
    regular_price: number | string; sale_price: number | string | null; category_key: string;
    woo_category: { id: number; slug: string } | null; woo_product_id: number | null;
    /** Prices in non-base currencies, each written to the store's own meta key (e.g. COP → _price_cop). */
    prices?: SnapPrice[];
  };
  sizes: string[];
  colors: SnapColor[];
  variants: SnapVariant[];
};

// ── WooCommerce REST shapes (subset we use) ──
export type WooMeta = { id?: number; key: string; value: unknown };
export type WooImage = { id: number; src?: string; name?: string; alt?: string };
export type WooImageInput = { id: number } | { src: string; name: string; alt: string };
export type WooAttrRef = { id: number; name?: string; option?: string; options?: string[]; variation?: boolean; visible?: boolean; position?: number };
export type WooProduct = {
  id: number; name: string; slug?: string; type: string; status: string; sku: string;
  description?: string; short_description?: string;
  categories: { id: number; slug?: string; name?: string }[];
  images: WooImage[]; attributes: WooAttrRef[]; meta_data: WooMeta[];
};
export type WooVariation = {
  id: number; sku: string; status: string; regular_price: string; sale_price: string;
  manage_stock: boolean | 'parent'; stock_quantity: number | null; backorders?: string;
  attributes: { id: number; name?: string; option: string }[]; image: WooImage | null; meta_data: WooMeta[];
};
export type WooAttribute = { id: number; name: string; slug: string };
export type WooTerm = { id: number; name: string; slug: string };
export type WooCategory = { id: number; name: string; slug: string };
export type BatchItemResult<T> = T | { id?: number; error: { code: string; message: string } };
export type BatchInput = { create?: Record<string, unknown>[]; update?: (Record<string, unknown> & { id: number })[] };
export type BatchResult = { create?: BatchItemResult<WooVariation>[]; update?: BatchItemResult<WooVariation>[] };

// ── The adapter: the ONLY thing that talks to a store. REST (real/local Woo) or in-memory mock. ──
export interface WooAdapter {
  listAttributes(): Promise<WooAttribute[]>;
  listTerms(attributeId: number): Promise<WooTerm[]>;
  createTerm(attributeId: number, name: string): Promise<WooTerm>;
  getCategory(id: number): Promise<WooCategory | null>;
  findProductBySku(sku: string): Promise<WooProduct | null>;
  getProduct(id: number): Promise<WooProduct | null>;
  createProduct(body: Record<string, unknown>): Promise<WooProduct>;
  updateProduct(id: number, body: Record<string, unknown>): Promise<WooProduct>;
  listVariations(productId: number): Promise<WooVariation[]>;
  /** purpose only labels the call (e.g. for fault injection in tests); REST ignores it. */
  batchVariations(productId: number, input: BatchInput, purpose: 'variations' | 'stock' | 'hide'): Promise<BatchResult>;
}

// ── Where the publisher writes its audit trail and Woo ids (Supabase RPCs in production code). ──
export type StepAction = 'create' | 'update' | 'link' | 'relink' | 'reuse' | 'check' | 'skip' | 'hide' | 'error';
export type StepName = 'preflight' | 'terms' | 'media' | 'product' | 'variations' | 'stock' | 'verify';
export interface Recorder {
  step(s: { step: StepName; ref?: string | null; action: StepAction; wooId?: number | null; ok: boolean; message?: string; detail?: unknown }): Promise<void>;
  link(kind: 'product' | 'variant' | 'media', f360Id: string, wooId: number, extra?: Record<string, unknown>): Promise<void>;
}

export type PublishOutcome = {
  status: 'succeeded' | 'partial' | 'failed';
  error: string | null;
  summary: {
    woo_product_id: number | null; woo_status: string | null; variations: number; created: number; updated: number;
    hidden: number; stock_pushed: number; mismatches: string[];
  };
};

export class WooError extends Error {
  status: number; code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
