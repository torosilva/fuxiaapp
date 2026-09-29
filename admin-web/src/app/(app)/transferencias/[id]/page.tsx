import Link from 'next/link';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconBack, IconTruck } from '@/components/icons';
import { TransferStatus } from '@/components/TransferStatus';
import { getTransfer, type TransferHistory } from '@/lib/f360';
import { fecha, pares } from '@/lib/format';
import { TransferActions } from './TransferActions';

const ACTION: Record<TransferHistory['action'], string> = { request: 'solicitó', cancel: 'canceló', send: 'envió', receive: 'confirmó la recepción', resolve: 'resolvió la diferencia' };

export default async function TransferDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const t = await getTransfer(id);
  const showSent = t.status !== 'requested' && t.status !== 'cancelled';
  const showReceived = ['received', 'with_difference', 'closed'].includes(t.status);
  const showGap = t.status === 'with_difference' || t.status === 'closed';
  return (
    <div className="mx-auto max-w-3xl">
      <Link href="/transferencias" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Transferencias</Link>
      <div className="mt-6 flex flex-wrap items-center gap-3"><p className="text-xs uppercase tracking-[0.25em] text-gold">Transferencia {t.number}</p><TransferStatus status={t.status} /></div>
      <h1 className="font-display mt-2 flex flex-wrap items-center gap-3 text-5xl leading-tight text-ink">{t.from.name}<IconTruck className="size-8 text-gold-strong" />{t.to.name}</h1>
      {t.note && <p className="mt-4 rounded-2xl bg-surface-2 px-5 py-4 text-ink-2">“{t.note}”</p>}

      {t.status === 'in_transit' && (
        <p className="mt-6 rounded-2xl bg-gold-soft px-5 py-4 text-ink-2">{pares(t.totals.sent)} salieron de {t.from.name} y van <b>en camino</b>. No están disponibles en ninguna ubicación: {t.to.name} los suma cuando confirme que llegaron.</p>
      )}
      {t.status === 'with_difference' && (
        <p className="mt-6 rounded-2xl bg-danger-soft px-5 py-4 text-danger">Llegaron {t.totals.received} de {t.totals.sent}. Faltan {pares(t.totals.outstanding ?? 0)}: siguen registrados <b>en camino</b> a nombre de esta transferencia hasta que operación indique si regresan al origen o se dan de baja.</p>
      )}

      <div className="mt-6 overflow-x-auto rounded-3xl border border-line bg-surface">
        <table className="w-full min-w-[520px] text-left">
          <thead className="bg-surface-2 text-xs uppercase tracking-wider text-muted">
            <tr><th className="px-4 py-3">Producto</th><th className="px-3 py-3 text-right">Pedido</th>{showSent && <th className="px-3 py-3 text-right">Enviado</th>}
              {showReceived && <th className="px-3 py-3 text-right">Recibido</th>}{showGap && <th className="px-4 py-3 text-right">Falta</th>}</tr>
          </thead>
          <tbody className="divide-y divide-line">
            {t.lines.map((l) => (
              <tr key={l.variant_id} className="tabular">
                <td className="px-4 py-3"><div className="flex items-center gap-3">
                  <div className="size-10 shrink-0 overflow-hidden rounded-lg"><ProductImage path={l.image_path} name={l.product_name} /></div>
                  <div><div className="font-medium text-ink">{l.product_name}</div><div className="flex items-center gap-1.5 text-sm text-muted"><ColorDot hex={l.color_hex} className="size-3" />{l.color} · Talla {l.size}</div></div>
                </div></td>
                <td className="px-3 py-3 text-right text-lg">{l.requested}</td>
                {showSent && <td className="px-3 py-3 text-right text-lg">{l.sent ?? 0}</td>}
                {showReceived && <td className={`px-3 py-3 text-right text-lg ${(l.received ?? 0) < (l.sent ?? 0) ? 'font-semibold text-danger' : ''}`}>{l.received ?? 0}</td>}
                {showGap && <td className="px-4 py-3 text-right text-sm">{l.outstanding > 0 ? <span className="font-semibold text-danger">{l.outstanding}</span> : null}
                  {l.returned > 0 && <div className="text-muted">{l.returned} regresó</div>}{l.written_off > 0 && <div className="text-muted">{l.written_off} baja</div>}</td>}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <TransferActions t={t} />

      <section className="mt-10">
        <h2 className="font-display text-3xl text-ink">Historial</h2>
        <ol className="mt-4 space-y-3 border-l border-line pl-5">
          {(t.history ?? []).map((h, i) => (
            <li key={i} className="relative">
              <span className="absolute -left-[26px] top-1.5 size-2.5 rounded-full bg-gold" />
              <p className="text-ink"><b>{h.actor_name}</b> {ACTION[h.action]}{h.lines.length ? ` · ${pares(h.lines.reduce((a, l) => a + l.quantity, 0))}` : ''}</p>
              <p className="text-sm text-muted">{fecha(h.at)}{h.reason ? ` · “${h.reason}”` : ''}</p>
              {h.action === 'resolve' && <p className="text-sm text-ink-2">{h.lines.map((l) => `${l.label}: ${l.quantity} ${l.action === 'return' ? 'regresan al origen' : 'baja'}`).join(' · ')}</p>}
            </li>
          ))}
        </ol>
        <p className="mt-6 text-sm text-muted">Cada paso queda registrado y no se puede modificar.</p>
      </section>
    </div>
  );
}
