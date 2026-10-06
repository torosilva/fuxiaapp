'use server';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { publisherAvailable } from '@/lib/env-guard';
import { suggestHex } from '@/lib/format';
import type { InventoryEvent, Product, Transfer } from '@/lib/f360';

type Result<T> = { ok: true; data: T } | { ok: false; error: string };

async function call<T>(fn: string, args: Record<string, unknown>): Promise<Result<T>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: error.code === '42501' ? 'Tu cuenta no tiene permiso para esta acción.' : error.message };
  return { ok: true, data: data as T };
}

export async function getProductAction(id: string): Promise<Result<Product>> {
  return call<Product>('f360_get_product', { p_product_id: id });
}

export async function createProductAction(input: {
  name: string; category?: string; imagePath?: string | null; sizes: string[]; colors: { name: string; hex?: string | null }[];
}): Promise<Result<Product>> {
  const name = input.name?.trim();
  if (!name) return { ok: false, error: 'Escribe el nombre del producto.' };
  if (!input.colors?.length) return { ok: false, error: 'Agrega al menos un color.' };
  if (!input.sizes?.length) return { ok: false, error: 'Elige al menos una talla.' };
  const r = await call<Product>('f360_create_product', {
    p_name: name, p_sizes: input.sizes, p_colors: input.colors.map((c) => ({ name: c.name.trim(), hex: c.hex ?? null })),
    p_category: input.category?.trim() || null, p_image_path: input.imagePath ?? null,
  });
  if (r.ok) { revalidatePath('/productos'); revalidatePath('/'); }
  return r;
}

export async function receiveInventoryAction(input: {
  idempotencyKey: string; locationId: string; lines: { variantId: string; quantity: number }[]; note?: string;
}): Promise<Result<InventoryEvent>> {
  const lines = input.lines.filter((l) => Number.isInteger(l.quantity) && l.quantity > 0);
  if (!lines.length) return { ok: false, error: 'Escribe al menos un par para recibir.' };
  if (!input.locationId) return { ok: false, error: 'Elige dónde llegó la mercancía.' };
  const r = await call<InventoryEvent>('f360_receive_inventory', {
    p_idempotency_key: input.idempotencyKey, p_location_id: input.locationId,
    p_lines: lines.map((l) => ({ variant_id: l.variantId, quantity: l.quantity })), p_note: input.note?.trim() || null,
  });
  if (r.ok) { revalidatePath('/'); revalidatePath('/productos', 'layout'); revalidatePath('/inventario', 'layout'); }
  return r;
}

// ── P2.1 product master ─────────────────────────────────────────────────────
function revalidateProduct(id: string) { revalidatePath(`/productos/${id}`); revalidatePath('/productos'); revalidatePath('/'); }

export async function updateProductAction(productId: string, fields: {
  name?: string; description?: string | null; short_description?: string | null; category_key?: string | null;
  regular_price?: number | null; sale_price?: number | null;
}): Promise<Result<Product>> {
  const r = await call<Product>('f360_update_product', { p_product_id: productId, p_fields: fields });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function addColorAction(productId: string, name: string, hex: string | null): Promise<Result<Product>> {
  if (!name.trim()) return { ok: false, error: 'Escribe el nombre del color.' };
  const r = await call<Product>('f360_add_color', { p_product_id: productId, p_name: name.trim(), p_hex: hex });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function addMediaAction(productId: string, colorId: string, paths: string[]): Promise<Result<Product>> {
  const r = await call<Product>('f360_add_media', { p_product_id: productId, p_color_id: colorId, p_paths: paths });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function removeMediaAction(productId: string, mediaId: string): Promise<Result<Product>> {
  const r = await call<Product>('f360_remove_media', { p_media_id: mediaId });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function setPrimaryMediaAction(productId: string, mediaId: string): Promise<Result<Product>> {
  const r = await call<Product>('f360_set_primary_media', { p_media_id: mediaId });
  if (r.ok) revalidateProduct(productId);
  return r;
}

// P2.2 · Publish/sync to the online store (owner only; checked in the database AND again by the publisher).
// The publisher runs server-side with the store credentials; the browser never sees them.
const STAGING_STORE = 'woo_staging4';   // the only store merges are approved for

export async function publishAction(productId: string, idempotencyKey: string): Promise<Result<{ status: string; error: string | null }>> {
  // Checked BEFORE creating a job: without a publisher a job would sit in the queue forever.
  if (!publisherAvailable()) return { ok: false, error: 'La publicación en WooCommerce todavía no está disponible en este ambiente.' };
  const url = process.env.F360_PUBLISHER_URL!;
  const supabase = await createClient();
  const req = await call<{ id: string; status: string }>('f360_request_publish', { p_product_id: productId, p_idempotency_key: idempotencyKey });
  if (!req.ok) return req;
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  let out: Result<{ status: string; error: string | null }>;
  try {
    const res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ job_id: req.data.id }), cache: 'no-store', signal: AbortSignal.timeout(280_000) });
    const body = await res.json().catch(() => ({}));
    out = res.ok ? { ok: true, data: { status: body.outcome?.status ?? 'failed', error: body.outcome?.error ?? null } }
      : { ok: false, error: body.error ?? 'No se pudo publicar.' };
  } catch {
    out = { ok: false, error: 'No hubo respuesta del publicador. Puedes reintentar: no se duplicará nada.' };
  }
  revalidatePath(`/productos/${productId}`);
  return out;
}

