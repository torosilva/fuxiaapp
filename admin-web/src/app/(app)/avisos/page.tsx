import Link from 'next/link';
import { canWrite, getMe, getSyncOverview } from '@/lib/f360';
import { fecha } from '@/lib/format';
import { publisherAvailable } from '@/lib/env-guard';
import { ReconcileButton, ResolveIssue } from './AvisosClient';

const KIND: Record<string, string> = {
  oversell: 'Venta sin existencia', unknown_sku: 'Artículo no reconocido', sku_mismatch: 'SKU no coincide', stock_drift: 'Existencias distintas',
  push_failed: 'No se pudo actualizar la tienda', cancel_after_sale: 'Cancelación después de venta', refund_after_sale: 'Reembolso después de venta',
  webhook_rejected: 'Aviso rechazado',
};
const RESULT: Record<string, string> = {
  applied: 'procesado', duplicate_delivery: 'repetido (ignorado)', duplicate: 'sin cambios (ignorado)', stale: 'llegó tarde (ignorado)',
  not_paid: 'aún no pagado', rejected_signature: 'rechazado: firma inválida', error: 'error',
};
const STATUS: Record<string, string> = {
  pending: 'pendiente de pago', 'on-hold': 'en espera', processing: 'pagado', completed: 'completado', cancelled: 'cancelado',
  refunded: 'reembolsado', failed: 'pago fallido',
};
const resultLabel = (result: string, status: string | null) =>
  result === 'not_paid' && status && ['cancelled', 'refunded', 'failed'].includes(status) ? 'sin cambio de inventario (ver avisos)' : RESULT[result] ?? result;
const OUTCOME: Record<string, string> = {
  sold: 'vendido', oversold: 'sin existencia', legacy: 'producto anterior (no Fuxia 360)', unknown_sku: 'no reconocido', sku_mismatch: 'SKU no coincide', already_recorded: 'ya registrado',
};

