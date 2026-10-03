'use client';
import { useState } from 'react';
import { storeContentListAction, storeContentPushAction } from '../actions';

/** Owner: sends what Fuxia 360 has (photos, description, price, colour name) to the current store's products, one by
 *  one, with progress. `productIds` limits it to some models (e.g. the one being viewed). Staging only (DB refuses prod). */
export function StoreContentPush({ productIds, label }: { productIds?: string[]; label?: string }) {
  const [running, setRunning] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const [errors, setErrors] = useState<string[]>([]);
  const run = async () => {
    setRunning(true); setErrors([]); setMsg('Preparando…');
    const list = await storeContentListAction(productIds);
    if (!list.ok) { setMsg(list.error); setRunning(false); return; }
    let done = 0, photos = 0; const errs: string[] = [];
    for (const it of list.data) {
      setMsg(`Mandando a la tienda ${done + 1} de ${list.data.length}: ${it.name}…`);
      const r = await storeContentPushAction(it.woo_product_id);
      if (!r.ok) errs.push(`${it.name}: ${r.error}`);
      else if (!r.data.ok) errs.push(`${r.data.name}: ${r.data.message}`);
      else photos += r.data.photos;
      done++; setErrors([...errs]);
    }
    setMsg(`Listo: ${done - errs.length} de ${done} productos de la tienda actualizados (${photos} fotos). Si no lo ves, purga la caché de SG.`);
    setRunning(false);
  };
  return (
    <div className="rounded-2xl border border-line bg-surface p-5" data-testid="store-content-push">
      <p className="text-sm text-ink-2">Pone en la <b>tienda de pruebas</b> lo que hay aquí: fotos, descripción, precio y nombre del color. No cambia SKUs, existencias ni si el producto se ve.</p>
      <button type="button" onClick={run} disabled={running} className="mt-3 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-50">
        {running ? 'Mandando…' : (label ?? 'Mandar todo a la tienda de pruebas')}
      </button>
      {msg && <p className="mt-3 text-sm text-ink" role="status">{msg}</p>}
      {errors.length > 0 && <ul className="mt-2 list-disc pl-5 text-xs text-danger">{errors.map((e) => <li key={e}>{e}</li>)}</ul>}
    </div>
  );
}