// One store product per model (Mario 2026-10-03): merge models sold as one store product per colour. Owner only;
// the database refuses production targets. start → publish each job (the normal publisher) → finish.
export type ConsolidationItem = { product_id: string; name: string; job_id: string | null; status: string };
export async function consolidateStartAction(productIds?: string[]) {
  return call<{ items: ConsolidationItem[]; skipped: { product_id: string; name: string; missing: string[] }[] }>('f360_consolidate_start',
    { p_target_key: STAGING_STORE, p_product_ids: productIds ?? null, p_legacy_paths: {} });
}
export async function runPublishJobAction(jobId: string, productId: string): Promise<Result<{ status: string; error: string | null }>> {
  if (!publisherAvailable()) return { ok: false, error: 'La publicación en WooCommerce todavía no está disponible en este ambiente.' };
  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  try {
    const res = await fetch(process.env.F360_PUBLISHER_URL!, { method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ job_id: jobId }), cache: 'no-store', signal: AbortSignal.timeout(280_000) });
    const body = await res.json().catch(() => ({}));
    revalidatePath(`/productos/${productId}`);
    return res.ok ? { ok: true, data: { status: body.outcome?.status ?? 'failed', error: body.outcome?.error ?? null } } : { ok: false, error: body.error ?? 'No se pudo publicar.' };
  } catch {
    return { ok: false, error: 'No hubo respuesta del publicador. Puedes reintentar: no se duplicará nada.' };
  }
}
export async function consolidateFinishAction(productId: string) {
  const r = await call<{ status: string; new_path: string }>('f360_consolidate_finish', { p_target_key: STAGING_STORE, p_product_id: productId });
  if (r.ok) { revalidatePath('/productos'); revalidatePath(`/productos/${productId}`); }
  return r;
}
export type Consolidation = { product_id: string; name: string; status: string; job_status: string | null; job_error: string | null; new_woo_product_id: number | null;
  new_path: string; legacy_products: { woo_product_id: number; name: string }[]; requested_at: string; finished_at: string | null };
/** Redirect list: old per-colour product URL → new single product URL (read from the store, owner only). */
export async function consolidationRedirectsAction() {
  const list = await call<Consolidation[]>('f360_consolidations', { p_target_key: STAGING_STORE });
  if (!list.ok) return list;
  const ids = list.data.flatMap((c) => [...c.legacy_products.map((l) => l.woo_product_id), ...(c.new_woo_product_id ? [c.new_woo_product_id] : [])]);
  const links = await contentCall<{ items: Record<string, { permalink: string | null; status: string | null }> }>({ action: 'permalinks', ids });
  if (!links.ok) return links;
  const path = (u: string | null | undefined) => { try { return u ? new URL(u).pathname : null; } catch { return null; } };
  const rows = list.data.filter((c) => c.status === 'publicada').flatMap((c) => c.legacy_products.map((l) => ({
    model: c.name, from: path(links.data.items[l.woo_product_id]?.permalink), to: path(links.data.items[c.new_woo_product_id ?? 0]?.permalink) ?? c.new_path })));
  return { ok: true as const, data: { list: list.data, rows } };
}

// P2.3A · Avisos de sincronización
export async function resolveSyncIssueAction(id: string, note: string): Promise<Result<{ ok: boolean }>> {
  const r = await call<{ ok: boolean }>('f360_resolve_sync_issue', { p_id: id, p_note: note });
  if (r.ok) revalidatePath('/avisos');
  return r;
}

/** "Revisar ahora": compares Fuxia 360 (Bodega CDMX) with the online store and corrects differences. Owner/operator. */
export async function reconcileNowAction(): Promise<Result<{ checked: number; in_sync: number; drifted: number; missing: number }>> {
  if (!publisherAvailable()) return { ok: false, error: 'La conexión con WooCommerce todavía no está disponible en este ambiente.' };
  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  // Relative: …/functions/v1/f360-woo-publish → …/functions/v1/f360-woo-sync (and 127.0.0.1:8787/f360-woo-sync locally).
  const url = new URL('f360-woo-sync', process.env.F360_PUBLISHER_URL!).toString();
  try {
    const res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'reconcile' }), cache: 'no-store', signal: AbortSignal.timeout(120_000) });
    const body = await res.json().catch(() => ({}));
    revalidatePath('/avisos');
    return res.ok ? { ok: true, data: body.reconcile } : { ok: false, error: body.error ?? 'No se pudo revisar.' };
  } catch {
    return { ok: false, error: 'La tienda no respondió. Intenta de nuevo en un momento.' };
  }
}

