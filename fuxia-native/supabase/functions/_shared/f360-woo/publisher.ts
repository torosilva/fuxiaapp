// Fuxia 360 → WooCommerce publisher engine (runtime-agnostic).
// Steps: preflight → terms → product (+photos) → variations → stock → read-back verify. Every step is recorded.
// Idempotent: stored Woo id → SKU lookup (only on products carrying our F360 meta) → create. A retry after ANY failure
// converges to the same single product with the same variations; nothing is ever deleted in Woo.
import {
  activeVariants, buildImages, buildParent, buildVariation, COLOR_ATTR, isF360VariationOf, isManagedBy,
  mediaName, parentSku, SIZE_ATTR, stockManaged, stockToPush, verify,
} from './mapping.ts';
import type { BatchItemResult, PublishOutcome, Recorder, Snapshot, WooAdapter, WooProduct, WooVariation } from './types.ts';

const BATCH = 100;   // Woo batch endpoint limit
const errMsg = (e: unknown) => (e instanceof Error ? e.message : String(e));
const isErr = <T>(r: BatchItemResult<T>): r is { id?: number; error: { code: string; message: string } } =>
  !!r && typeof r === 'object' && 'error' in (r as object);
const slugish = (x: string) => x.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

class StepFailure extends Error {}

export type PublishOptions = { storageBase: string; allowProduction?: boolean };

