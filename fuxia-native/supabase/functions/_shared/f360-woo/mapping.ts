// Pure Fuxia 360 → Woo payload builders (no I/O). Every rule here is an approved decision:
//   one model = one variable product (DW1) · color + Colombian size = variation · one price per model (P-PRICE)
//   first publish non-public (DW3) · SKU F360-{PRODUCT}-{COLOR}-{SIZE} (DW9) · stock = Bodega CDMX sellable (P-STOCK)
import type { Snapshot, SnapColor, SnapVariant, WooImageInput, WooMeta, WooProduct, WooVariation } from './types.ts';

export const META_PRODUCT = '_fuxia360_product_id';
export const META_MANAGED = '_fuxia360_managed';
export const META_VARIANT = '_fuxia360_variant_id';
export const COLOR_ATTR = 'pa_color';
export const SIZE_ATTR = 'pa_medida';

export const parentSku = (code: string) => `F360-${code}`;
export const mediaName = (mediaId: string) => `f360-${mediaId}`;
export const money = (v: number | string | null | undefined) => (v == null || v === '' ? '' : String(Number(v)));
export const publicImageUrl = (storageBase: string, path: string) =>
  `${storageBase.replace(/\/+$/, '')}/storage/v1/object/public/product-images/${path.split('/').map(encodeURIComponent).join('/')}`;

/** Currency prices as Woo meta (COP → _price_cop …), the same fields the store's variation form edits. */
export const priceMeta = (s: Snapshot) => (s.product.prices ?? []).map((p) => ({ key: p.woo_meta_key, value: money(p.amount) }));

export const metaValue = (meta: WooMeta[] | undefined, key: string) => meta?.find((m) => m.key === key)?.value;
export const isManagedBy = (p: WooProduct, productId: string) =>
  String(metaValue(p.meta_data, META_MANAGED) ?? '') === '1' && String(metaValue(p.meta_data, META_PRODUCT) ?? '') === productId;

export const activeVariants = (s: Snapshot) => s.variants.filter((v) => v.status === 'active');
export const colorOf = (s: Snapshot, v: SnapVariant) => s.colors.find((c) => c.id === v.color_id)!;
/** Woo media id of a color's main photo (first photo), once uploaded. */
export const primaryWooMedia = (c: SnapColor) => c.media[0]?.woo_media_id ?? null;

/** Gallery: every photo of every color, in color order (color → its photos). Linked photos by id, new ones by URL. */
export function buildImages(s: Snapshot, storageBase: string): WooImageInput[] {
  return s.colors.flatMap((c) => c.media.map((m): WooImageInput =>
    m.woo_media_id ? { id: m.woo_media_id } : { src: publicImageUrl(storageBase, m.path), name: mediaName(m.id), alt: m.alt || `${s.product.name} ${c.name}` }));
}

export function buildParent(s: Snapshot, ids: { colorAttr: number; sizeAttr: number }, images: WooImageInput[], isCreate: boolean) {
  const body: Record<string, unknown> = {
    name: s.product.name,
    type: 'variable',
    sku: parentSku(s.product.code),
    description: s.product.description ?? '',
    short_description: s.product.short_description ?? '',
    categories: [{ id: s.product.woo_category!.id }],
    images,
    attributes: [
      { id: ids.colorAttr, position: 0, visible: true, variation: true, options: s.colors.map((c) => c.name) },
      { id: ids.sizeAttr, position: 1, visible: true, variation: true, options: s.sizes },
    ],
    manage_stock: false,
    meta_data: [{ key: META_PRODUCT, value: s.product.id }, { key: META_MANAGED, value: '1' }, { key: '_fuxia360_code', value: s.product.code }, ...priceMeta(s)],
  };
  // DW3: created NON-public. On later syncs the visibility is never touched (an owner decides it; P2.3).
  if (isCreate) { body.status = 'draft'; body.slug = s.product.slug; }
  return body;
}

/** Variation content. Stock is NOT set here (see buildStock); new variations start at 0 = never oversell. */
export function buildVariation(s: Snapshot, v: SnapVariant, ids: { colorAttr: number; sizeAttr: number }, isCreate: boolean) {
  const c = colorOf(s, v);
  const img = primaryWooMedia(c);
  const body: Record<string, unknown> = {
    sku: v.sku,
    status: 'publish',                    // variation enabled; the PARENT stays draft, so nothing is public
    regular_price: money(s.product.regular_price),   // P-PRICE: same price for every color and size
    sale_price: money(s.product.sale_price),
    attributes: [{ id: ids.colorAttr, option: c.name }, { id: ids.sizeAttr, option: v.size }],
    manage_stock: true,
    backorders: 'no',
    meta_data: [{ key: META_VARIANT, value: v.id }, ...priceMeta(s)],
  };
  if (img) body.image = { id: img };
  if (isCreate) body.stock_quantity = 0;
  return body;
}

