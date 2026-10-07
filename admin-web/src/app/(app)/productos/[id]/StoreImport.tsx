'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { LegacySource } from '@/lib/f360';
import { importFromStoreAction, linkProductsAction } from '../../actions';
import { StoreContentPush } from '../StoreContentPush';

/** Brings the store's photos, price and description into the model, a few colours per call, until done. */
export async function runStoreImport(productId: string, onProgress?: (text: string) => void) {
  let photos = 0, price = false, description = false; const skipped: string[] = [];
  for (let i = 0; i < 30; i++) {
    const r = await importFromStoreAction(productId);
    if (!r.ok) return { ok: false as const, error: r.error };
    photos += r.data.photos; price ||= r.data.price; description ||= r.data.description; skipped.push(...r.data.skipped);
    onProgress?.(`Trayendo fotos de la tienda… ${photos} hasta ahora`);
    if (!r.data.remaining) break;
  }
  const done = [photos ? `${photos} fotos` : null, price ? 'precio' : null, description ? 'descripción' : null].filter(Boolean);
  return { ok: true as const, text: done.length ? `De la tienda se trajeron: ${done.join(', ')}.` : 'No faltaba nada por traer de la tienda.', skipped };
}

// Shown instead of the "falta para la tienda" checklist on a model adopted from the current store.
export function StoreOrigin({ productId, sources, canEdit, missing, owner = false, rehearsal = false }: { productId: string; sources: LegacySource[]; canEdit: boolean; missing: string[]; owner?: boolean; rehearsal?: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  const [notes, setNotes] = useState<string[]>([]);
  const products = new Set(sources.map((s) => s.woo_product_id)).size;
  const run = () => start(async () => {
    setMsg('Leyendo la tienda…'); setNotes([]);
    const r = await runStoreImport(productId, setMsg);
    setMsg(r.ok ? r.text : r.error); setNotes(r.ok ? r.skipped.filter((s) => !s.endsWith('ya tenía fotos')) : []);
    router.refresh();
  });
  return (
    <div className="mt-6 rounded-2xl border border-line bg-surface p-5" data-testid="store-origin">
      <p className="text-ink">Este modelo <b>ya está en la tienda en línea</b>: viene de {products} {products === 1 ? 'producto' : 'productos'} de la tienda ({sources[0]?.target_name}).</p>
      <p className="mt-1 text-sm text-muted">No se publica de nuevo. Sus fotos, precio y descripción se traen de la tienda.</p>
      {missing.length > 0 && <p className="mt-2 text-sm text-ink-2">Todavía falta en Fuxia 360: {missing.join(', ')}.</p>}
      {canEdit && (
        <button type="button" onClick={run} disabled={pending} className="mt-4 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-50">
          {pending ? 'Trayendo…' : 'Traer fotos, precio y descripción de la tienda'}
        </button>
      )}
      {owner && rehearsal && (
        <div className="mt-4 border-t border-line pt-4">
          <p className="text-sm text-ink-2">Ensayo en la tienda de pruebas: envía a {sources[0].target_name} las cantidades reales de este modelo (lo que hay en Bodega CDMX; con 0 sale agotado).</p>
          <button type="button" disabled={pending} onClick={() => start(async () => {
            const r = await linkProductsAction(sources[0].target_key, [productId], 'Ensayo desde la ficha del modelo');
            setMsg(r.ok ? (r.data.linked ? `Ligadas ${r.data.linked} tallas; la tienda se actualiza en ~1 minuto.` : `Ya estaba ligado; se reenviaron ${r.data.queued} tallas.`) : r.error); router.refresh();
          })} className="mt-2 rounded-full border border-ink px-4 py-2 text-sm text-ink">Mostrar cantidades en la tienda de pruebas</button>
          <div className="mt-4"><StoreContentPush productIds={[productId]} label="Mandar fotos, descripción y precio de este modelo" /></div>
        </div>
      )}
      {msg && <p className="mt-3 text-sm text-ink-2" role="status">{msg}</p>}
      {notes.length > 0 && <ul className="mt-1 list-disc pl-5 text-xs text-muted">{notes.map((n) => <li key={n}>{n}</li>)}</ul>}
    </div>
  );
}
