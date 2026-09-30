'use server';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { publisherAvailable } from '@/lib/env-guard';
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
