'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { Location } from '@/lib/f360';
import { pares } from '@/lib/format';
import { deactivateLocationAction, updateLocationAction } from '../actions';

const TYPE: Record<string, string> = { store: 'Tienda', bazaar: 'Bazar', warehouse: 'Bodega', receiving: 'Recepción', workshop: 'Taller', other: 'Otra' };
type EditType = 'store' | 'bazaar' | 'warehouse';

// One location: Cambios (name, type, bazaar dates) and Baja. Owner only; the database re-checks everything.
export function LocationRow({ l, owner }: { l: Location; owner: boolean }) {
  const router = useRouter();
  const [mode, setMode] = useState<'view' | 'edit' | 'baja'>('view');
  const [f, setF] = useState({ name: l.name, type: (['store', 'bazaar', 'warehouse'].includes(l.type) ? l.type : 'store') as EditType, startsOn: l.starts_on ?? '', endsOn: l.ends_on ?? '' });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 outline-none focus:border-gold';
  const editable = owner && ['store', 'bazaar', 'warehouse'].includes(l.type);
  const close = () => { setMode('view'); setError(null); };

  return (
    <div className="px-5 py-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex-1">
          <div className="text-ink">{l.name}</div>
          <div className="text-xs text-muted">{TYPE[l.type] ?? l.type}{l.starts_on ? ` · ${l.starts_on} → ${l.ends_on ?? ''}` : ''}{l.sellable ? ' · vende al público' : ''}</div>
        </div>
        <span className={`rounded-full px-3 py-1 text-xs ${l.ledger_authority === 'legacy' ? 'bg-gold-soft text-ink-2' : 'bg-success-soft text-success'}`}>
          {l.ledger_authority === 'legacy' ? 'Inventario en el sistema anterior (falta corte)' : 'Inventario en Fuxia 360'}</span>
        <span className="tabular w-24 text-right text-ink">{pares(l.pairs)}</span>
        {editable && mode === 'view' && (
          <div className="flex gap-2">
            <button type="button" onClick={() => setMode('edit')} className="rounded-full border border-line px-4 py-2 text-sm text-ink-2">Editar</button>
            <button type="button" onClick={() => setMode('baja')} className="rounded-full border border-line px-4 py-2 text-sm text-danger">Dar de baja</button>
          </div>
        )}
      </div>

      {mode === 'edit' && (
        <div className="mt-4 grid gap-3 rounded-2xl border border-line bg-bg/50 p-4 sm:grid-cols-2">
          <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} className={input} /></label>
          <label className="text-sm text-ink-2">Tipo
            <select aria-label="Tipo" value={f.type} onChange={(e) => setF({ ...f, type: e.target.value as EditType })} className={input}>
              <option value="store">Tienda</option><option value="bazaar">Bazar</option><option value="warehouse">Bodega</option>
            </select></label>
          {f.type === 'bazaar' && <>
            <label className="text-sm text-ink-2">Empieza<input type="date" aria-label="Empieza" value={f.startsOn} onChange={(e) => setF({ ...f, startsOn: e.target.value })} className={input} /></label>
            <label className="text-sm text-ink-2">Termina<input type="date" aria-label="Termina" value={f.endsOn} onChange={(e) => setF({ ...f, endsOn: e.target.value })} className={input} /></label>
          </>}
          <div className="flex gap-2 sm:col-span-2">
            <button type="button" disabled={pending} onClick={() => start(async () => {
              const r = await updateLocationAction({ id: l.id, name: f.name, type: f.type, startsOn: f.startsOn || null, endsOn: f.endsOn || null });
              if (r.ok) { close(); router.refresh(); } else setError(r.error);
            })} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar'}</button>
            <button type="button" onClick={close} className="rounded-full px-4 py-2.5 text-sm text-ink-2">Cancelar</button>
          </div>
        </div>
      )}

      {mode === 'baja' && (
        <div className="mt-4 rounded-2xl border border-danger/40 bg-danger-soft/40 p-4">
          <p className="text-sm text-ink">¿Dar de baja <b>{l.name}</b>? Deja de aparecer en Fuxia 360 y nadie puede vender ahí. Su historial se queda guardado.</p>
          <div className="mt-3 flex gap-2">
            <button type="button" disabled={pending} onClick={() => start(async () => {
              const r = await deactivateLocationAction(l.id);
              if (r.ok) { close(); router.refresh(); } else setError(r.error);
            })} className="rounded-full bg-danger px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Dando de baja…' : 'Sí, dar de baja'}</button>
            <button type="button" onClick={close} className="rounded-full px-4 py-2.5 text-sm text-ink-2">No</button>
          </div>
        </div>
      )}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
    </div>
  );
}
