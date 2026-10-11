'use client';
import { useEffect, useState, useTransition } from 'react';
import { decideDiscountAction, discountInboxAction, type DiscountInbox as Inbox } from '../actions';
import { fecha, precio } from '@/lib/format';

// "Descuentos por aprobar": a seller asked for more than 10 % and Carolina is not in the store. Only approvers see this
// (approval scope 'store_discount'); it refreshes every 10 s while open. The seller's phone shows the answer by itself.
export function DiscountInbox({ initial }: { initial: Inbox }) {
  const [data, setData] = useState(initial);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  useEffect(() => {
    const t = setInterval(() => { discountInboxAction().then((r) => { if (r.ok) setData(r.data); }); }, 10000);
    return () => clearInterval(t);
  }, []);
  if (!data.can_approve) return null;

  const decide = (id: string, approve: boolean) => start(async () => {
    setError(null);
    const r = await decideDiscountAction(id, approve, notes[id] ?? '');
    if (!r.ok) setError(r.error);
    const again = await discountInboxAction();
    if (again.ok) setData(again.data);
  });

  return (
    <section className="mt-6 rounded-3xl border border-gold/40 bg-gold-soft p-5" data-testid="discount-inbox">
      <p className="text-sm uppercase tracking-[0.15em] text-muted">Descuentos por aprobar</p>
      {data.pending.length === 0 ? <p className="mt-2 text-ink-2">Nada pendiente. Cuando una vendedora pida más de 10%, aparece aquí.</p> : (
        <ul className="mt-3 space-y-3">
          {data.pending.map((q) => (
            <li key={q.id} className="rounded-2xl border border-line bg-surface p-4">
              <p className="text-lg text-ink"><b>{q.seller}</b> · {q.location} pide <b>{q.pct}%</b></p>
              <p className="mt-1 text-ink-2">{q.summary}</p>
              <p className="tabular mt-1 text-ink">{precio(q.gross_total)} → <b>{precio(q.net_total)}</b></p>
              {q.reason && <p className="mt-1 text-sm text-ink-2">Motivo: {q.reason}</p>}
              <p className="mt-1 text-xs text-muted">Pedido {fecha(q.created_at)} · vence {fecha(q.expires_at)}</p>
              <input value={notes[q.id] ?? ''} onChange={(e) => setNotes({ ...notes, [q.id]: e.target.value })} maxLength={200} placeholder="Nota para la vendedora (opcional)"
                className="mt-3 w-full rounded-xl border border-line bg-bg px-3 py-2 text-ink outline-none focus:border-gold" />
              <div className="mt-3 flex gap-2">
                <button type="button" disabled={pending} onClick={() => decide(q.id, true)} className="rounded-2xl bg-ink px-5 py-2.5 text-surface disabled:opacity-60">Aprobar</button>
                <button type="button" disabled={pending} onClick={() => decide(q.id, false)} className="rounded-2xl border border-line px-5 py-2.5 text-ink-2 disabled:opacity-60">No aprobar</button>
              </div>
            </li>
          ))}
        </ul>
      )}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
      {data.recent && data.recent.length > 0 && (
        <details className="mt-4 text-sm text-ink-2">
          <summary className="cursor-pointer text-muted">Últimos 7 días</summary>
          <ul className="mt-2 space-y-1">
            {data.recent.map((r) => (
              <li key={r.id}>{fecha(r.at)} · {r.seller} · {r.location} · {r.pct}% · {precio(r.net_total)} · {
                { approved: 'aprobado', used: 'aprobado y vendido', rejected: 'no aprobado', expired: 'venció' }[r.status] ?? r.status}{r.via === 'pin' ? ' (PIN en tienda)' : ''}{r.decided_by ? ` · ${r.decided_by}` : ''}</li>
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}
