'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { LegacyChannel } from '@/lib/f360';
import { createLocationAction } from '../actions';

export function NewLocation({ legacy }: { legacy: LegacyChannel[] }) {
  const router = useRouter();
  const [f, setF] = useState<{ name: string; type: 'store' | 'bazaar' | 'warehouse'; legacy: string; startsOn: string; endsOn: string }>({ name: '', type: 'store', legacy: '', startsOn: '', endsOn: '' });
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 outline-none focus:border-gold';
  const pickLegacy = (id: string) => { const ch = legacy.find((c) => c.id === id); setF({ ...f, legacy: id, name: f.name || ch?.name || '', type: ch?.type === 'bazar' ? 'bazaar' : f.type }); };
  return (
    <section className="mt-10 rounded-3xl border border-line bg-surface p-5" data-testid="new-location">
      <h2 className="font-display text-3xl text-ink">Agregar tienda, bazar o bodega</h2>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        {legacy.length > 0 && (
          <label className="text-sm text-ink-2 sm:col-span-2">¿Ya existe en el sistema anterior (app de vendedoras)?
            <select aria-label="Tienda del sistema anterior" value={f.legacy} onChange={(e) => pickLegacy(e.target.value)} className={input}>
              <option value="">No, es nueva</option>
              {legacy.map((c) => <option key={c.id} value={c.id}>{c.name} · {c.legacy_pairs} pares en el sistema anterior</option>)}
            </select>
            {f.legacy && <span className="mt-1 block text-xs text-muted">Se liga a esa tienda y sigue usando su inventario anterior hasta hacer su corte (conteo físico). No se mueve nada ahora.</span>}
          </label>
        )}
        <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre de la ubicación" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} className={input} /></label>
        <label className="text-sm text-ink-2">Tipo
          <select aria-label="Tipo de ubicación" value={f.type} onChange={(e) => setF({ ...f, type: e.target.value as typeof f.type })} className={input}>
            <option value="store">Tienda</option><option value="bazaar">Bazar</option><option value="warehouse">Bodega</option>
          </select></label>
        {f.type === 'bazaar' && <>
          <label className="text-sm text-ink-2">Empieza<input type="date" aria-label="Empieza" value={f.startsOn} onChange={(e) => setF({ ...f, startsOn: e.target.value })} className={input} /></label>
          <label className="text-sm text-ink-2">Termina<input type="date" aria-label="Termina" value={f.endsOn} onChange={(e) => setF({ ...f, endsOn: e.target.value })} className={input} /></label>
        </>}
      </div>
      {msg && <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
      <button type="button" disabled={pending} onClick={() => start(async () => {
        const r = await createLocationAction({ name: f.name, type: f.type, legacyChannelId: f.legacy || null, startsOn: f.startsOn || null, endsOn: f.endsOn || null });
        setMsg(r.ok ? { ok: true, text: `${f.name} agregada.` } : { ok: false, text: r.error }); if (r.ok) { setF({ name: '', type: 'store', legacy: '', startsOn: '', endsOn: '' }); router.refresh(); }
      })} className="mt-4 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Agregar'}</button>
    </section>
  );
}
