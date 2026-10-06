// In-memory stand-in for the P2.2 database side (f360_pub_claim snapshot + f360_pub_link + f360_pub_step), so the
// publisher can be run repeatedly exactly like the Edge Function does: every run starts from a FRESH snapshot
// built from the stored links (nothing carried over in memory between runs).
import type { Recorder, Snapshot, SnapVariant } from '../types.ts';

export type Base = Omit<Snapshot, 'job' | 'target'> & { stock: Record<string, number> };   // stock by SKU (Bodega CDMX)

export function macarena(): Base {
  const colors = [['Nude', 'NUDE'], ['Negro', 'NEGRO'], ['Rojo', 'ROJO']].map(([name, code], i) => ({
    id: `c-${code.toLowerCase()}`, code, name, hex: null,
    media: [1, 2].map((n) => ({ id: `m-${code.toLowerCase()}-${n}`, path: `f360/MACARENA/${code}/${n}.png`, alt: null, woo_media_id: null })),
    _i: i,
  }));
  const sizes = ['35', '36', '37', '38', '39', '40'];
  const variants: SnapVariant[] = colors.flatMap((c) => sizes.map((size) => ({
    id: `v-${c.code.toLowerCase()}-${size}`, color_id: c.id, size, sku: `F360-MACARENA-${c.code}-${size}`, status: 'active' as const,
    ats: 0, woo_variation_id: null, last_pushed_stock: null,
  })));
  return {
    product: { id: 'p-macarena', code: 'MACARENA', name: 'Macarena', slug: 'macarena', description: 'Ballerina de piel.', short_description: 'La clásica.',
      regular_price: 2800, sale_price: null, category_key: 'ballerinas', woo_category: { id: 17, slug: 'ballerinas' }, woo_product_id: null },
    sizes, colors: colors.map(({ _i, ...c }) => c), variants,
    stock: { 'F360-MACARENA-NUDE-35': 4, 'F360-MACARENA-NUDE-37': 4, 'F360-MACARENA-NUDE-39': 4, 'F360-MACARENA-NEGRO-37': 2 },
  };
}

export class FakeDb {
  base: Base;
  productLink: number | null = null;
  variantLinks = new Map<string, { woo: number; stock: number | null }>();
  mediaLinks = new Map<string, number>();
  steps: { job: number; step: string; ref?: string | null; action: string; ok: boolean; message?: string }[] = [];
  jobs = 0;
  isProduction = false;
  capabilities: Partial<Pick<Snapshot['target'], 'catalog_mode' | 'stock_sync_mode' | 'stock_policy'>> = {};   // U1/U2

  constructor(base: Base) { this.base = base; }

  /** Equivalent of public.f360_pub_claim: a fresh snapshot with the currently stored Woo links. */
  claim(): Snapshot {
    this.jobs++;
    const b = structuredClone(this.base);
    return {
      job: { id: `job-${this.jobs}`, attempt: 1, requested_by_name: 'Carolina', content_hash: 'h' },
      target: { id: 't-local', key: 'woo_local', base_url: 'http://localhost:8080', is_production: this.isProduction, fulfillment_location_id: 'bodega', ...this.capabilities },
      product: { ...b.product, woo_product_id: this.productLink },
      sizes: b.sizes,
      colors: b.colors.map((c) => ({ ...c, media: c.media.map((m) => ({ ...m, woo_media_id: this.mediaLinks.get(m.id) ?? null })) })),
      variants: b.variants.map((v) => ({ ...v, ats: b.stock[v.sku] ?? 0, woo_variation_id: this.variantLinks.get(v.id)?.woo ?? null,
        last_pushed_stock: this.variantLinks.get(v.id)?.stock ?? null })),
    };
  }

  recorder(): Recorder {
    const job = this.jobs;
    return {
      step: async (s) => { this.steps.push({ job, step: s.step, ref: s.ref, action: s.action, ok: s.ok, message: s.message }); },
      link: async (kind, id, woo, extra) => {
        if (kind === 'product') this.productLink = woo;
        else if (kind === 'media') this.mediaLinks.set(id, woo);
        else {
          const prev = this.variantLinks.get(id);
          this.variantLinks.set(id, { woo, stock: extra && 'stock' in extra ? Number(extra.stock) : prev?.stock ?? null });
        }
      },
    };
  }
}
