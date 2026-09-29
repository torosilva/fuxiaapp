import Link from 'next/link';
import { redirect } from 'next/navigation';
import { EventCard } from '@/components/EventCard';
import { IconBack } from '@/components/icons';
import { canWrite, getMe, getSale } from '@/lib/f360';
import { dinero, fecha, PAYMENT_LABEL, pares } from '@/lib/format';

export default async function Venta({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const v = await getSale(id);
  const tone = v.loyalty.state === 'credited' ? 'bg-success-soft text-success' : 'bg-surface-2 text-ink-2';
  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/ventas" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Ventas</Link>
      <p className="mt-6 text-xs uppercase tracking-[0.25em] text-gold">Venta en tienda · Completada</p>
      <h1 className="font-display mt-2 text-5xl text-ink">{dinero(v.total)}</h1>
      <p className="mt-2 text-lg text-ink-2">{fecha(v.occurred_at)} · {v.location?.name ?? '—'} · {v.seller}</p>

      <dl className="mt-6 grid gap-3 sm:grid-cols-3">
        <div className="rounded-2xl border border-line bg-surface p-4"><dt className="text-sm text-muted">Clienta</dt>
          <dd className="mt-1 text-ink" data-testid="sale-customer">{v.customer ? <>{v.customer.name ?? 'Clienta'} <span className="text-muted">{v.customer.phone}</span></> : 'Sin identificar'}</dd></div>
        <div className="rounded-2xl border border-line bg-surface p-4"><dt className="text-sm text-muted">Pago</dt>
          <dd className="mt-1 text-ink">{PAYMENT_LABEL[v.payment_method ?? ''] ?? '—'}{v.payment_reference ? ` · ${v.payment_reference}` : ''}</dd></div>
        <div className="rounded-2xl border border-line bg-surface p-4"><dt className="text-sm text-muted">Inventario</dt>
          <dd className="mt-1 text-ink">{v.ledger === 'f360' ? 'Fuxia 360' : 'Sistema anterior'}</dd></div>
      </dl>

      <div className="mt-6 overflow-x-auto rounded-3xl border border-line bg-surface">
        <table className="w-full min-w-[520px] text-left">
          <thead className="bg-surface-2 text-xs uppercase tracking-wider text-muted">
            <tr><th className="px-4 py-3">Producto</th><th className="px-3 py-3 text-right">Cant.</th><th className="px-3 py-3 text-right">Precio</th><th className="px-4 py-3 text-right">Importe</th></tr>
          </thead>
          <tbody className="divide-y divide-line">
            {v.items.map((i) => (
              <tr key={i.line} className="tabular" data-testid="sale-item">
                <td className="px-4 py-3"><div className="font-medium text-ink">{i.product_name}</div><div className="text-sm text-muted">{[i.color, i.size && `Talla ${i.size}`, i.sku].filter(Boolean).join(' · ')}</div></td>
                <td className="px-3 py-3 text-right">{i.quantity}</td><td className="px-3 py-3 text-right">{dinero(i.unit_price)}</td><td className="px-4 py-3 text-right font-medium">{dinero(i.line_total)}</td>
              </tr>
            ))}
            <tr className="bg-surface-2"><td className="px-4 py-3 font-medium" colSpan={3}>Total</td><td className="tabular px-4 py-3 text-right text-lg font-semibold">{dinero(v.total)}</td></tr>
          </tbody>
        </table>
      </div>

      <section className="mt-6">
        <h2 className="font-display text-3xl text-ink">Puntos</h2>
        <p className={`mt-3 rounded-2xl px-5 py-4 ${tone}`} data-testid="sale-loyalty">{v.loyalty.state === 'credited' ? `Se acreditaron ${v.loyalty.points} puntos (${pares(v.loyalty.pairs ?? 0)} × 100).` : v.loyalty.text}</p>
      </section>

      <section className="mt-6">
        <h2 className="font-display text-3xl text-ink">Movimiento de inventario</h2>
        <div className="mt-3">{v.inventory.kind === 'f360' ? <EventCard e={v.inventory.event} /> : <p className="rounded-2xl bg-surface-2 px-5 py-4 text-ink-2">{v.inventory.text}</p>}</div>
      </section>

      <details className="mt-6 rounded-2xl border border-line bg-surface p-4">
        <summary className="cursor-pointer text-sm text-ink-2">Datos para soporte</summary>
        <dl className="mt-3 grid gap-1 text-xs">
          {Object.entries(v.support).map(([k, val]) => <div key={k} className="flex gap-2"><dt className="w-44 shrink-0 text-muted">{k}</dt><dd className="break-all font-mono text-ink-2">{val ?? '—'}</dd></div>)}
          {v.loyalty.audit.map((a, i) => <div key={i} className="flex gap-2"><dt className="w-44 shrink-0 text-muted">loyalty_audit</dt><dd className="font-mono text-ink-2">{a.result} · {a.points} · {a.at}</dd></div>)}
        </dl>
      </details>
      <p className="mt-8 text-center text-sm text-muted">Una venta registrada no se modifica. Las devoluciones llegarán como movimientos nuevos.</p>
    </div>
  );
}
