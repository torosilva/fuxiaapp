// In-memory WooCommerce with the semantics the publisher depends on: global attributes/terms, categories,
// unique SKUs across products AND variations, 100-item batch limit, image sideload → media ids, meta, trash.
// Used by unit tests; never deployed.
import type { BatchInput, BatchResult, WooAdapter, WooAttribute, WooCategory, WooImage, WooProduct, WooTerm, WooVariation } from './types.ts';
import { WooError } from './types.ts';

export type MockStore = {
  products: Map<number, WooProduct>;
  variations: Map<number, WooVariation & { parent_id: number }>;
  attributes: WooAttribute[];
  terms: Map<number, WooTerm[]>;
  categories: WooCategory[];
  media: Map<number, WooImage>;
  calls: string[];
  seq: number;   // auto-increment lives in the store (like the DB), not in an adapter instance
};

export function mockStore(): MockStore {
  const s: MockStore = { products: new Map(), variations: new Map(), attributes: [], terms: new Map(), categories: [], media: new Map(), calls: [], seq: 1000 };
  s.attributes.push({ id: 1, name: 'Color', slug: 'pa_color' }, { id: 2, name: 'Medida', slug: 'pa_medida' });
  s.terms.set(1, ['Café', 'Dorado', 'Negro', 'Taupe', 'Verde', 'Vino'].map((n, i) => ({ id: 100 + i, name: n, slug: n.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '') })));
  s.terms.set(2, ['35', '36', '37', '38', '39', '40'].map((n, i) => ({ id: 200 + i, name: n, slug: n })));
  s.categories.push({ id: 17, name: 'Ballerinas', slug: 'ballerinas' }, { id: 18, name: 'Sandalia Alta', slug: 'sandalia-alta' },
    { id: 19, name: 'Sandalia Plana', slug: 'sandalia-plana' }, { id: 20, name: 'Botas', slug: 'botas' });
  return s;
}

const clone = <T>(x: T): T => JSON.parse(JSON.stringify(x));

