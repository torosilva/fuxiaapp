'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { voidHistSaleAction } from '../../actions';

// Correcting a load = void it (with a reason) and load it again. Inline confirm: no browser dialogs.
export function VoidHistButton({ id, label }: { id: string; label: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  if (!open) return <button type="button" onClick={() => setOpen(true)} className="rounded-full px-3 py-2 text-sm text-ink-2 ring-1 ring-line">Anular</button>;
  return (
    <div className="flex w-full flex-wrap items-center gap-2">
      <label className="sr-only" htmlFor={`void-${id}`}>Motivo para anular {label}</label>
      <input id={`void-${id}`} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="¿Por qué se anula?" className="min-w-0 flex-1 rounded-xl border border-line bg-surface px-3 py-2 text-[15px] outline-none focus:border-gold" />
      <button type="button" disabled={pending} onClick={() => start(async () => {
        const r = await voidHistSaleAction(id, reason);
        if (r.ok) { setOpen(false); router.refresh(); } else setError(r.error);
      })} className="rounded-full bg-danger px-4 py-2 text-sm text-surface disabled:opacity-50">Anular</button>
      <button type="button" onClick={() => { setOpen(false); setError(null); }} className="rounded-full px-3 py-2 text-sm text-ink-2">Cancelar</button>
      {error && <p role="alert" className="w-full text-sm text-danger">{error}</p>}
    </div>
  );
}