/** Fuxia 360 content (photos, description, price, colour name) → the current store's products. Owner only; the
 *  database refuses production targets. One store product per call so the page can show progress. */
async function contentCall<T>(body: Record<string, unknown>): Promise<Result<T>> {
  if (!publisherAvailable()) return { ok: false, error: 'La conexión con WooCommerce todavía no está disponible en este ambiente.' };
  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  const url = new URL('f360-woo-sync', process.env.F360_PUBLISHER_URL!).toString();
  try {
    const res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body), cache: 'no-store', signal: AbortSignal.timeout(140_000) });
    const out = await res.json().catch(() => ({}));
    return res.ok ? { ok: true, data: out as T } : { ok: false, error: out.error ?? 'No se pudo.' };
  } catch {
    return { ok: false, error: 'La tienda tardó demasiado en responder.' };
  }
}
export type StoreContentItem = { woo_product_id: number; product_id: string; name: string; last_push: string | null };
export async function storeContentListAction(productIds?: string[]) {
  const r = await contentCall<{ items: StoreContentItem[] }>({ action: 'content_list', product_ids: productIds ?? null });
  return r.ok ? { ok: true as const, data: r.data.items } : r;
}
export async function storeContentPushAction(wooProductId: number) {
  return contentCall<{ ok: boolean; name: string; photos: number; message: string }>({ action: 'content', woo_product_id: wooProductId });
}

// B4 · Plan (owner only; validated again in the database)
export async function saveGrowthPlanAction(year: number, northStar: number, note: string): Promise<Result<unknown>> {
  const r = await call('f360_save_growth_plan', { p_year: year, p_north_star: northStar, p_note: note || null });
  if (r.ok) revalidatePath('/growth');
  return r;
}
export async function saveScenarioAction(year: number, kind: string, inputs: Record<string, unknown>): Promise<Result<unknown>> {
  const r = await call('f360_save_growth_scenario', { p_year: year, p_kind: kind, p_inputs: inputs });
  if (r.ok) revalidatePath('/growth');
  return r;
}
export async function addReportedFigureAction(input: { period: string; value: number; scope: string; source: string; note: string }): Promise<Result<unknown>> {
  const r = await call('f360_add_reported_figure', { p_period: input.period, p_value: input.value, p_scope: input.scope, p_source: input.source, p_note: input.note || null });
  if (r.ok) revalidatePath('/growth');
  return r;
}
export async function setReportedFigureStatusAction(id: string, status: string, note: string): Promise<Result<unknown>> {
  const r = await call('f360_set_reported_figure_status', { p_id: id, p_status: status, p_note: note });
  if (r.ok) revalidatePath('/growth');
  return r;
}

// Track C · Transfers. The database decides who may do what (role + live location assignment); the client never sends a
// role, a location for the actor, or a price. Every call carries a key: a double click can never move stock twice.
function revalidateTransfers(id?: string) {
  revalidatePath('/transferencias'); if (id) revalidatePath(`/transferencias/${id}`);
  revalidatePath('/'); revalidatePath('/inventario', 'layout'); revalidatePath('/productos', 'layout');
}
type QtyLine = { variantId: string; quantity: number };
const qtyLines = (lines: QtyLine[], allowZero = false) =>
  lines.filter((l) => Number.isInteger(l.quantity) && (allowZero ? l.quantity >= 0 : l.quantity > 0)).map((l) => ({ variant_id: l.variantId, quantity: l.quantity }));

