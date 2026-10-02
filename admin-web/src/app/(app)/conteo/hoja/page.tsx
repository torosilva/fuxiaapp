import { redirect } from 'next/navigation';
import { canWrite, getMe, getOpeningSheet, getOpeningState } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { PrintButton } from './PrintButton';

// Printable count sheet: model → colour → one box per size, to count on paper and type in later.
export default async function HojaConteo() {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const state = await getOpeningState();
  if (!state.count || state.count.status === 'cancelado') redirect('/conteo');
  const sheet = await getOpeningSheet(state.count.id, 'conteo1');
  return (
    <div className="hoja">
      <style>{`@media print { aside, header, nav, .no-print, body > div.fixed { display: none !important } main { max-width: none !important; padding: 0 !important } body { background: #fff } .hoja section { break-inside: avoid } }`}</style>
      <div className="no-print mb-4 flex items-center justify-between"><h1 className="font-display text-4xl text-ink">Hoja de conteo</h1><PrintButton /></div>
      <p className="text-sm text-ink-2">{state.count.location} · {fecha(state.count.started_at)} · Contó: ____________________ · Ronda: 1 / 2 / reconteo</p>
      <div className="mt-4 grid gap-3">
        {sheet.models.map((m) => (
          <section key={m.product_id} className="rounded-xl border border-line bg-surface p-3">
            <h2 className="text-lg font-semibold text-ink">{m.model}</h2>
            <table className="mt-1 w-full text-sm">
              <tbody>{m.colors.map((c) => (
                <tr key={c.color} className="border-t border-line">
                  <td className="w-48 py-2 pr-2 text-ink-2">{c.color}</td>
                  {c.sizes.map((s) => <td key={s.variant_id} className="px-1 py-2 text-center"><div className="text-[11px] text-muted">{s.size}</div><div className="mx-auto mt-1 h-8 w-12 rounded border border-ink/40" /></td>)}
                </tr>))}
              </tbody>
            </table>
          </section>
        ))}
      </div>
      <p className="mt-4 text-xs text-muted">Pares sin ficha (no aparecen arriba): descripción · talla · pares ______________________________________________</p>
    </div>
  );
}