/**
 * P-STOCK: Woo quantity = actual sellable stock in the fulfillment location (Bodega CDMX). No reserve.
 * The only correction: units Woo already sold that the ledger hasn't ingested yet (last pushed − current Woo
 * stock) are not added back. With no pending Woo sales this is 0, so Woo = ATS exactly.
 */
export function stockToPush(ats: number, lastPushed: number | null, currentWoo: number | null) {
  const unsynced = lastPushed != null && currentWoo != null ? Math.max(0, lastPushed - currentWoo) : 0;
  return Math.max(0, ats - unsynced);
}

export const isF360VariationOf = (w: WooVariation, code: string) => w.sku?.startsWith(`${parentSku(code)}-`);

/** Read-back verification: every expectation that must hold for "Publicado". Returns human-readable mismatches. */
export function verify(s: Snapshot, p: WooProduct | null, vars: WooVariation[], ids: { colorAttr: number; sizeAttr: number },
  expectedStock: Map<string, number>): string[] {
  const out: string[] = [];
  if (!p) return ['el producto no existe en la tienda'];
  if (p.type !== 'variable') out.push(`tipo ${p.type} (esperado variable)`);
  if (p.sku !== parentSku(s.product.code)) out.push(`SKU del producto ${p.sku}`);
  if (p.name !== s.product.name) out.push('nombre distinto');
  if (p.status === 'publish') out.push('el producto está PÚBLICO (P2.2 solo publica oculto)');
  if (!p.categories.some((c) => c.id === s.product.woo_category?.id)) out.push('categoría distinta');
  const sameSet = (a: string[], b: string[]) => a.length === b.length && a.every((x) => b.includes(x));
  const colorA = p.attributes.find((a) => a.id === ids.colorAttr);
  const sizeA = p.attributes.find((a) => a.id === ids.sizeAttr);
  if (!colorA || !sameSet(colorA.options ?? [], s.colors.map((c) => c.name))) out.push('colores distintos');
  if (!sizeA || !sameSet(sizeA.options ?? [], s.sizes)) out.push('tallas distintas');
  const photos = s.colors.reduce((n, c) => n + c.media.length, 0);
  if (p.images.length !== photos) out.push(`${p.images.length} fotos en la tienda (esperadas ${photos})`);

  const f360 = vars.filter((w) => isF360VariationOf(w, s.product.code));
  const skus = f360.map((w) => w.sku);
  const dup = skus.filter((x, i) => skus.indexOf(x) !== i);
  if (dup.length) out.push(`variaciones duplicadas: ${[...new Set(dup)].join(', ')}`);
  const active = activeVariants(s);
  for (const v of active) {
    const w = f360.find((x) => x.sku === v.sku);
    if (!w) { out.push(`falta ${v.sku}`); continue; }
    const c = colorOf(s, v);
    if (w.status !== 'publish') out.push(`${v.sku} deshabilitada`);
    if (Number(w.regular_price) !== Number(s.product.regular_price)) out.push(`${v.sku} precio ${w.regular_price}`);
    if (money(w.sale_price) !== money(s.product.sale_price)) out.push(`${v.sku} oferta ${w.sale_price || '—'}`);
    for (const pm of priceMeta(s)) if (money(metaValue(w.meta_data, pm.key) as string) !== pm.value) out.push(`${v.sku} ${pm.key} ${metaValue(w.meta_data, pm.key) ?? '—'} (esperado ${pm.value})`);
    const wc = w.attributes.find((a) => a.id === ids.colorAttr)?.option;
    const ws = w.attributes.find((a) => a.id === ids.sizeAttr)?.option;
    if (wc?.toLowerCase() !== c.name.toLowerCase() || ws !== v.size) out.push(`${v.sku} atributos ${wc}/${ws}`);
    if (w.manage_stock !== true) out.push(`${v.sku} sin control de stock`);
    const exp = expectedStock.get(v.id);
    if (exp != null && w.stock_quantity !== exp) out.push(`${v.sku} stock ${w.stock_quantity} (esperado ${exp})`);
    const img = primaryWooMedia(c);
    if (img && w.image?.id !== img) out.push(`${v.sku} foto distinta`);
  }
  const visible = f360.filter((w) => w.status !== 'private');
  if (visible.length !== active.length) out.push(`${visible.length} variaciones activas (esperadas ${active.length})`);
  return out;
}
