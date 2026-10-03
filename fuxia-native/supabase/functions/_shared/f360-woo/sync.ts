// Stock authority worker (Fuxia 360 → Woo) and reconciliation (Fuxia 360 ↔ Woo). Runtime-agnostic.
// The database decides WHAT must be pushed (queue filled by a trigger on Bodega balances); this code only talks to Woo.
import { stockToPush } from './mapping.ts';
import type { WooAdapter, WooVariation } from './types.ts';

export type Rpc = <T>(fn: string, args: Record<string, unknown>) => Promise<T>;
type Claim = { variant_id: string; claimed_at: string; attempts: number; sku: string; woo_product_id: number; woo_variation_id: number; ats: number; expected: number | null };
type Result = { variant_id: string; claimed_at: string; ok: boolean; ats: number; expected: number | null; woo_before: number | null; pushed: number | null; error: string | null };
const msg = (e: unknown) => (e instanceof Error ? e.message : String(e));

function groupBy<T>(xs: T[], key: (x: T) => number) {
  const m = new Map<number, T[]>();
  for (const x of xs) m.set(key(x), [...(m.get(key(x)) ?? []), x]);
  return m;
}

/** Drains the push queue once. Woo quantity = Bodega CDMX sellable stock (P-STOCK), minus sales Woo made that the ledger hasn't seen. */
export async function pushStock(rpc: Rpc, woo: WooAdapter, targetKey: string, limit = 100) {
  const claims = await rpc<Claim[]>('f360_sync_claim_stock', { p_target_key: targetKey, p_limit: limit });
  if (!claims.length) return { claimed: 0, ok: 0, failed: 0 };
  const results: Result[] = [];
  for (const [pid, group] of groupBy(claims, (c) => c.woo_product_id)) {
    const base = (c: Claim) => ({ variant_id: c.variant_id, claimed_at: c.claimed_at, ats: c.ats, expected: c.expected });
    let vars: WooVariation[];
    try { vars = await woo.listVariations(pid); }
    catch (e) { for (const c of group) results.push({ ...base(c), ok: false, woo_before: null, pushed: null, error: `Tienda no disponible: ${msg(e)}` }); continue; }
    const updates: { c: Claim; qty: number; before: number | null }[] = [];
    for (const c of group) {
      const w = vars.find((v) => v.id === c.woo_variation_id);
      if (!w) { results.push({ ...base(c), ok: false, woo_before: null, pushed: null, error: 'La variación ya no existe en la tienda.' }); continue; }
      const qty = stockToPush(c.ats, c.expected, w.stock_quantity);
      if (w.manage_stock === true && w.stock_quantity === qty) results.push({ ...base(c), ok: true, woo_before: w.stock_quantity, pushed: qty, error: null });
      else updates.push({ c, qty, before: w.stock_quantity });
    }
    for (let i = 0; i < updates.length; i += 100) {
      const chunk = updates.slice(i, i + 100);
      try {
        const r = await woo.batchVariations(pid, { update: chunk.map((u) => ({ id: u.c.woo_variation_id, manage_stock: true, stock_quantity: u.qty, backorders: 'no' })) }, 'stock');
        chunk.forEach((u, k) => {
          const item = r.update?.[k] as { error?: { message: string } } | undefined;
          results.push(item && !item.error
            ? { ...base(u.c), ok: true, woo_before: u.before, pushed: u.qty, error: null }
            : { ...base(u.c), ok: false, woo_before: u.before, pushed: null, error: item?.error?.message ?? 'Sin respuesta de la tienda.' });
        });
      } catch (e) {
        for (const u of chunk) results.push({ ...base(u.c), ok: false, woo_before: u.before, pushed: null, error: `Tienda no disponible: ${msg(e)}` });
      }
    }
  }
  const r = await rpc<{ ok: number; failed: number }>('f360_sync_stock_result', { p_target_key: targetKey, p_results: results });
  return { claimed: claims.length, ...r };
}

type Snap = { variant_id: string; sku: string; label: string; woo_product_id: number; woo_variation_id: number; ats: number; expected: number | null };

/** Read-only compare of every linked variant. Differences become alerts + a queued correction (done by the DB). */
export async function reconcile(rpc: Rpc, woo: WooAdapter, targetKey: string, requestedBy: string) {
  const snap = await rpc<Snap[]>('f360_reconcile_snapshot', { p_target_key: targetKey });
  const items: (Snap & { woo_stock: number | null; state: 'in_sync' | 'drift' | 'missing' })[] = [];
  for (const [pid, group] of groupBy(snap, (s) => s.woo_product_id)) {
    const vars = await woo.listVariations(pid);   // a store outage fails the whole run loudly (nothing recorded as "in sync")
    for (const s of group) {
      const w = vars.find((v) => v.id === s.woo_variation_id);
      if (!w) items.push({ ...s, woo_stock: null, state: 'missing' });
      else items.push({ ...s, woo_stock: w.stock_quantity, state: w.manage_stock === true && w.stock_quantity === s.ats ? 'in_sync' : 'drift' });
    }
  }
  return rpc<{ id: string; checked: number; in_sync: number; drifted: number; missing: number }>('f360_reconcile_finish',
    { p_target_key: targetKey, p_run: { requested_by_name: requestedBy, items } });
}

type VisClaim = { id: string; woo_product_id: number; kind: 'ocultar' | 'mostrar'; restore_status: string | null };

/** Applies queued "hide / show again" requests for store products a person marked "no existe" (D4).
 *  Hide = Woo status 'private' (never deleted); show = the status it had before hiding. */
export async function applyVisibility(rpc: Rpc, woo: WooAdapter, targetKey: string) {
  const claims = await rpc<VisClaim[]>('f360_visibility_claim', { p_target_key: targetKey });
  if (!claims.length) return { claimed: 0, ok: 0, failed: 0 };
  const results: { id: string; ok: boolean; before: string | null; after: string | null; error: string | null }[] = [];
  for (const c of claims) {
    try {
      const p = await woo.getProduct(c.woo_product_id);
      if (!p) { results.push({ id: c.id, ok: false, before: null, after: null, error: 'El producto ya no existe en la tienda.' }); continue; }
      const target = c.kind === 'ocultar' ? 'private' : (c.restore_status && c.restore_status !== 'private' ? c.restore_status : 'publish');
      if (p.status !== target) await woo.updateProduct(c.woo_product_id, { status: target });
      results.push({ id: c.id, ok: true, before: p.status, after: target, error: null });
    } catch (e) {
      results.push({ id: c.id, ok: false, before: null, after: null, error: `Tienda no disponible: ${msg(e)}` });
    }
  }
  const r = await rpc<{ ok: number; failed: number }>('f360_visibility_result', { p_target_key: targetKey, p_results: results });
  return { claimed: claims.length, ...r };
}
