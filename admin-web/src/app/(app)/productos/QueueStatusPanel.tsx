'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { kickQueueAction, queueStatusAction } from '../actions';
import type { QueueStatus } from '@/lib/f360';

// Progress of the SERVER publishing queue — it keeps going with this page closed; this box just reads it every 8 s.
export function QueueStatusPanel({ initial, storeName }: { initial: QueueStatus | null; storeName: string }) {
  const router = useRouter();
  const [q, setQ] = useState<QueueStatus | null>(initial);
  const [msg, setMsg] = useState<string | null>(null);
  useEffect(() => {
    const id = setInterval(async () => {
      const r = await queueStatusAction();
      if (r.ok) {
        setQ((prev) => { if (prev && prev.queued + prev.running > 0 && r.data.queued + r.data.running === 0) router.refresh(); return r.data; });
        if (r.data.queued > 0 && r.data.running === 0) await kickQueueAction();   // the chain was cut (time limit, network): resume it
      }
    }, 8000);
    return () => clearInterval(id);
  }, [router]);
  if (!q) return null;
  const busy = q.queued + q.running > 0;
  return (
    <div className={`rounded-3xl border p-5 ${busy ? 'border-gold/40 bg-gold-soft' : 'border-line bg-surface'}`} data-testid="queue-status">
      <p className="text-lg text-ink">{busy ? `Publicando en ${storeName}…` : `${storeName}`}</p>
      <div className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-sm text-ink-2">
        <span>En cola: <strong className="text-ink">{q.queued}</strong></span>
        <span>Publicando ahora: <strong className="text-ink">{q.now ?? '—'}</strong></span>
        <span>Terminados hoy: <strong className="text-success">{q.succeeded_today}</strong></span>
        <span>Con error hoy: <strong className={q.failed_today ? 'text-danger' : 'text-ink'}>{q.failed_today}</strong></span>
        <span>En la tienda: <strong className="text-ink">{q.published}</strong> ({q.live} en vivo)</span>
      </div>
      {busy && <p className="mt-2 text-sm text-ink-2">Esto corre en el servidor: puedes cerrar la página y volver cuando quieras.</p>}
      {busy && (
        <button type="button" onClick={async () => { const r = await kickQueueAction(); setMsg(r.ok ? 'Cola reactivada.' : r.error); }}
          className="mt-3 rounded-full px-4 py-2 text-sm text-ink ring-1 ring-line">¿Parece detenido? Reactivar</button>
      )}
      {msg && <p className="mt-2 text-sm text-ink-2">{msg}</p>}
    </div>
  );
}