export default async function Avisos({ searchParams }: { searchParams: Promise<{ ver?: string }> }) {
  const { ver } = await searchParams;
  const showResolved = ver === 'resueltos';
  const [me, data] = await Promise.all([getMe(), getSyncOverview(showResolved ? 'resolved' : 'open')]);
  const rec = data.last_reconciliation;
  const live = publisherAvailable();
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Avisos</h1>
      <p className="mt-2 text-ink-2">Lo que pasa entre Fuxia 360 y la tienda en línea. Si todo está bien, aquí no hay nada pendiente.</p>

      <div className="mt-6 grid gap-4 md:grid-cols-2">
        <section className={`rounded-3xl border p-5 ${rec && rec.drifted + rec.missing === 0 ? 'border-success/30 bg-success-soft' : 'border-line bg-surface'}`} data-testid="reconciliation">
          <p className="text-sm uppercase tracking-[0.15em] text-muted">Existencias Fuxia 360 ↔ tienda</p>
          {rec ? (
            <>
              <p className="mt-2 text-lg text-ink">{rec.drifted + rec.missing === 0
                ? `Todo coincide: ${rec.in_sync} de ${rec.checked} variaciones`
                : `${rec.drifted + rec.missing} de ${rec.checked} variaciones no coincidían (se corrigen solas)`}</p>
              <p className="mt-1 text-sm text-muted">Última revisión: {fecha(rec.at)}{rec.by ? ` · ${rec.by}` : ''} · {rec.target}</p>
            </>
          ) : <p className="mt-2 text-ink-2">Todavía no se ha revisado.</p>}
          {canWrite(me.role) && (live ? <ReconcileButton /> : (
            <p className="mt-3 text-sm text-ink-2" data-testid="sync-unavailable">La conexión con WooCommerce estará disponible en este ambiente cuando conectemos la tienda de pruebas.</p>
          ))}
        </section>
        <section className="rounded-3xl border border-line bg-surface p-5">
          <p className="text-sm uppercase tracking-[0.15em] text-muted">Actualizaciones hacia la tienda</p>
          <p className="mt-2 text-lg text-ink" data-testid="queue">{data.queue.pending === 0 ? 'Al día: nada pendiente' : `${data.queue.pending} pendiente${data.queue.pending === 1 ? '' : 's'}${data.queue.failing ? ` (${data.queue.failing} reintentando)` : ''}`}</p>
          <p className="mt-1 text-sm text-muted">Cada vez que cambian las existencias de Bodega CDMX, la tienda se actualiza sola.</p>
        </section>
      </div>

      <div className="mt-10 flex flex-wrap items-baseline justify-between gap-3">
        <h2 className="font-display text-3xl text-ink">{showResolved ? 'Resueltos' : `Pendientes (${data.open_count})`}</h2>
        <Link href={showResolved ? '/avisos' : '/avisos?ver=resueltos'} className="text-sm text-gold-strong hover:underline">{showResolved ? 'Ver pendientes' : 'Ver resueltos'}</Link>
      </div>
      <div className="mt-4 space-y-3" data-testid="issues">
        {data.issues.length === 0 ? (
          <p className="rounded-2xl border border-dashed border-line bg-surface p-6 text-ink-2">{showResolved ? 'No hay avisos resueltos.' : 'Nada pendiente. Todo está sincronizado.'}</p>
        ) : data.issues.map((i) => (
          <article key={i.id} className={`rounded-2xl border p-5 ${i.status === 'open' ? (i.kind === 'oversell' || i.kind.endsWith('_after_sale') ? 'border-danger/30 bg-danger-soft/40' : 'border-gold/40 bg-gold-soft/50') : 'border-line bg-surface'}`} data-kind={i.kind}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="text-sm font-semibold uppercase tracking-[0.12em] text-ink-2">{KIND[i.kind] ?? i.kind}</p>
              <p className="text-sm text-muted">{fecha(i.created_at)}{i.occurrences > 1 ? ` · ${i.occurrences} veces` : ''}</p>
            </div>
            <p className="mt-2 text-ink">{i.message}</p>
            <p className="mt-1 text-sm text-muted">
              {i.product_id && <Link href={`/productos/${i.product_id}`} className="text-gold-strong hover:underline">{i.variant_label ?? i.product_name}</Link>}
              {i.woo_order_id ? `${i.product_id ? ' · ' : ''}Pedido en línea #${i.woo_order_id}` : ''}
            </p>
            {i.status === 'resolved'
              ? <p className="mt-3 text-sm text-success">Resuelto por {i.resolved_by_name}{i.resolved_at ? `, ${fecha(i.resolved_at)}` : ''}{i.resolution_note ? ` — “${i.resolution_note}”` : ''}</p>
              : canWrite(me.role) && <ResolveIssue id={i.id} />}
          </article>
        ))}
      </div>

      <div className="mt-12 grid gap-8 lg:grid-cols-2">
        <section>
          <h2 className="font-display text-2xl text-ink">Pedidos recibidos de la tienda</h2>
          <ul className="mt-3 space-y-2" data-testid="recent-orders">
            {data.recent_orders.length === 0 ? <li className="text-sm text-muted">Todavía no llega ningún pedido.</li> : data.recent_orders.map((o, k) => (
              <li key={k} className="rounded-xl bg-surface px-4 py-3 text-sm">
                <span className="text-ink">{o.order ? `Pedido #${o.order}` : 'Aviso'}{o.status ? ` · ${STATUS[o.status] ?? o.status}` : ''}</span>
                <span className="text-muted"> — {resultLabel(o.result, o.status)}</span>
                {o.lines?.map((l, j) => <span key={j} className="block text-xs text-ink-2">{l.sku}{l.qty ? ` × ${l.qty}` : ''}: {OUTCOME[l.outcome] ?? l.outcome}</span>)}
                <span className="block text-xs text-muted">{fecha(o.at)}</span>
              </li>
            ))}
          </ul>
        </section>
        <section>
          <h2 className="font-display text-2xl text-ink">Actualizaciones de existencias</h2>
          <ul className="mt-3 space-y-2" data-testid="recent-pushes">
            {data.recent_pushes.length === 0 ? <li className="text-sm text-muted">Sin actualizaciones todavía.</li> : data.recent_pushes.map((p, k) => (
              <li key={k} className={`rounded-xl px-4 py-3 text-sm ${p.ok ? 'bg-surface' : 'bg-danger-soft'}`}>
                <span className="text-ink">{p.label}</span>
                <span className="text-muted"> — {p.ok ? (p.woo_before === p.pushed ? `tienda ya tenía ${p.pushed}` : `tienda ${p.woo_before ?? '—'} → ${p.pushed}`) : `falló: ${p.error}`}</span>
                <span className="block text-xs text-muted">Bodega CDMX: {p.ats ?? '—'} · {fecha(p.at)}</span>
              </li>
            ))}
          </ul>
        </section>
      </div>
    </div>
  );
}
