'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { setMakeToOrderAction, setProductNewAction } from '../../actions';

// Sobre pedido: when a size has no stock, the store still sells it, shipped in 5–7 business days (Mario 2026-10-03).
export function MakeToOrderPanel({ productId, on }: { productId: string; on: boolean }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const toggle = () => start(async () => {
    setError(null);
    const r = await setMakeToOrderAction(productId, !on, on ? 'Ya no se hace sobre pedido' : 'Se puede pedir sobre pedido');
    if (!r.ok) setError(r.error); else router.refresh();
  });
  return (
    <section className="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-line bg-surface p-5" data-testid="make-to-order">
      <div>
        <h2 className="font-display text-2xl text-ink">Vender tallas sin existencia (5 a 7 días)</h2>
        <p className="mt-1 text-sm text-ink-2">{on
          ? 'Si una talla no tiene existencia, en la tienda se puede comprar igual y dice “Esta talla y color se entrega en 5 a 7 días hábiles”.'
          : 'Si una talla no tiene existencia, en la tienda sale agotada y no se puede comprar.'}</p>
        {error && <p className="mt-2 text-sm text-danger">{error}</p>}
      </div>
      <button type="button" role="switch" aria-checked={on} onClick={toggle} disabled={pending}
        className={`relative h-8 w-14 rounded-full transition ${on ? 'bg-success' : 'bg-surface-2 ring-1 ring-line'} disabled:opacity-50`}>
        <span className={`absolute top-1 size-6 rounded-full bg-white shadow transition ${on ? 'left-7' : 'left-1'}`} />
        <span className="sr-only">Sobre pedido</span>
      </button>
    </section>
  );
}

// "Nuevas" carousel in the store (Mario 2026-10-03): Carolina decides; automatic = registered < 45 days and not from the old store.
export function NewPanel({ productId, value }: { productId: string; value: boolean | null }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const opts: [boolean | null, string][] = [[true, 'Sí, es nuevo'], [false, 'No'], [null, 'Automático']];
  return (
    <section className="mt-4 flex flex-wrap items-center justify-between gap-4 rounded-3xl border border-line bg-surface p-5" data-testid="new-panel">
      <div>
        <h2 className="font-display text-2xl text-ink">Nuevo en la tienda</h2>
        <p className="mt-1 text-sm text-ink-2">Sale en el carrusel “Nuevas”. Automático: modelos dados de alta hace menos de 45 días que no venían de la tienda anterior.</p>
      </div>
      <div className="flex gap-2">{opts.map(([v, l]) => (
        <button key={String(v)} type="button" disabled={pending} onClick={() => start(async () => { await setProductNewAction(productId, v); router.refresh(); })}
          className={`rounded-full px-4 py-2 text-sm ${value === v ? 'bg-ink text-surface' : 'text-ink-2 ring-1 ring-line'}`}>{l}</button>))}
      </div>
    </section>
  );
}