export async function requestTransferAction(input: { idempotencyKey: string; fromId: string; toId: string; lines: QtyLine[]; note?: string; sendNow: boolean }): Promise<Result<Transfer>> {
  const lines = qtyLines(input.lines);
  if (!input.fromId || !input.toId) return { ok: false, error: 'Elige origen y destino.' };
  if (!lines.length) return { ok: false, error: 'Agrega al menos un par.' };
  const r = await call<Transfer>('f360_request_transfer', { p_idempotency_key: input.idempotencyKey, p_from_location_id: input.fromId, p_to_location_id: input.toId,
    p_lines: lines, p_note: input.note?.trim() || null, p_send_now: input.sendNow });
  if (r.ok) revalidateTransfers(r.data.id);
  return r;
}
export async function sendTransferAction(id: string, idempotencyKey: string, lines: QtyLine[]): Promise<Result<Transfer>> {
  const r = await call<Transfer>('f360_send_transfer', { p_idempotency_key: idempotencyKey, p_transfer_id: id, p_lines: qtyLines(lines, true) });
  if (r.ok) revalidateTransfers(id);
  return r;
}
export async function receiveTransferAction(id: string, idempotencyKey: string, lines: QtyLine[]): Promise<Result<Transfer>> {
  const r = await call<Transfer>('f360_receive_transfer', { p_idempotency_key: idempotencyKey, p_transfer_id: id, p_lines: qtyLines(lines, true) });
  if (r.ok) revalidateTransfers(id);
  return r;
}
export async function resolveTransferAction(id: string, idempotencyKey: string, lines: { variantId: string; quantity: number; action: 'return' | 'write_off' }[], reason: string): Promise<Result<Transfer>> {
  const clean = lines.filter((l) => Number.isInteger(l.quantity) && l.quantity > 0).map((l) => ({ variant_id: l.variantId, quantity: l.quantity, action: l.action }));
  if (!clean.length) return { ok: false, error: 'Indica qué pasó con los pares faltantes.' };
  if (reason.trim().length < 3) return { ok: false, error: 'Escribe el motivo.' };
  const r = await call<Transfer>('f360_resolve_transfer_difference', { p_idempotency_key: idempotencyKey, p_transfer_id: id, p_lines: clean, p_reason: reason.trim() });
  if (r.ok) revalidateTransfers(id);
  return r;
}
export async function cancelTransferAction(id: string, idempotencyKey: string, reason: string): Promise<Result<Transfer>> {
  const r = await call<Transfer>('f360_cancel_transfer', { p_idempotency_key: idempotencyKey, p_transfer_id: id, p_reason: reason.trim() || null });
  if (r.ok) revalidateTransfers(id);
  return r;
}

// Prices per currency (operator+; validated again in the database) and currencies (owner)
export async function setProductPriceAction(productId: string, currency: string, amount: number | null): Promise<Result<unknown>> {
  if (amount != null && !(amount > 0)) return { ok: false, error: 'El precio debe ser mayor a cero.' };
  const r = await call('f360_set_product_price', { p_product_id: productId, p_currency: currency, p_amount: amount });
  if (r.ok) revalidateProduct(productId);
  return r;
}
export async function saveCurrencyAction(input: { code: string; name: string; symbol: string; decimals: number; wooMetaKey: string; active: boolean }): Promise<Result<unknown>> {
  const r = await call('f360_save_currency', { p_code: input.code, p_name: input.name, p_symbol: input.symbol, p_decimals: input.decimals,
    p_woo_meta_key: input.wooMetaKey, p_active: input.active });
  if (r.ok) revalidatePath('/monedas');
  return r;
}

// Track D · D2 — homologation (operator+; every rule is enforced again in the database)
export async function confirmHomologationAction(input: {
  target: string; variationIds: number[]; productId: string | null; newModelName: string | null; categoryKey: string | null; color: string; note?: string;
}): Promise<Result<{ product_id: string; confirmed: number }>> {
  if (!input.variationIds.length) return { ok: false, error: 'Elige al menos una variación.' };
  if (!input.color.trim()) return { ok: false, error: 'Escribe el color F360.' };
  if (!input.productId && !input.newModelName?.trim()) return { ok: false, error: 'Escribe el nombre del modelo o elige uno existente.' };
  const r = await call<{ product_id: string; confirmed: number }>('f360_legacy_confirm', {
    p_target_key: input.target, p_variation_ids: input.variationIds, p_product_id: input.productId,
    p_new_model_name: input.productId ? null : input.newModelName?.trim(), p_category_key: input.categoryKey || null,
    p_color_name: input.color.trim(), p_note: input.note?.trim() || null,
  });
  if (r.ok) { revalidatePath('/homologacion'); revalidatePath('/productos'); }
  return r;
}
export async function markHomologationAction(target: string, variationIds: number[], status: 'requiere_revision' | 'sin_correspondencia', note: string): Promise<Result<unknown>> {
  if (note.trim().length < 3) return { ok: false, error: 'Escribe el motivo.' };
  const r = await call('f360_legacy_mark', { p_target_key: target, p_variation_ids: variationIds, p_status: status, p_note: note.trim() });
  if (r.ok) revalidatePath('/homologacion');
  return r;
}
export async function reopenHomologationAction(target: string, variationIds: number[], reason: string): Promise<Result<unknown>> {
  if (reason.trim().length < 3) return { ok: false, error: 'Escribe por qué se reabre.' };
  const r = await call('f360_legacy_reopen', { p_target_key: target, p_variation_ids: variationIds, p_reason: reason.trim() });
  if (r.ok) revalidatePath('/homologacion');
  return r;
}

