'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useState, useTransition } from 'react';
import { ColorDot } from '@/components/ProductImage';
import type { Reservation } from '@/lib/f360';
import { cancelReservationAction } from '../actions';

const STATUS: Record<Reservation['status'], { label: string; tone: string }> = {
  activa: { label: 'Apartado', tone: 'bg-gold-soft text-ink-2' }, vendida: { label: 'Vendido', tone: 'bg-success-soft text-success' },
  vencida: { label: 'Venció (2 h)', tone: 'bg-surface-2 text-muted' }, cancelada: { label: 'Cancelado', tone: 'bg-surface-2 text-muted' },
};
const CHANNEL = { app: 'App', web: 'Tienda en línea', tienda: 'En tienda' };

export function ReservationsClient({ rows }: { rows: Reservation[] }) {
  const router = useRouter();
  const [now, setNow] = useState(() => Date.now());
  const [cancel, setCancel] = useState<{ id: string; reason: string } | null>(null);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 30_000); return () => clearInterval(t); }, []);
  const left = (iso: string) => { const m = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000)); return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`; };
  const active = rows.filter((r) => r.status === 'activa');
  const rest = rows.filter((r) => r.status !== 'activa');
  const row = (r: Reservation) => (
    <div key={r.id} className="flex flex-wrap items-center gap-3 px-5 py-4" data-testid={`reservation-${r.status}`}>
      <div className="min-w-56 flex-1">
        <div className="flex items-center gap-2 text-ink">{r.product} · <ColorDot hex={r.color_hex} className="size-3" />{r.color} · talla <b>{r.size}</b></div>
        <div className="text-xs text-muted">{r.store} · {r.customer} (tel. ···{r.phone_last4}) · {CHANNEL[r.channel]}{r.closed_by ? ` · ${r.closed_by}` : ''}{r.closed_reason ? `: “${r.closed_reason}”` : ''}</div>
      </div>
      {r.status === 'activa' && <span className="tabular text-sm text-ink">Quedan <b>{left(r.expires_at)}</b></span>}
      <span className={`rounded-full px-3 py-1 text-xs ${STATUS[r.status].tone}`}>{STATUS[r.status].label}</span>
      {r.status === 'activa' && cancel?.id !== r.id && <button type="button" onClick={() => setCancel({ id: r.id, reason: '' })} className="text-sm text-muted underline">Cancelar</button>}
      {cancel?.id === r.id && (
        <div className="flex w-full flex-wrap gap-2">
          <input aria-label="Motivo de cancelación" value={cancel.reason} onChange={(e) => setCancel({ ...cancel, reason: e.target.value })} placeholder="Motivo (p. ej. la clienta avisó que no viene)" className="min-w-64 flex-1 rounded-xl border border-line bg-bg px-3 py-2 text-sm" />
          <button type="button" disabled={pending} onClick={() => start(async () => {
            const res = await cancelReservationAction(r.id, cancel.reason);
            setMsg(res.ok ? { ok: true, text: 'Apartado cancelado: el par ya está libre.' } : { ok: false, text: res.error }); if (res.ok) { setCancel(null); router.refresh(); }
          })} className="rounded-xl bg-ink px-3 py-2 text-sm text-surface">Cancelar apartado</button>
          <button type="button" onClick={() => setCancel(null)} className="text-sm text-muted">Volver</button>
        </div>
      )}
    </div>
  );
  return (
    <>
      {msg && <p className={`mt-4 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
      <h2 className="font-display mt-8 text-3xl text-ink">Activos <span className="tabular text-muted">{active.length}</span></h2>
      <div className="mt-3 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
        {active.length ? active.map(row) : <p className="p-6 text-ink-2">No hay apartados activos.</p>}
      </div>
      <h2 className="font-display mt-10 text-2xl text-ink">Últimos 7 días</h2>
      <div className="mt-3 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
        {rest.length ? rest.map(row) : <p className="p-6 text-ink-2">Sin historial.</p>}
      </div>
    </>
  );
}
