import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, listSales } from '@/lib/f360';
import { dinero, fecha, PAYMENT_LABEL, pares } from '@/lib/format';

// C3.3 · Ventas: the authoritative sales already recorded by the sale RPC (S0.3 / C3). Nothing is typed in here and no
// reported figure is mixed in. Online orders will appear in this same list when P2.3B connects them (channel filter).
type SP = { desde?: string; hasta?: string; ubicacion?: string; vendedora?: string; canal?: string };
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
const daysAgo = (n: number) => new Date(Date.now() - n * 86400000).toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });

export default async function Ventas({ searchParams }: { searchParams: Promise<SP> }) {
  const sp = await searchParams;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const data = await listSales({ from: sp.desde, to: sp.hasta, locationId: sp.ubicacion, sellerId: sp.vendedora, channel: sp.canal });
  const s = data.summary;
  const keep = (extra: Record<string, string>) => {
    const q = new URLSearchParams({ ...(sp.ubicacion ? { ubicacion: sp.ubicacion } : {}), ...(sp.vendedora ? { vendedora: sp.vendedora } : {}), ...(sp.canal ? { canal: sp.canal } : {}), ...extra });
    return `/ventas?${q.toString()}`;
  };
  const preset = (label: string, from: string) => {
    const active = data.from === from && data.to === today();
    return <Link key={label} href={keep({ desde: from, hasta: today() })} className={`rounded-full px-4 py-2 text-sm ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>{label}</Link>;
  };
  const select = 'rounded-xl border border-line bg-surface px-3 py-2.5 text-[15px] outline-none focus:border-gold';
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Ventas</h1>
      <p className="mt-2 text-sm text-muted">Solo ventas registradas en Fuxia 360 (tiendas). Las ventas en línea se sumarán aquí cuando se conecte la tienda en línea.</p>

      <div className="mt-6 flex flex-wrap gap-2">{preset('Hoy', today())}{preset('7 días', daysAgo(6))}{preset('30 días', daysAgo(29))}</div>
      <form className="mt-4 flex flex-wrap items-end gap-3" action="/ventas">
        <label className="text-sm text-muted">Desde<input type="date" name="desde" defaultValue={data.from} className={`${select} mt-1 block`} /></label>
        <label className="text-sm text-muted">Hasta<input type="date" name="hasta" defaultValue={data.to} className={`${select} mt-1 block`} /></label>
        <label className="text-sm text-muted">Ubicación
          <select name="ubicacion" defaultValue={sp.ubicacion ?? ''} className={`${select} mt-1 block`}>
            <option value="">Todas</option>{data.filters.locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}
          </select></label>
        <label className="text-sm text-muted">Vendedora
          <select name="vendedora" defaultValue={sp.vendedora ?? ''} className={`${select} mt-1 block`}>
            <option value="">Todas</option>{data.filters.sellers.map((v) => <option key={v.id} value={v.id}>{v.name}</option>)}
          </select></label>
        <label className="text-sm text-muted">Canal
          <select name="canal" defaultValue={sp.canal ?? ''} className={`${select} mt-1 block`}>
            <option value="">Todos</option>{data.filters.channels.map((c) => <option key={c.key} value={c.key} disabled={!c.available}>{c.name}{c.available ? '' : ' (pronto)'}</option>)}
          </select></label>
        <button className="rounded-xl bg-ink px-5 py-2.5 text-surface">Filtrar</button>
      </form>

      <section className="mt-8 grid grid-cols-2 gap-3 lg:grid-cols-4" data-testid="sales-summary">
        {[['Ingresos', dinero(s.revenue)], ['Ventas', String(s.sales)], ['Pares', String(s.pairs)], ['Ticket promedio', dinero(s.avg_ticket)]].map(([k, v]) => (
          <div key={k} className="rounded-2xl border border-line bg-surface p-5"><div className="text-sm text-ink-2">{k}</div><div className="tabular mt-1 text-3xl font-semibold text-ink">{v}</div></div>
        ))}
      </section>
      <p className="mt-2 text-xs text-muted">Periodo: {data.from} a {data.to} · calculado solo con ventas registradas.</p>

      <section className="mt-6 overflow-x-auto rounded-3xl border border-line bg-surface">
        {data.items.length === 0 ? <p className="p-8 text-center text-ink-2">No hay ventas en este periodo.</p> : (
          <table className="w-full min-w-[820px] text-left">
            <thead className="bg-surface-2 text-xs uppercase tracking-wider text-muted">
              <tr><th className="px-4 py-3">Fecha</th><th className="px-3 py-3">Ubicación</th><th className="px-3 py-3">Vendedora</th><th className="px-3 py-3">Clienta</th>
                <th className="px-3 py-3 text-right">Pares</th><th className="px-3 py-3 text-right">Total</th><th className="px-3 py-3">Pago</th><th className="px-4 py-3">Estado</th></tr>
            </thead>
            <tbody className="divide-y divide-line">
              {data.items.map((v) => (
                <tr key={v.id} className="hover:bg-surface-2" data-testid="sale-row">
                  <td className="px-4 py-3"><Link href={`/ventas/${v.id}`} className="text-ink underline-offset-2 hover:underline">{fecha(v.occurred_at)}</Link></td>
                  <td className="px-3 py-3 text-ink-2">{v.location ?? '—'}</td>
                  <td className="px-3 py-3 text-ink-2">{v.seller}</td>
                  <td className="px-3 py-3">{v.customer ?? <span className="text-muted">Sin identificar</span>}</td>
                  <td className="tabular px-3 py-3 text-right">{v.pairs}</td>
                  <td className="tabular px-3 py-3 text-right font-medium text-ink">{dinero(v.total)}</td>
                  <td className="px-3 py-3 text-ink-2">{PAYMENT_LABEL[v.payment_method ?? ''] ?? '—'}</td>
                  <td className="px-4 py-3 text-sm"><span className="rounded-full bg-success-soft px-2.5 py-1 text-success">Completada</span>
                    {v.claim_pending && <span className="ml-2 text-muted">puntos por reclamar</span>}{v.self_sale && <span className="ml-2 text-muted">auto-venta</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
      <p className="mt-3 text-sm text-muted">{pares(s.pairs)} en {s.sales} {s.sales === 1 ? 'venta' : 'ventas'}.</p>
    </div>
  );
}
