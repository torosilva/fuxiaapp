import Link from 'next/link';
import { IconMove, IconTruck } from '@/components/icons';
import { TransferStatus } from '@/components/TransferStatus';
import { canRequestTransfer, getMe, listTransfers, type Transfer, type TransferView } from '@/lib/f360';
import { fecha, pares } from '@/lib/format';

const TABS: { view: Exclude<TransferView, 'all'>; label: string; empty: string }[] = [
  { view: 'requested', label: 'Solicitadas', empty: 'No hay solicitudes pendientes.' },
  { view: 'in_transit', label: 'En camino', empty: 'No hay mercancía en camino.' },
  { view: 'received', label: 'Recibidas', empty: 'Todavía no se ha recibido ninguna transferencia.' },
  { view: 'with_difference', label: 'Con diferencia', empty: 'No hay diferencias pendientes.' },
];
const VIEW: Record<string, TransferView> = { solicitadas: 'requested', 'en-camino': 'in_transit', recibidas: 'received', diferencias: 'with_difference' };
const SLUG: Record<string, string> = { requested: 'solicitadas', in_transit: 'en-camino', received: 'recibidas', with_difference: 'diferencias' };

function TransferCard({ t }: { t: Transfer }) {
  const pairs = t.status === 'requested' || t.status === 'cancelled' ? t.totals.requested : t.totals.sent;
  const when = t.status === 'in_transit' ? `Enviada ${fecha(t.sent_at!)} por ${t.sent_by_name}` : t.received_at ? `Recibida ${fecha(t.received_at)} por ${t.received_by_name}`
    : t.cancelled_at ? `Cancelada ${fecha(t.cancelled_at)}` : `Pedida ${fecha(t.requested_at)} por ${t.requested_by_name}`;
  return (
    <Link href={`/transferencias/${t.id}`} className="block rounded-2xl border border-line bg-surface p-4 transition hover:border-gold/40 md:p-5" data-testid="transfer-card">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full bg-gold-soft text-gold-strong">{t.status === 'in_transit' ? <IconTruck className="size-5" /> : <IconMove className="size-5" />}</span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2"><span className="font-medium text-ink">{t.from.name} → {t.to.name}</span><TransferStatus status={t.status} /></div>
          <p className="mt-0.5 text-sm text-muted">{t.number} · {pares(pairs)} · {when}</p>
          {t.status === 'with_difference' && <p className="mt-2 text-sm text-danger">Faltan {pares(t.totals.outstanding ?? 0)}: siguen identificados hasta que operación los resuelva.</p>}
        </div>
      </div>
    </Link>
  );
}

export default async function Transferencias({ searchParams }: { searchParams: Promise<{ vista?: string }> }) {
  const sp = await searchParams;
  const view = VIEW[sp.vista ?? ''] ?? 'requested';
  const [me, data] = await Promise.all([getMe(), listTransfers(view)]);
  const tab = (active: boolean) => `whitespace-nowrap rounded-full px-4 py-2.5 text-[15px] transition ${active ? 'bg-ink text-surface' : 'text-ink-2 hover:bg-surface-2'}`;
  const count: Record<string, number> = { requested: data.counts.requested, in_transit: data.counts.in_transit, with_difference: data.counts.with_difference };
  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <h1 className="font-display text-5xl text-ink">Transferencias</h1>
        {canRequestTransfer(me.role) && <Link href="/mover" className="rounded-2xl bg-ink px-5 py-3 text-surface hover:bg-ink-2">Mover inventario</Link>}
      </div>
      <div className="mt-6 flex max-w-full gap-1 overflow-x-auto rounded-full border border-line bg-surface p-1 md:inline-flex">
        {TABS.map((t) => (
          <Link key={t.view} href={`/transferencias?vista=${SLUG[t.view]}`} className={tab(t.view === view)}>
            {t.label}{count[t.view] ? <span className="ml-1.5 tabular opacity-70">{count[t.view]}</span> : null}
          </Link>
        ))}
      </div>
      {view === 'in_transit' && <p className="mt-4 text-sm text-muted">Lo que va en camino no está disponible en ninguna ubicación ni se puede vender hasta que el destino confirme que llegó.</p>}
      <section className="mt-6 space-y-3">
        {data.items.length === 0 ? <p className="rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">{TABS.find((t) => t.view === view)?.empty}</p>
          : data.items.map((t) => <TransferCard key={t.id} t={t} />)}
      </section>
    </div>
  );
}
