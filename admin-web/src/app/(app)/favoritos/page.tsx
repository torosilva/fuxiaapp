import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getFavoritesReport } from '@/lib/f360';

// ♡ Favoritos / Intent V1 (Mario 2026-10-06): what the store's visitors save, per model, anonymously. A report only — nothing
// here changes the store, sends messages or reorders products (those come later, by decision). ATC is not captured by
// Fuxia 360 yet: shown as "—", never estimated.
export default async function Favoritos({ searchParams }: { searchParams: Promise<{ dias?: string }> }) {
  if (process.env.NEXT_PUBLIC_F360_ENV === 'production') notFound();   // V1 lives in staging until production is approved
  const sp = await searchParams;
  const days = [7, 30, 90].includes(Number(sp.dias)) ? Number(sp.dias) : 30;
  const r = await getFavoritesReport(days);
  const pill = (on: boolean) => `rounded-full px-4 py-2 text-sm ${on ? 'bg-ink text-[#F7E7C4]' : 'border border-line bg-surface text-ink-2'}`;
  const active = r.rows.reduce((a, x) => a + x.active, 0), adds = r.rows.reduce((a, x) => a + x.adds, 0);
  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-2">
        <h1 className="font-display text-[56px] font-semibold leading-none text-ink">Favoritos</h1>
        <p className="max-w-3xl text-[15px] text-ink-2">Lo que las visitantes guardan con ♡ en la tienda (México y Colombia), por modelo. Anónimo: sin nombres ni teléfonos. Es una señal de intención: qué gusta aunque todavía no se compre.</p>
      </header>
      <nav className="flex flex-wrap gap-2" aria-label="Periodo">
        {[7, 30, 90].map((d) => <Link key={d} href={`/favoritos?dias=${d}`} className={pill(days === d)}>{d} días</Link>)}
      </nav>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="rounded-3xl bg-[#14110D] p-5 text-[#F7E7C4]"><p className="text-[11px] font-bold tracking-[0.2em] text-[#E8C98A]">FAVORITOS ACTIVOS</p><p className="font-display tabular text-5xl font-semibold">{active}</p><p className="text-xs opacity-75">guardados hoy, en todos los dispositivos</p></div>
        <div className="rounded-3xl border border-line bg-surface p-5"><p className="text-[11px] font-bold tracking-[0.2em] text-gold-strong">♡ AGREGADOS · {days} DÍAS</p><p className="font-display tabular text-5xl font-semibold text-ink">{adds}</p><p className="text-xs text-muted">veces que tocaron ♡</p></div>
      </div>
      {r.rows.length === 0 ? (
        <p className="rounded-3xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">Todavía nadie ha guardado favoritos en este periodo.</p>
      ) : (
        <div className="overflow-x-auto rounded-3xl border border-line bg-surface">
          <table className="w-full min-w-[680px] text-sm">
            <thead className="text-left text-[11px] font-bold tracking-[0.16em] text-muted">
              <tr className="border-b border-line">
                <th className="px-5 py-3">MODELO</th><th className="px-3 py-3 text-right">FAVORITOS ACTIVOS</th><th className="px-3 py-3 text-right">AGREGADOS {days}D</th>
                <th className="px-3 py-3 text-right">QUITADOS {days}D</th><th className="px-3 py-3 text-right">AL CARRITO</th><th className="px-5 py-3 text-right">VENDIDOS {days}D</th>
              </tr>
            </thead>
            <tbody>
              {r.rows.map((x) => (
                <tr key={x.key} className="border-b border-line/70 last:border-0">
                  <td className="px-5 py-3">{x.product_id ? <Link href={`/productos/${x.product_id}`} className="font-medium text-ink hover:text-gold-strong">{x.model}</Link> : <span className="text-ink-2">{x.model} <span className="text-xs text-muted">(sin identificar)</span></span>}</td>
                  <td className="tabular px-3 py-3 text-right font-semibold text-ink">{x.active}</td>
                  <td className="tabular px-3 py-3 text-right">{x.adds}</td>
                  <td className="tabular px-3 py-3 text-right">{x.removes}</td>
                  <td className="tabular px-3 py-3 text-right text-muted">{x.atc ?? '—'}</td>
                  <td className="tabular px-5 py-3 text-right">{x.sold ?? '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <p className="text-xs text-muted">“Al carrito” todavía no se registra en Fuxia 360 (se mide en GA4); llegará en la siguiente fase y aquí no se estima. Vendidos = pares de ese modelo en tiendas y en línea en el mismo periodo.</p>
    </div>
  );
}
