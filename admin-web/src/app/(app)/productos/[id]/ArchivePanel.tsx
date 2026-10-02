'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { ArchiveState } from '@/lib/f360';
import { setProductArchivedAction } from '../../actions';

// Archive = hide from every list, keep all history. The database decides whether it is allowed (blockers).
export function ArchivePanel({ productId, name, state }: { productId: string; name: string; state: ArchiveState }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const archived = state.status === 'archived';
  const save = () => start(async () => {
    setError(null);
    const r = await setProductArchivedAction(productId, !archived, reason);
    if (!r.ok) { setError(r.error); return; }
    setOpen(false); setReason('');
    if (archived) router.refresh(); else router.push('/productos');
  });
  return (
    <section className="mt-12 rounded-3xl border border-line bg-surface p-5" data-testid="archive-panel">
      <h2 className="font-display text-2xl text-ink">{archived ? 'Producto archivado' : 'Archivar producto'}</h2>
      {archived ? (
        <p className="mt-1 text-sm text-ink-2">No aparece en las listas. Su historial se conserva.{state.last_change && ` Lo archivó ${state.last_change.by}: “${state.last_change.reason}”.`}</p>
      ) : state.blockers.length ? (
        <>
          <p className="mt-1 text-sm text-ink-2">No se puede archivar todavía:</p>
          <ul className="mt-2 list-disc pl-5 text-sm text-muted">{state.blockers.map((b) => <li key={b}>{b}</li>)}</ul>
        </>
      ) : (
        <p className="mt-1 text-sm text-ink-2">Lo quita de Productos, Recibir, Mover y Homologación. No se borra nada y se puede reactivar.</p>
      )}
      {(archived || !state.blockers.length) && !open && (
        <button type="button" onClick={() => setOpen(true)} className="mt-4 rounded-full border border-ink px-5 py-2.5 text-sm text-ink hover:bg-ink hover:text-surface">
          {archived ? 'Reactivar' : `Archivar ${name}`}
        </button>
      )}
      {open && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <input aria-label="Motivo" value={reason} onChange={(e) => setReason(e.target.value)} placeholder={archived ? '¿Por qué regresa?' : '¿Por qué se archiva?'}
            className="min-w-64 flex-1 rounded-xl border border-line bg-bg px-3 py-2.5 text-sm outline-none focus:border-gold" />
          <button type="button" disabled={pending} onClick={save} className="rounded-xl bg-ink px-4 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : archived ? 'Reactivar' : 'Archivar'}</button>
          <button type="button" onClick={() => setOpen(false)} className="text-sm text-muted">Cancelar</button>
        </div>
      )}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
    </section>
  );
}
