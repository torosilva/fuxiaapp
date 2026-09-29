'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { reconcileNowAction, resolveSyncIssueAction } from '../actions';

export function ReconcileButton() {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [msg, setMsg] = useState<string | null>(null);
  return (
    <div className="mt-3">
      <button type="button" disabled={pending} onClick={() => start(async () => {
        setMsg(null);
        const r = await reconcileNowAction();
        setMsg(r.ok ? (r.data.drifted + r.data.missing === 0 ? `Listo: ${r.data.in_sync} de ${r.data.checked} coinciden.` : `Se encontraron ${r.data.drifted + r.data.missing} diferencias y se corrigieron.`) : r.error);
        router.refresh();
      })} className="rounded-2xl border border-ink bg-surface px-5 py-3 text-ink disabled:opacity-60">{pending ? 'Revisando…' : 'Revisar ahora'}</button>
      {msg && <p className="mt-2 text-sm text-ink-2" role="status">{msg}</p>}
    </div>
  );
}

export function ResolveIssue({ id }: { id: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (!open) return <button type="button" onClick={() => setOpen(true)} className="mt-3 text-sm text-gold-strong hover:underline">Marcar como resuelto</button>;
  return (
    <div className="mt-3 space-y-2">
      <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="¿Qué se hizo? (p. ej. se surtió desde producción)" aria-label="Qué se hizo"
        className="w-full rounded-xl border border-line bg-bg px-4 py-3 outline-none focus:border-gold" />
      {error && <p role="alert" className="text-sm text-danger">{error}</p>}
      <div className="flex gap-3">
        <button type="button" disabled={pending} onClick={() => start(async () => {
          const r = await resolveSyncIssueAction(id, note);
          if (!r.ok) { setError(r.error); return; }
          router.refresh();
        })} className="rounded-xl bg-ink px-4 py-2.5 text-surface disabled:opacity-60">Guardar</button>
        <button type="button" onClick={() => setOpen(false)} className="px-3 text-muted">Cancelar</button>
      </div>
    </div>
  );
}
