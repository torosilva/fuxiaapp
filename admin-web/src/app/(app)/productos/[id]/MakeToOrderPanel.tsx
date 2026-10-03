'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { setMakeToOrderAction } from '../../actions';

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
