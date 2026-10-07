'use client';
import { useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { StoreOrder } from '@/lib/f360';
import { applyStoreOrderAction, setStoreFeaturedAction } from '../../actions';

/** Destacados (star, move up/down, remove) + the full shop order + "Aplicar a la tienda" (owner). */
export function StoreOrderPanel({ order, canEdit, canApply, storeName }: { order: StoreOrder; canEdit: boolean; canApply: boolean; storeName: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [q, setQ] = useState('');
  // one entry per model (an old store product per colour can appear several times in the shop list)
  const featured = useMemo(() => {
    const seen = new Map<string, { product_id: string; name: string; rank: number }>();
    for (const it of order.items) if (it.store_rank != null && !seen.has(it.product_id)) seen.set(it.product_id, { product_id: it.product_id, name: it.name, rank: it.store_rank });
    return [...seen.values()].sort((a, b) => a.rank - b.rank);
  }, [order.items]);
  const save = (ids: string[], text: string) => start(async () => {
    const r = await setStoreFeaturedAction(ids);
    setMsg(r.ok ? { ok: true, text: `${text} Pulsa “Aplicar a la tienda” para que se vea en ${storeName}.` } : { ok: false, text: r.error });
    router.refresh();
  });
  const ids = featured.map((f) => f.product_id);
  const move = (i: number, d: number) => { const n = [...ids]; const j = i + d; if (j < 0 || j >= n.length) return; [n[i], n[j]] = [n[j], n[i]]; save(n, 'Orden de destacados guardado.'); };
  const apply = () => start(async () => {
    setMsg({ ok: true, text: `Aplicando el orden en ${storeName}…` });
    const r = await applyStoreOrderAction();
    setMsg(r.ok ? { ok: true, text: `Listo: ${r.data.done} productos acomodados en ${storeName}. Si no lo ves, purga la caché de SG.` } : { ok: false, text: r.error });
    router.refresh();
  });
  const list = q ? order.items.filter((it) => it.name.toLowerCase().includes(q.toLowerCase())) : order.items;
  const last = order.last_run;

  return (
    <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.4fr)]">
      <section className="h-fit rounded-3xl border border-line bg-surface p-5" data-testid="store-order-featured">
        <h2 className="font-display text-2xl text-ink">⭐ Destacados</h2>
        <p className="mt-1 text-sm text-ink-2">Aparecen primero, en este orden.</p>
        {featured.length === 0 ? <p className="mt-4 text-sm text-muted">Ninguno todavía. Toca ⭐ en un modelo de la lista.</p> : (
          <ol className="mt-4 space-y-2">
            {featured.map((f, i) => (
              <li key={f.product_id} className="flex items-center gap-2 rounded-2xl bg-gold-soft/50 px-3 py-2">
                <span className="tabular w-6 text-sm text-ink-2">{i + 1}</span>
                <span className="flex-1 text-ink">{f.name}</span>
                {canEdit && <>
                  <button type="button" disabled={pending || i === 0} onClick={() => move(i, -1)} aria-label={`Subir ${f.name}`} className="rounded-full px-2 py-1 text-ink-2 ring-1 ring-line disabled:opacity-30">↑</button>
                  <button type="button" disabled={pending || i === featured.length - 1} onClick={() => move(i, 1)} aria-label={`Bajar ${f.name}`} className="rounded-full px-2 py-1 text-ink-2 ring-1 ring-line disabled:opacity-30">↓</button>
                  <button type="button" disabled={pending} onClick={() => save(ids.filter((x) => x !== f.product_id), `${f.name} ya no es destacado.`)} aria-label={`Quitar ${f.name}`} className="rounded-full px-2 py-1 text-ink-2 ring-1 ring-line">✕</button>
                </>}
              </li>
            ))}
          </ol>
        )}
        {canApply && (
          <button type="button" onClick={apply} disabled={pending} className="mt-5 w-full rounded-full bg-ink px-5 py-3 text-surface disabled:opacity-50" data-testid="store-order-apply">
            {pending ? 'Trabajando…' : `Aplicar a la tienda`}
          </button>
        )}
        {msg && <p className={`mt-3 text-sm ${msg.ok ? 'text-ink' : 'text-danger'}`} role="status">{msg.text}</p>}
        {last && <p className="mt-3 text-xs text-muted">Última vez aplicado: {new Date(last.at).toLocaleString('es-MX', { dateStyle: 'medium', timeStyle: 'short' })} por {last.by} · {last.ok ? `${last.items} productos` : `con errores: ${last.message ?? ''}`}</p>}
      </section>

      <section className="rounded-3xl border border-line bg-surface p-5" data-testid="store-order-list">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="font-display text-2xl text-ink">Cómo se ve la tienda</h2>
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Busca un modelo" className="rounded-full border border-line bg-surface px-4 py-2 text-sm outline-none focus:border-gold" />
        </div>
        <ol className="mt-4 divide-y divide-line">
          {list.map((it) => {
            const isFeat = it.store_rank != null;
            return (
              <li key={it.woo_product_id} className="flex items-center gap-3 py-2">
                <span className="tabular w-8 text-sm text-muted">{it.position}</span>
                <span className="flex-1 text-ink">{it.name}{it.legacy && <span className="ml-2 rounded-full bg-line/60 px-2 py-0.5 text-xs text-ink-2">tienda anterior</span>}</span>
                <span className="tabular text-sm text-ink-2" title="Pares vendidos (últimos 60 días)">{it.sold} vendidos</span>
                {canEdit && (
                  <button type="button" disabled={pending} aria-label={isFeat ? `Quitar destacado ${it.name}` : `Destacar ${it.name}`}
                    onClick={() => save(isFeat ? ids.filter((x) => x !== it.product_id) : [...ids, it.product_id], isFeat ? `${it.name} ya no es destacado.` : `${it.name} destacado.`)}
                    className={`rounded-full px-2.5 py-1 text-sm ring-1 ${isFeat ? 'bg-gold-soft text-ink ring-gold/40' : 'text-muted ring-line'}`}>⭐</button>
                )}
              </li>
            );
          })}
        </ol>
      </section>
    </div>
  );
}