// Track D · D2 — bring the store's existing photos, price and description into a model adopted from the legacy catalog.
// Reads the store's PUBLIC catalog only (Store API, GET, no credentials). Fills only what is still EMPTY in Fuxia 360
// (never overwrites what a person wrote), through the same RPCs a person uses. Nothing is written to Woo.
type WooStoreProduct = { id: number; name: string; description: string; prices: { regular_price: string; sale_price: string; currency_minor_unit: number }; on_sale: boolean; images: { src: string }[] };
const STORE_HOSTS = /(^|\.)fuxiaballerinas\.com$/;
function plainText(html: string) {
  return html.replace(/<\s*br\s*\/?>/gi, '\n').replace(/<\/p>/gi, '\n\n').replace(/<[^>]+>/g, '')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n))).replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&quot;/g, '"')
    .replace(/&#039;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/\n{3,}/g, '\n\n').trim();
}
async function storeProduct(baseUrl: string, id: number): Promise<WooStoreProduct | null> {
  const u = new URL(`/wp-json/wc/store/v1/products/${id}`, baseUrl);
  if (u.protocol !== 'https:' || !STORE_HOSTS.test(u.hostname)) return null;
  const r = await fetch(u, { method: 'GET', headers: { Accept: 'application/json' }, cache: 'no-store' });
  return r.ok ? ((await r.json()) as WooStoreProduct) : null;
}