export function mockAdapter(s: MockStore): WooAdapter {
  const next = () => ++s.seq;
  const skuTaken = (sku: string, exceptId?: number) => !!sku && ([...s.products.values()].some((p) => p.sku === sku && p.id !== exceptId && p.status !== 'trash')
    || [...s.variations.values()].some((v) => v.sku === sku && v.id !== exceptId));
  const images = (list: unknown): WooImage[] => ((list as Record<string, unknown>[]) ?? []).map((i) => {
    if (typeof i.id === 'number') { const m = s.media.get(i.id); if (!m) throw new WooError(400, 'woocommerce_product_invalid_image_id', `#${i.id} no es un id de imagen válido.`); return m; }
    const m: WooImage = { id: next(), src: String(i.src), name: String(i.name ?? ''), alt: String(i.alt ?? '') };
    s.media.set(m.id, m);   // sideloaded into the media library
    return m;
  });
  const applyProduct = (p: WooProduct, b: Record<string, unknown>) => {
    for (const k of ['name', 'type', 'status', 'sku', 'description', 'short_description', 'slug'] as const) if (b[k] !== undefined) (p as Record<string, unknown>)[k] = b[k];
    if (b.categories) p.categories = (b.categories as { id: number }[]).map((c) => {
      const cat = s.categories.find((x) => x.id === c.id); if (!cat) throw new WooError(400, 'woocommerce_rest_invalid_term', 'Categoría no válida'); return { ...cat };
    });
    if (b.images) p.images = images(b.images);
    if (b.attributes) {
      // like real Woo: a global attribute option is stored with the EXISTING term's name ("chocolate" → "Chocolate")
      p.attributes = (clone(b.attributes) as WooProduct['attributes']).map((a) => ({ ...a, options: (a.options ?? []).map((o) => {
        const t = (s.terms.get(a.id) ?? []).find((x) => x.name.toLowerCase() === String(o).toLowerCase()); return t ? t.name : o; }) }));
    }
    if (b.meta_data) for (const m of b.meta_data as { key: string; value: unknown }[]) {
      const hit = p.meta_data.find((x) => x.key === m.key); if (hit) hit.value = m.value; else p.meta_data.push({ id: next(), key: m.key, value: m.value });
    }
  };
  const applyVariation = (v: WooVariation, b: Record<string, unknown>) => {
    for (const k of ['sku', 'status', 'regular_price', 'sale_price', 'manage_stock', 'stock_quantity', 'backorders', 'stock_status'] as const) if (b[k] !== undefined) (v as Record<string, unknown>)[k] = b[k];
    if (b.attributes) v.attributes = clone(b.attributes) as WooVariation['attributes'];
    if (b.image) { const m = s.media.get((b.image as { id: number }).id); if (!m) throw new WooError(400, 'woocommerce_variation_invalid_image_id', 'Imagen no válida'); v.image = m; }
    if (b.meta_data) v.meta_data = clone(b.meta_data) as WooVariation['meta_data'];
  };

  return {
    listAttributes: async () => { s.calls.push('listAttributes'); return clone(s.attributes); },
    listTerms: async (id) => { s.calls.push('listTerms'); return clone(s.terms.get(id) ?? []); },
    createTerm: async (id, name) => {
      s.calls.push('createTerm');
      const list = s.terms.get(id) ?? [];
      if (list.some((t) => t.name.toLowerCase() === name.toLowerCase())) throw new WooError(400, 'term_exists', 'Ya existe');
      const t = { id: next(), name, slug: name.toLowerCase() }; list.push(t); s.terms.set(id, list); return clone(t);
    },
    getCategory: async (id) => { s.calls.push('getCategory'); return clone(s.categories.find((c) => c.id === id) ?? null); },
    findProductBySku: async (sku) => { s.calls.push('findProductBySku'); return clone([...s.products.values()].find((p) => p.sku === sku && p.status !== 'trash') ?? null); },
    getProduct: async (id) => { s.calls.push('getProduct'); const p = s.products.get(id); return p && p.status !== 'trash' ? clone(p) : null; },
    createProduct: async (b) => {
      s.calls.push('createProduct');
      if (skuTaken(String(b.sku ?? ''))) throw new WooError(400, 'product_invalid_sku', 'SKU inválido o duplicado.');
      const p: WooProduct = { id: next(), name: '', type: 'simple', status: 'publish', sku: '', categories: [], images: [], attributes: [], meta_data: [] };
      applyProduct(p, b); s.products.set(p.id, p); return clone(p);
    },
    updateProduct: async (id, b) => {
      s.calls.push('updateProduct');
      const p = s.products.get(id); if (!p) throw new WooError(404, 'woocommerce_rest_product_invalid_id', 'ID no válido.');
      if (b.sku !== undefined && skuTaken(String(b.sku), id)) throw new WooError(400, 'product_invalid_sku', 'SKU duplicado.');
      applyProduct(p, b); return clone(p);
    },
    listVariations: async (pid) => { s.calls.push('listVariations'); return clone([...s.variations.values()].filter((v) => v.parent_id === pid)); },
    batchVariations: async (pid, input: BatchInput): Promise<BatchResult> => {
      s.calls.push('batchVariations');
      if (!s.products.has(pid)) throw new WooError(404, 'woocommerce_rest_product_invalid_id', 'ID no válido.');
      if ((input.create?.length ?? 0) + (input.update?.length ?? 0) > 100) throw new WooError(413, 'woocommerce_rest_request_entity_too_large', 'Máximo 100.');
      const out: BatchResult = {};
      if (input.create) out.create = input.create.map((b) => {
        if (skuTaken(String(b.sku ?? ''))) return { error: { code: 'product_invalid_sku', message: 'SKU duplicado.' } };
        const v = { id: next(), parent_id: pid, sku: '', status: 'publish', regular_price: '', sale_price: '', manage_stock: false, stock_quantity: null, attributes: [], image: null, meta_data: [] } as WooVariation & { parent_id: number };
        try { applyVariation(v, b); } catch (e) { return { error: { code: 'invalid', message: (e as Error).message } }; }
        s.variations.set(v.id, v); const { parent_id: _p, ...pub } = v; return clone(pub);
      });
      if (input.update) out.update = input.update.map((b) => {
        const v = s.variations.get(b.id);
        if (!v || v.parent_id !== pid) return { id: b.id, error: { code: 'woocommerce_rest_product_variation_invalid_id', message: 'Variación no válida.' } };
        if (b.sku !== undefined && skuTaken(String(b.sku), v.id)) return { id: b.id, error: { code: 'product_invalid_sku', message: 'SKU duplicado.' } };
        try { applyVariation(v, b); } catch (e) { return { id: b.id, error: { code: 'invalid', message: (e as Error).message } }; }
        const { parent_id: _p, ...pub } = v; return clone(pub);
      });
      return out;
    },
  };
}
