import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, listHistSales } from '@/lib/f360';
import { dinero } from '@/lib/format';
import { HistForm } from './HistForm';
import { VoidHistButton } from './VoidHistButton';

// Ventas pasadas (Mario 2026-10-05): Carolina loads general totals of sales made BEFORE Fuxia 360 — a store per month or a
// bazaar by dates — so the dashboard shows the whole year. Online history comes from WooCommerce; it is not typed here.
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const monthName = (ym: string) => { const [y, m] = ym.split('-'); return `${MONTHS[Number(m) - 1]} ${y}`; };
const day = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' });

export default async function VentasPasadas({ searchParams }: { searchParams: Promise<{ anio?: string }> }) {
  const { anio } = await searchParams;
  if (!canWrite((await getMe()).role)) redirect('/');
  const data = await listHistSales(anio ? Number(anio) : undefined);
  return (
    <div>
      <Link href="/ventas" className="text-sm text-muted">← Ventas</Link>
      <h1 className="font-display mt-2 text-5xl text-ink">Ventas pasadas</h1>
      <p className="mt-2 max-w-2xl text-ink-2">
        Totales de lo que vendieron las tiendas y los bazares antes de usar Fuxia 360. Solo monto y pares, en pesos. Lo de la tienda en línea ya
        viene de WooCommerce, no hay que cargarlo.
      </p>

      <div className="mt-6 grid gap-6 lg:grid-cols-[minmax(0,420px)_minmax(0,1fr)]">
        <HistForm stores={data.stores} bazaars={data.bazaars} />

        <div className="flex flex-col gap-6">
          <div className="rounded-3xl bg-ink p-6 text-surface">
            <p className="text-sm text-surface/70">Cargado en {data.year}</p>
            <p className="font-display tabular mt-1 text-5xl">{dinero(data.total.amount)}</p>
            <p className="tabular mt-1 text-surface/80">{data.total.pairs.toLocaleString('es-MX')} pares · resumen histórico (MXN)</p>
            {data.by_month.length > 0 && (
              <div className="mt-5 flex flex-wrap gap-2">
                {data.by_month.map((m) => (
                  <span key={m.month} className="tabular rounded-full bg-surface/10 px-3 py-1 text-sm">{monthName(m.month)} · {dinero(m.amount)}</span>
                ))}
              </div>
            )}
          </div>

          <div className="rounded-3xl border border-line bg-surface">
            <div className="flex items-center justify-between border-b border-line px-5 py-4">
              <h2 className="font-display text-2xl text-ink">Lo que ya se cargó</h2>
              <div className="flex gap-2 text-sm">
                {[data.year - 1, data.year].map((y) => (
                  <Link key={y} href={`/ventas/pasadas?anio=${y}`} className={`rounded-full px-3 py-1 ${y === data.year ? 'bg-ink text-surface' : 'border border-line text-ink-2'}`}>{y}</Link>
                ))}
              </div>
            </div>
            {data.items.length === 0 ? (
              <p className="px-5 py-8 text-center text-muted">Todavía no hay nada cargado para {data.year}.</p>
            ) : (
              <ul className="divide-y divide-line">
                {data.items.map((h) => (
                  <li key={h.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-4">
                    <div className="min-w-0 flex-1">
                      <p className="text-ink">
                        <span className="font-medium">{h.place}</span>
                        <span className="ml-2 rounded-full bg-surface-2 px-2 py-0.5 text-xs text-ink-2">{h.kind === 'bazaar' ? 'Bazar' : 'Tienda'}</span>
                      </p>
                      <p className="text-sm text-muted">
                        {h.kind === 'store_month' ? monthName(h.period_start.slice(0, 7)) : h.period_start === h.period_end ? day(h.period_start) : `${day(h.period_start)} – ${day(h.period_end)}`}
                        {h.created_by_name ? ` · cargó ${h.created_by_name}` : ''}{h.notes ? ` · ${h.notes}` : ''}
                      </p>
                    </div>
                    <div className="tabular text-right">
                      <p className="text-ink">{dinero(h.amount)}</p>
                      <p className="text-sm text-muted">{h.pairs_estimated ? '~' : ''}{h.pairs} pares</p>
                    </div>
                    <VoidHistButton id={h.id} label={h.place} />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