export async function importFromStoreAction(productId: string, maxColors = 3): Promise<Result<{ photos: number; price: boolean; description: boolean; skipped: string[]; remaining: number }>> {
  const supabase = await createClient();
  const src = await supabase.rpc('f360_legacy_sources', { p_product_id: productId });
  if (src.error) return { ok: false, error: src.error.message };
  const sources = (src.data ?? []) as { color_id: string; color: string; woo_product_id: number; base_url: string }[];
  if (!sources.length) return { ok: false, error: 'Este modelo no viene de la tienda actual.' };
  const pr = await supabase.rpc('f360_get_product', { p_product_id: productId });
  if (pr.error) return { ok: false, error: pr.error.message };
  const product = pr.data as Product;
  const skipped: string[] = [];
  const woo = new Map<number, WooStoreProduct | null>();
  for (const s of sources) if (!woo.has(s.woo_product_id)) woo.set(s.woo_product_id, await storeProduct(s.base_url, s.woo_product_id));
  if ([...woo.values()].every((w) => !w)) return { ok: false, error: 'No se pudo leer la tienda (o es el canal de práctica).' };

  // price + description: only when still empty, and only if every colour has the same price in the store
  const fields: Record<string, unknown> = {};
  const read = [...woo.values()].filter(Boolean) as WooStoreProduct[];
  const money = (w: WooStoreProduct, v: string) => Number(v) / 10 ** (w.prices.currency_minor_unit ?? 0);
  const regular = [...new Set(read.map((w) => money(w, w.prices.regular_price)))];
  if (product.regular_price == null) {
    if (regular.length === 1 && regular[0] > 0) {
      fields.regular_price = regular[0];
      const sale = [...new Set(read.map((w) => (w.on_sale ? money(w, w.prices.sale_price) : null)))];
      if (sale.length === 1 && sale[0] != null && sale[0] < regular[0]) fields.sale_price = sale[0];
    } else skipped.push(`precio: los colores tienen precios distintos en la tienda (${regular.join(' / ')})`);
  }
  if (!product.description) {
    const d = read.map((w) => plainText(w.description || '')).find((t) => t.length > 0);
    if (d) fields.description = d;
  }
  if (Object.keys(fields).length) {
    const u = await supabase.rpc('f360_update_product', { p_product_id: productId, p_fields: fields });
    if (u.error) skipped.push(`precio/descripción: ${u.error.message}`);
  }

  // swatches: colours without one get the palette colour that matches their name (display only, editable by hand)
  for (const s of sources) {
    const c = product.colors.find((k) => k.id === s.color_id);
    const hex = c && !c.hex ? suggestHex(c.name) : null;
    if (c && hex) { const h = await supabase.rpc('f360_set_color_hex', { p_color_id: c.id, p_hex: hex }); if (!h.error) c.hex = hex; }
  }

  // photos: per colour, only for colours that have none yet (max 6 per colour), a few colours per call
  let photos = 0;
  const pending = sources.filter((x) => { const c = product.colors.find((k) => k.id === x.color_id); return c && !c.media.length && woo.get(x.woo_product_id); });
  for (const s of pending.slice(0, maxColors)) {
    const color = product.colors.find((c) => c.id === s.color_id)!;
    const w = woo.get(s.woo_product_id)!;
    const paths: string[] = [];
    for (const img of w.images.slice(0, 6)) {
      try {
        const u = new URL(img.src);
        if (u.protocol !== 'https:' || !STORE_HOSTS.test(u.hostname)) continue;
        const r = await fetch(u, { cache: 'no-store' });
        if (!r.ok) continue;
        const type = r.headers.get('content-type') ?? 'image/jpeg';
        if (!type.startsWith('image/')) continue;
        const ext = (u.pathname.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
        const path = `f360/${product.code}/${color.code}/${crypto.randomUUID()}.${ext}`;
        const up = await supabase.storage.from('product-images').upload(path, await r.arrayBuffer(), { contentType: type });
        if (!up.error) paths.push(path);
      } catch { /* one image failing does not stop the rest */ }
    }
    if (paths.length) {
      const m = await supabase.rpc('f360_add_media', { p_product_id: productId, p_color_id: color.id, p_paths: paths });
      if (m.error) skipped.push(`${color.name}: ${m.error.message}`); else photos += paths.length;
    } else skipped.push(`${color.name}: la tienda no tiene fotos que se puedan traer`);
  }
  revalidateProduct(productId);
  return { ok: true, data: { photos, price: 'regular_price' in fields, description: 'description' in fields, skipped, remaining: Math.max(0, pending.length - maxColors) } };
}

export async function setMadeToOrderStatusAction(id: string, status: 'pendiente' | 'en_proceso' | 'enviado' | 'cancelado'): Promise<Result<unknown>> {
  const r = await call('f360_made_to_order_set', { p_id: id, p_status: status, p_note: null });
  if (r.ok) revalidatePath('/sobre-pedido');
  return r;
}
export async function setCustomRequestStatusAction(id: string, status: 'nueva' | 'contactada' | 'cotizada' | 'cerrada' | 'descartada'): Promise<Result<unknown>> {
  const r = await call('f360_custom_request_set', { p_id: id, p_status: status });
  if (r.ok) revalidatePath('/a-la-medida');
  return r;
}
export async function markStoreShipmentSentAction(id: string): Promise<Result<unknown>> {
  const r = await call('f360_online_store_shipment_sent', { p_id: id });
  if (r.ok) revalidatePath('/sobre-pedido');
  return r;
}
/** "Nuevas" in the store: true = always new, false = never, null = automatic (45 days, not from the old catalog). */
export async function setProductNewAction(productId: string, value: boolean | null): Promise<Result<unknown>> {
  const r = await call('f360_set_product_new', { p_product_id: productId, p_value: value });
  if (r.ok) revalidateProduct(productId);
  return r;
}
export async function setCaseStatusAction(id: string, status: 'nueva' | 'en_atencion' | 'resuelta' | 'descartada'): Promise<Result<unknown>> {
  const r = await call('f360_case_set', { p_id: id, p_status: status });
  if (r.ok) revalidatePath('/bandeja');
  return r;
}
/** Sobre pedido on/off for a model (operator+; validated again in the database). */
export async function setMakeToOrderAction(productId: string, on: boolean, reason: string): Promise<Result<unknown>> {
  const r = await call('f360_set_make_to_order', { p_product_id: productId, p_on: on, p_reason: reason || null });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function setColorHexAction(productId: string, colorId: string, hex: string | null): Promise<Result<Product>> {
  if (hex && !/^#[0-9a-fA-F]{6}$/.test(hex)) return { ok: false, error: 'Color no válido.' };
  const r = await call<Product>('f360_set_color_hex', { p_color_id: colorId, p_hex: hex });
  if (r.ok) revalidateProduct(productId);
  return r;
}

export async function setProductArchivedAction(productId: string, archived: boolean, reason: string): Promise<Result<unknown>> {
  if (reason.trim().length < 3) return { ok: false, error: 'Escribe el motivo.' };
  const r = await call('f360_set_product_archived', { p_product_id: productId, p_archived: archived, p_reason: reason.trim() });
  if (r.ok) { revalidateProduct(productId); revalidatePath('/homologacion'); }
  return r;
}

// Inventory adjustment by hand (owner only; reason mandatory; never negative — all enforced again in the database)
export async function adjustInventoryAction(input: { idempotencyKey: string; productId: string; locationId: string; lines: { variantId: string; delta: number }[]; reason: string }): Promise<Result<InventoryEvent>> {
  const lines = input.lines.filter((l) => Number.isInteger(l.delta) && l.delta !== 0);
  if (!lines.length) return { ok: false, error: 'Escribe al menos un par para ajustar.' };
  if (input.reason.trim().length < 3) return { ok: false, error: 'Escribe el motivo del ajuste.' };
  const r = await call<InventoryEvent>('f360_adjust_inventory', { p_idempotency_key: input.idempotencyKey, p_location_id: input.locationId,
    p_lines: lines.map((l) => ({ variant_id: l.variantId, delta: l.delta })), p_reason: input.reason.trim() });
  if (r.ok) { revalidateProduct(input.productId); revalidatePath('/inventario', 'layout'); }
  return r;
}

// Track D · D3 — opening physical count (every rule is enforced again in the database; nothing here writes inventory)
function revalidateCount() { revalidatePath('/conteo', 'layout'); }
export async function openingStartAction(target: string, note: string): Promise<Result<unknown>> {
  // Mario 2026-10-05 (b): every new count is ONE count, approved by an owner.
  const r = await call<{ count: { id: string } }>('f360_opening_start', { p_target_key: target, p_note: note.trim() || null });
  if (r.ok) { const s = await call('f360_opening_set_simple', { p_count_id: r.data.count.id }); revalidateCount(); if (!s.ok) return s; }
  return r;
}
export async function openingSetSimpleAction(id: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_set_simple', { p_count_id: id }); if (r.ok) revalidateCount(); return r;
}
export async function openingRefreshAction(id: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_refresh_scope', { p_count_id: id }); if (r.ok) revalidateCount(); return r;
}
export async function openingRecordAction(id: string, round: '1' | '2' | 're', lines: { variantId: string; qty: number }[]): Promise<Result<unknown>> {
  const clean = lines.filter((l) => Number.isInteger(l.qty) && l.qty >= 0).map((l) => ({ variant_id: l.variantId, qty: l.qty }));
  if (!clean.length) return { ok: false, error: 'Escribe al menos una cantidad.' };
  const r = await call('f360_opening_record', { p_count_id: id, p_round: round, p_lines: clean }); if (r.ok) revalidateCount(); return r;
}
export async function openingAddUnlistedAction(id: string, description: string, size: string, quantity: number): Promise<Result<unknown>> {
  const r = await call('f360_opening_add_unlisted', { p_count_id: id, p_description: description, p_size: size || null, p_quantity: quantity }); if (r.ok) revalidateCount(); return r;
}
export async function openingResolveUnlistedAction(unlistedId: string, resolution: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_resolve_unlisted', { p_unlisted_id: unlistedId, p_resolution: resolution }); if (r.ok) revalidateCount(); return r;
}
// Carolina 2026-10-05: undo mistakes while counting (open count only; logged; never inventory)
export async function openingClearLineAction(id: string, variantId: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_clear_line', { p_count_id: id, p_variant_id: variantId }); if (r.ok) revalidateCount(); return r;
}
export async function openingRemoveUnlistedAction(unlistedId: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_remove_unlisted', { p_unlisted_id: unlistedId }); if (r.ok) revalidateCount(); return r;
}
export async function openingUnlistedOpenAction(id: string): Promise<Result<{ id: string; description: string; size: string | null; quantity: number; found_by: string }[]>> {
  return call('f360_opening_unlisted_open', { p_count_id: id });
}
export async function openingStepAction(id: string, step: 'freeze' | 'reconcile' | 'approve' | 'cancel', note = ''): Promise<Result<unknown>> {
  const fn = { freeze: 'f360_opening_freeze', reconcile: 'f360_opening_reconcile', approve: 'f360_opening_approve', cancel: 'f360_opening_cancel' }[step];
  const args: Record<string, unknown> = { p_count_id: id };
  if (step === 'approve') args.p_note = note; if (step === 'cancel') args.p_reason = note;
  const r = await call(fn, args); if (r.ok) revalidateCount(); return r;
}

export async function removeColorAction(productId: string, colorId: string, reason: string): Promise<Result<Product>> {
  if (reason.trim().length < 3) return { ok: false, error: 'Escribe el motivo.' };
  const r = await call<Product>('f360_remove_color', { p_color_id: colorId, p_reason: reason.trim() });
  if (r.ok) revalidateProduct(productId);
  return r;
}

// Track D · D4 (staging) — store visibility, opening load, channel links. All rules enforced again in the database.
export async function storeVisibilityAction(target: string, wooProductId: number, kind: 'ocultar' | 'mostrar', reason: string): Promise<Result<unknown>> {
  const r = await call('f360_store_visibility_request', { p_target_key: target, p_woo_product_id: wooProductId, p_kind: kind, p_reason: reason.trim() });
  if (r.ok) revalidatePath('/homologacion'); return r;
}
export async function linkProductsAction(target: string, productIds: string[], reason: string): Promise<Result<{ linked: number; queued: number }>> {
  const r = await call<{ linked: number; queued: number }>('f360_legacy_link_products', { p_target_key: target, p_product_ids: productIds, p_reason: reason.trim() });
  if (r.ok) productIds.forEach(revalidateProduct); return r;
}
export async function openingLoadAction(id: string, idempotencyKey: string): Promise<Result<unknown>> {
  const r = await call('f360_opening_load', { p_count_id: id, p_idempotency_key: idempotencyKey }); if (r.ok) { revalidateCount(); revalidatePath('/inventario', 'layout'); } return r;
}
export async function linkChannelAction(target: string): Promise<Result<{ linked: number; queued: number; total_links: number }>> {
  const r = await call<{ linked: number; queued: number; total_links: number }>('f360_legacy_link_channel', { p_target_key: target }); if (r.ok) revalidateCount(); return r;
}

export async function renameColorAction(productId: string, colorId: string, name: string): Promise<Result<Product>> {
  if (!name.trim()) return { ok: false, error: 'Escribe el nombre del color.' };
  const r = await call<Product>('f360_rename_color', { p_color_id: colorId, p_name: name.trim() });
  if (r.ok) revalidateProduct(productId);
  return r;
}
export async function createLocationAction(input: { name: string; type: 'store' | 'bazaar' | 'warehouse'; legacyChannelId: string | null; startsOn: string | null; endsOn: string | null }): Promise<Result<unknown>> {
  if (!input.name.trim()) return { ok: false, error: 'Escribe el nombre.' };
  const r = await call('f360_create_location', { p_name: input.name.trim(), p_type: input.type, p_legacy_channel_id: input.legacyChannelId,
    p_sellable: null, p_starts_on: input.startsOn || null, p_ends_on: input.endsOn || null });
  if (r.ok) { revalidatePath('/tiendas'); revalidatePath('/inventario', 'layout'); }
  return r;
}
export async function updateLocationAction(input: { id: string; name: string; type: 'store' | 'bazaar' | 'warehouse'; startsOn: string | null; endsOn: string | null }): Promise<Result<unknown>> {
  if (!input.name.trim()) return { ok: false, error: 'Escribe el nombre.' };
  const r = await call('f360_update_location', { p_location_id: input.id, p_name: input.name.trim(), p_type: input.type, p_starts_on: input.startsOn || null, p_ends_on: input.endsOn || null });
  if (r.ok) { revalidatePath('/tiendas'); revalidatePath('/inventario', 'layout'); }
  return r;
}
export async function deactivateLocationAction(id: string): Promise<Result<unknown>> {
  const r = await call('f360_deactivate_location', { p_location_id: id });
  if (r.ok) { revalidatePath('/tiendas'); revalidatePath('/inventario', 'layout'); }
  return r;
}

export async function cancelReservationAction(id: string, reason: string): Promise<Result<unknown>> {
  if (reason.trim().length < 3) return { ok: false, error: 'Escribe el motivo.' };
  const r = await call('f360_reservation_cancel', { p_reservation_id: id, p_reason: reason.trim() });
  if (r.ok) revalidatePath('/apartados'); return r;
}

// Ventas pasadas: the RPC answers refusals as { ok: false, error } data, so unwrap them into the same Result shape.
type Refusal = { ok: boolean; error?: string };
export async function saveHistSaleAction(input: { kind: 'store_month' | 'bazaar'; locationId: string | null; bazaarName: string | null; start: string;
  end: string | null; amount: number; pairs: number; pairsEstimated: boolean; notes: string }): Promise<Result<unknown>> {
  const r = await call<Refusal>('f360_hist_sales_save', { p_kind: input.kind, p_location: input.locationId || null, p_bazaar_name: input.bazaarName || null,
    p_start: input.start || null, p_end: input.end || null, p_amount: input.amount, p_pairs: input.pairs, p_pairs_estimated: input.pairsEstimated,
    p_notes: input.notes.trim() || null });
  if (!r.ok) return r;
  if (!r.data.ok) return { ok: false, error: r.data.error ?? 'No se pudo guardar.' };
  revalidatePath('/ventas/pasadas');
  return r;
}
export async function voidHistSaleAction(id: string, reason: string): Promise<Result<unknown>> {
  const r = await call<Refusal>('f360_hist_sales_void', { p_id: id, p_reason: reason.trim() });
  if (!r.ok) return r;
  if (!r.data.ok) return { ok: false, error: r.data.error ?? 'No se pudo anular.' };
  revalidatePath('/ventas/pasadas');
  return r;
}

// CRO-3A · Ajuste y talla. Every rule (fields, values, who validates) is enforced again in the database.
export async function saveKnowledgeAction(productId: string, fields: Record<string, string>, validate: boolean): Promise<Result<unknown>> {
  const r = await call('f360_product_knowledge_save', { p_product_id: productId, p_fields: fields, p_validate: validate });
  if (r.ok) revalidatePath(`/productos/${productId}`);
  return r;
}
