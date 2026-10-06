'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { publishAction, publishCandidatesAction } from '../actions';

type Row = { id: string; name: string; state: 'pendiente' | 'publicando' | 'ok' | 'error'; error?: string };

// "Publicar todos los listos": one click, one product after the other (the owner's session; the database and the publisher
// re-check everything per product). Every product is created HIDDEN (draft) in the store; going live is a separate decision.
export function PublishAllPanel({ storeName }: { storeName: string }) {
  const router = useRouter();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (i: number, patch: Partial<Row>) => setRows((r) => r && r.map((x, k) => (k === i ? { ...x, ...patch } : x)));

  const run = async () => {
    setError(null); setRunning(true);
    const c = await publishCandidatesAction();
    if (!c.ok) { setError(c.error); setRunning(false); return; }
    const list: Row[] = c.data.map((p) => ({ ...p, state: 'pendiente' }));
    setRows(list);
    for (let i = 0; i < list.length; i++) {
      set(i, { state: 'publicando' });
      const r = await publishAction(list[i].id, crypto.randomUUID());
      if (r.ok && r.data.status === 'succeeded') set(i, { state: 'ok' });
      else set(i, { state: 'error', error: r.ok ? (r.data.error ?? r.data.status) : r.error });
    }
    setRunning(false);
    router.refresh();
  };

  const done = rows?.filter((r) => r.state === 'ok').length ?? 0;
  const failed = rows?.filter((r) => r.state === 'error').length ?? 0;
  return (
    <div className="rounded-3xl border border-line bg-surface p-5" data-testid="publish-all">
      <p className="text-lg text-ink">Publicar en {storeName}</p>
      <p className="mt-1 text-sm text-ink-2">Publica <strong>todos los modelos listos</strong> que todavía no están en la tienda. Se crean <strong>ocultos (borrador)</strong>: nadie los ve hasta que en cada modelo elijas “Publicar en vivo”.</p>
      {!rows && <button type="button" disabled={running} onClick={run} className="mt-4 rounded-2xl bg-ink px-6 py-3.5 text-surface disabled:opacity-40">{running ? 'Buscando modelos listos…' : 'Publicar todos los listos'}</button>}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
      {rows && (
        <div className="mt-4">
          <p className="text-ink">{running ? `Publicando… ${done + failed} de ${rows.length}` : rows.length ? `Listo: ${done} publicados${failed ? `, ${failed} con error (puedes reintentar en su ficha)` : ''}.` : 'No hay modelos listos sin publicar.'}</p>
          <ul className="mt-3 max-h-80 space-y-1 overflow-auto text-sm">
            {rows.map((r) => (
              <li key={r.id} className={r.state === 'error' ? 'text-danger' : r.state === 'ok' ? 'text-success' : 'text-ink-2'}>
                {r.state === 'ok' ? '✓' : r.state === 'error' ? '✕' : r.state === 'publicando' ? '…' : '·'} <a href={`/productos/${r.id}`} className="hover:underline">{r.name}</a>{r.error ? ` — ${r.error}` : ''}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