export async function publish(s: Snapshot, woo: WooAdapter, rec: Recorder, opts: PublishOptions): Promise<PublishOutcome> {
  const summary: PublishOutcome['summary'] = { woo_product_id: s.product.woo_product_id, woo_status: null, variations: 0, created: 0, updated: 0, hidden: 0, stock_pushed: 0, mismatches: [] };
  let partial = false;

  const fail = async (step: Parameters<Recorder['step']>[0]['step'], message: string, ref?: string, detail?: unknown): Promise<never> => {
    await rec.step({ step, ref, action: 'error', ok: false, message, detail });
    throw new StepFailure(message);
  };
  const guarded = async <T>(step: Parameters<Recorder['step']>[0]['step'], ref: string | undefined, fn: () => Promise<T>): Promise<T> => {
    try { return await fn(); } catch (e) {
      if (e instanceof StepFailure) throw e;
      return fail(step, `Error de la tienda: ${errMsg(e)}`, ref);
    }
  };

  try {
    // ── 0 · Preflight: production only with its catalog switch on; category must exist by STABLE ID (never created, never by name) ──
    // production only with the channel's catalog switched ON (U1); its stock is never touched unless the channel syncs stock
    if (s.target.is_production && s.target.catalog_mode !== 'on' && !opts.allowProduction) await fail('preflight', 'Publicar en la tienda de producción no está habilitado.');
    const cat = s.product.woo_category;
    if (!cat) await fail('preflight', 'La categoría no está vinculada con esta tienda.');
    const wooCat = await guarded('preflight', `categoria:${s.product.category_key}`, () => woo.getCategory(cat!.id));
    if (!wooCat) await fail('preflight', `La categoría vinculada (id ${cat!.id}) no existe en la tienda.`, `categoria:${s.product.category_key}`);
    if (wooCat!.slug !== cat!.slug) await fail('preflight', `La categoría id ${cat!.id} ahora es “${wooCat!.slug}”, no “${cat!.slug}”. Revisa el vínculo.`, `categoria:${s.product.category_key}`);
    await rec.step({ step: 'preflight', ref: `categoria:${s.product.category_key}`, action: 'check', wooId: cat!.id, ok: true, message: `Categoría ${wooCat!.name}` });

    // ── 1 · Terms: reuse the store's global pa_color / pa_medida; create a missing term (never an attribute) ──
    const attrs = await guarded('terms', undefined, () => woo.listAttributes());
    const colorAttr = attrs.find((a) => a.slug === COLOR_ATTR);
    const sizeAttr = attrs.find((a) => a.slug === SIZE_ATTR);
    if (!colorAttr || !sizeAttr) await fail('terms', `La tienda no tiene los atributos globales ${COLOR_ATTR} y ${SIZE_ATTR}.`);
    const ids = { colorAttr: colorAttr!.id, sizeAttr: sizeAttr!.id };
    for (const [attr, names] of [[colorAttr!, s.colors.map((c) => c.name)], [sizeAttr!, s.sizes]] as const) {
      const terms = await guarded('terms', attr.slug, () => woo.listTerms(attr.id));
      for (const name of names) {
        const hit = terms.find((t) => t.name.toLowerCase() === name.toLowerCase() || t.slug === slugish(name));
        if (hit) { await rec.step({ step: 'terms', ref: `${attr.slug}:${name}`, action: 'reuse', wooId: hit.id, ok: true }); continue; }
        const t = await guarded('terms', `${attr.slug}:${name}`, () => woo.createTerm(attr.id, name));
        terms.push(t);
        await rec.step({ step: 'terms', ref: `${attr.slug}:${name}`, action: 'create', wooId: t.id, ok: true });
      }
    }

    // ── 2 · Product: find (link → SKU with our meta) or create as DRAFT; photos travel with it ──
    const sku = parentSku(s.product.code);
    let product: WooProduct | null = null;
    if (s.product.woo_product_id) {
      product = await guarded('product', sku, () => woo.getProduct(s.product.woo_product_id!));
      if (product && !isManagedBy(product, s.product.id)) await fail('product', `El producto ${product.id} de la tienda no pertenece a Fuxia 360.`, sku);
      if (!product) await rec.step({ step: 'product', ref: sku, action: 'check', wooId: s.product.woo_product_id, ok: true, message: 'El vínculo guardado ya no existe; se busca por SKU.' });
    }
    if (!product) {
      const bySku = await guarded('product', sku, () => woo.findProductBySku(sku));
      if (bySku) {
        if (!isManagedBy(bySku, s.product.id)) await fail('product', `El SKU ${sku} ya lo usa otro producto de la tienda que no es de Fuxia 360.`, sku, { woo_id: bySku.id });
        product = bySku;
        await rec.link('product', s.product.id, product.id, { status: product.status });
        await rec.step({ step: 'product', ref: sku, action: 'relink', wooId: product.id, ok: true, message: 'Recuperado por SKU (no se duplica).' });
      }
    }
    // Photos already in Woo but not yet linked (e.g. crash right after an upload): link by name, never re-upload.
    if (product) await linkExistingMedia(s, product, rec);

    const isCreate = !product;
    const body = buildParent(s, ids, buildImages(s, opts.storageBase), isCreate);
    const newPhotos = (body.images as { src?: string }[]).filter((i) => i.src).length;
    if (isCreate) {
      product = await guarded('product', sku, () => woo.createProduct(body));
      await rec.link('product', s.product.id, product!.id, { status: product!.status });
      await rec.step({ step: 'product', ref: sku, action: 'create', wooId: product!.id, ok: true, message: `Creado como ${product!.status}`, detail: { photos_uploaded: newPhotos } });
    } else {
      product = await guarded('product', sku, () => woo.updateProduct(product!.id, body));
      await rec.link('product', s.product.id, product!.id, { status: product!.status });
      await rec.step({ step: 'product', ref: sku, action: 'update', wooId: product!.id, ok: true, message: `Actualizado (${product!.status})`, detail: { photos_uploaded: newPhotos } });
    }
    summary.woo_product_id = product!.id;
    summary.woo_status = product!.status;
    const linked = await linkExistingMedia(s, product!, rec);
    const missing = s.colors.flatMap((c) => c.media).filter((m) => !m.woo_media_id);
    if (missing.length) await fail('media', `${missing.length} foto(s) no quedaron en la tienda.`, undefined, { missing: missing.map((m) => m.id) });
    await rec.step({ step: 'media', action: 'check', ok: true, message: `${linked} foto(s) nuevas vinculadas; ${s.colors.reduce((n, c) => n + c.media.length, 0)} en total` });
    const pid = product!.id;

    // ── 3 · Variations: one per color × size; match by link, then SKU; create the rest ──
    let existing = await guarded('variations', sku, () => woo.listVariations(pid));
    const creates: { v: (typeof s.variants)[number]; body: Record<string, unknown> }[] = [];
    const updates: { v: (typeof s.variants)[number]; body: Record<string, unknown> & { id: number } }[] = [];
    for (const v of activeVariants(s)) {
      const w = existing.find((x) => x.id === v.woo_variation_id) ?? existing.find((x) => x.sku === v.sku);
      if (w) {
        if (w.id !== v.woo_variation_id) {
          await rec.link('variant', v.id, w.id);
          await rec.step({ step: 'variations', ref: v.sku, action: 'relink', wooId: w.id, ok: true, message: 'Recuperada por SKU (no se duplica).' });
          v.woo_variation_id = w.id;
        }
        updates.push({ v, body: { id: w.id, ...buildVariation(s, v, ids, false) } });
      } else creates.push({ v, body: buildVariation(s, v, ids, true) });
    }
    // Sizes/colors no longer active in Fuxia (or stray F360 SKUs) are hidden (private), never deleted: orders reference them.
    const activeSkus = new Set(activeVariants(s).map((v) => v.sku));
    const hides = existing.filter((w) => isF360VariationOf(w, s.product.code) && !activeSkus.has(w.sku) && w.status !== 'private');

    for (let i = 0; i < creates.length; i += BATCH) {
      const chunk = creates.slice(i, i + BATCH);
      const r = await guarded('variations', sku, () => woo.batchVariations(pid, { create: chunk.map((c) => c.body) }, 'variations'));
      for (const [k, item] of (r.create ?? []).entries()) {
        const v = chunk[k].v;
        if (isErr(item)) { partial = true; await rec.step({ step: 'variations', ref: v.sku, action: 'error', ok: false, message: item.error.message }); continue; }
        const w = item as WooVariation;
        await rec.link('variant', v.id, w.id, { stock: w.stock_quantity ?? 0 });
        v.woo_variation_id = w.id; v.last_pushed_stock = w.stock_quantity ?? 0;
        summary.created++;
        await rec.step({ step: 'variations', ref: v.sku, action: 'create', wooId: w.id, ok: true });
      }
    }
    for (let i = 0; i < updates.length; i += BATCH) {
      const chunk = updates.slice(i, i + BATCH);
      const r = await guarded('variations', sku, () => woo.batchVariations(pid, { update: chunk.map((c) => c.body) }, 'variations'));
      for (const [k, item] of (r.update ?? []).entries()) {
        const v = chunk[k].v;
        if (isErr(item)) { partial = true; await rec.step({ step: 'variations', ref: v.sku, action: 'error', ok: false, message: item.error.message }); continue; }
        summary.updated++;
        await rec.step({ step: 'variations', ref: v.sku, action: 'update', wooId: (item as WooVariation).id, ok: true });
      }
    }
    if (hides.length) {
      const r = await guarded('variations', sku, () => woo.batchVariations(pid, { update: hides.map((w) => ({ id: w.id, status: 'private' })) }, 'hide'));
      for (const [k, item] of (r.update ?? []).entries()) {
        const ok = !isErr(item);
        if (!ok) partial = true; else summary.hidden++;
        await rec.step({ step: 'variations', ref: hides[k].sku, action: 'hide', wooId: hides[k].id, ok, message: ok ? 'Oculta (ya no está activa en Fuxia 360)' : (item as { error: { message: string } }).error.message });
      }
    }

    // ── 4 · Stock: Woo = sellable stock in the fulfillment location (P-STOCK) — only when this channel syncs stock ──
    existing = await guarded('stock', sku, () => woo.listVariations(pid));
    const expected = new Map<string, number>();
    const pushes: { v: (typeof s.variants)[number]; qty: number; id: number }[] = [];
    if (!stockManaged(s)) await rec.step({ step: 'stock', ref: sku, action: 'skip', ok: true, message: 'Stock de la tienda sin cambios: este canal no sincroniza existencias.' });
    for (const v of stockManaged(s) ? activeVariants(s) : []) {
      const w = existing.find((x) => x.id === v.woo_variation_id);
      if (!w) continue;   // creation failed above → verification reports it
      const qty = stockToPush(v.ats, v.last_pushed_stock, w.stock_quantity);
      expected.set(v.id, qty);
      if (w.manage_stock === true && w.stock_quantity === qty && v.last_pushed_stock === qty) {
        await rec.step({ step: 'stock', ref: v.sku, action: 'skip', wooId: w.id, ok: true, message: `${qty} (sin cambio)` });
      } else pushes.push({ v, qty, id: w.id });
    }
    for (let i = 0; i < pushes.length; i += BATCH) {
      const chunk = pushes.slice(i, i + BATCH);
      const r = await guarded('stock', sku, () => woo.batchVariations(pid, { update: chunk.map((p) => ({ id: p.id, manage_stock: true, stock_quantity: p.qty, backorders: 'no' })) }, 'stock'));
      for (const [k, item] of (r.update ?? []).entries()) {
        const p = chunk[k];
        if (isErr(item)) { partial = true; await rec.step({ step: 'stock', ref: p.v.sku, action: 'error', ok: false, message: item.error.message }); continue; }
        await rec.link('variant', p.v.id, p.id, { stock: p.qty });
        p.v.last_pushed_stock = p.qty;
        summary.stock_pushed++;
        await rec.step({ step: 'stock', ref: p.v.sku, action: 'update', wooId: p.id, ok: true, message: `${p.qty} (Bodega: ${p.v.ats})` });
      }
    }

    // ── 5 · Read-back verification: "Publicado" only if the store matches exactly ──
    const after = await guarded('verify', sku, () => woo.getProduct(pid));
    const afterVars = await guarded('verify', sku, () => woo.listVariations(pid));
    summary.variations = afterVars.filter((w) => isF360VariationOf(w, s.product.code) && w.status !== 'private').length;
    summary.woo_status = after?.status ?? summary.woo_status;
    summary.mismatches = verify(s, after, afterVars, ids, expected);
    await rec.step({ step: 'verify', ref: sku, action: 'check', wooId: pid, ok: summary.mismatches.length === 0,
      message: summary.mismatches.length ? summary.mismatches.slice(0, 5).join('; ') : `1 producto (${after?.status}), ${summary.variations} variaciones, todo coincide`,
      detail: { mismatches: summary.mismatches } });
    if (summary.mismatches.length || partial) {
      return { status: 'partial', error: summary.mismatches[0] ? `La tienda no quedó igual: ${summary.mismatches[0]}` : 'Algunas variaciones no se guardaron.', summary };
    }
    return { status: 'succeeded', error: null, summary };
  } catch (e) {
    const message = e instanceof StepFailure ? e.message : `Error inesperado: ${errMsg(e)}`;
    if (!(e instanceof StepFailure)) { try { await rec.step({ step: 'verify', action: 'error', ok: false, message }); } catch { /* keep original error */ } }
    return { status: 'failed', error: message, summary };
  }
}

/** Links Woo gallery images named f360-{mediaId} to F360 photos not yet linked. Returns how many were linked. */
async function linkExistingMedia(s: Snapshot, p: WooProduct, rec: Recorder) {
  let n = 0;
  for (const c of s.colors) for (const m of c.media) {
    if (m.woo_media_id) continue;
    const img = p.images.find((i) => i.name === mediaName(m.id));
    if (!img) continue;
    await rec.link('media', m.id, img.id);
    await rec.step({ step: 'media', ref: `${c.code}:${m.id.slice(0, 8)}`, action: 'link', wooId: img.id, ok: true });
    m.woo_media_id = img.id;
    n++;
  }
  return n;
}

