import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, getStockDemand } from '@/lib/f360';

// CRO-5 (Mario 2026-10-05): DEMANDA SIN INVENTARIO — commercial intelligence, not just notifications.
// "Esperando" = Avísame cuando llegue (operational consent). "Vendidos sobre pedido" = paid orders without stock (10 días).
// Below: the single delivery-promise rule every channel reads (blocked = needs a business decision).
const CASE: Record<string, string> = { in_stock: 'Con existencia', made_to_order: 'Sin existencia, sobre pedido', unavailable: 'Agotada (sin sobre pedido)' };

export default async function Demanda({ searchParams }: { searchParams: Promise<{ mercado?: string }> }) {
  if (!canWrite((await getMe()).role)) redirect('/');
  const { mercado } = await searchParams;
  const d = await getStockDemand(mercado);
  const pill = (on: boolean) => `rounded-full px-4 py-2 text-sm ${on ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  const total = d.models.reduce((a, m) => a + m.waiting, 0), mto = d.models.reduce((a, m) => a + m.mto_pairs, 0);
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Demanda sin inventario</h1>
      <p className="mt-2 max-w-3xl text-ink-2">Quién quiere un modelo, color y talla que no tenemos en existencia: clientas esperando que llegue y pares vendidos sobre pedido. Sin datos personales.</p>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/demanda" className={pill(!mercado)}>Todos</Link>
        <Link href="/demanda?mercado=MX" className={pill(mercado === 'MX')}>México</Link>
        <Link href="/demanda?mercado=CO" className={pill(mercado === 'CO')}>Colombia</Link>
      </div>
      <div className="mt-5 grid gap-3 sm:grid-cols-2">
        <div className="rounded-3xl bg-ink p-5 text-surface"><p className="text-sm text-surface/70">Clientas esperando</p><p className="font-display tabular text-5xl">{total}</p></div>
        <div className="rounded-3xl border border-line bg-surface p-5"><p className="text-sm text-muted">Pares vendidos sobre pedido (en curso)</p><p className="font-display tabular text-5xl text-ink">{mto}</p></div>
      </div>

      {d.models.length === 0 ? (
        <p className="mt-8 rounded-2xl border border-dashed border-line p-8 text-center text-muted">Todavía no hay demanda sin inventario registrada.</p>
      ) : d.models.map((m) => (
        <section key={m.product_key + m.product} className="mt-6 rounded-3xl border border-line bg-surface p-5">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="font-display text-3xl text-ink">{m.product}</h2>
            <span className="text-sm text-muted">{m.waiting} esperando · {m.mto_pairs} sobre pedido</span>
          </div>
          <ul className="mt-3 divide-y divide-line">
            {m.sizes.map((s) => (
              <li key={`${s.color}-${s.size}`} className="flex flex-wrap items-center justify-between gap-2 py-3">
                <span className="text-ink">{s.color} / {s.size}</span>
                <span className="tabular text-ink-2">
                  {s.waiting > 0 && <b className="text-ink">{s.waiting} esperando</b>}{s.waiting > 0 && s.mto_pairs > 0 ? ' · ' : ''}{s.mto_pairs > 0 && `${s.mto_pairs} sobre pedido`}
                </span>
              </li>
            ))}
          </ul>
        </section>
      ))}

      <h2 className="font-display mt-12 text-3xl text-ink">Promesa de entrega (una sola regla)</h2>
      <p className="mt-1 text-sm text-muted">La tienda, el checkout, Hilo y “Pedido recibido” leen esta misma tabla. “Por decidir” usa un texto conservador sin tiempos.</p>
      <div className="mt-4 overflow-x-auto rounded-3xl border border-line bg-surface">
        <table className="w-full min-w-[640px] text-left text-sm">
          <thead className="text-muted"><tr><th className="px-4 py-3">Mercado</th><th className="px-4 py-3">Caso</th><th className="px-4 py-3">Texto</th><th className="px-4 py-3">Estado</th></tr></thead>
          <tbody className="divide-y divide-line">
            {d.rules.map((r) => (
              <tr key={r.market + r.promise_case}>
                <td className="px-4 py-3">{r.market === 'OTHER' ? 'Otros' : r.market}</td>
                <td className="px-4 py-3">{CASE[r.promise_case] ?? r.promise_case}</td>
                <td className="px-4 py-3 text-ink">{r.headline}{r.detail ? <span className="block text-muted">{r.detail}</span> : null}</td>
                <td className="px-4 py-3">{r.status === 'known' ? <span className="text-success">Definido · {r.decided_by}</span> : <span className="rounded-full bg-gold-soft px-2 py-1 text-ink-2">Por decidir</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
