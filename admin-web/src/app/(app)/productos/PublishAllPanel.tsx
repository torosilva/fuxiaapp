'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { liveCandidatesAction, publishAllQueuedAction, setStoreVisibilityAction } from '../actions';

type Row = { id: string; name: string; state: 'pendiente' | 'publicando' | 'ok' | 'error'; error?: string };

// "Publicar todos los listos": one click, one product after the other (the owner's session; the database and the publisher
// re-check everything per product). Every product is created HIDDEN (draft) in the store; going live is a separate decision.
export function PublishAllPanel({ storeName }: { storeName: string }) {
  const router = useRouter();
  const [rows, setRows] = useState<Row[] | null>(null);
  const [running, setRunning] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const set = (i: number, patch: Partial<Row>) => setRows((r) => r && r.map((x, k) => (k === i ? { ...x, ...patch } : x)));

  const [liveConfirm, setLiveConfirm] = useState(false);
  const goLiveAll = async () => {
    setError(null); setRunning(true); setLiveConfirm(false);
    const c = await liveCandidatesAction();
    if (!c.ok) { setError(c.error); setRunning(false); return; }
    const list: Row[] = c.data.map((p) => ({ ...p, state: 'pendiente' }));
    setRows(list);
    for (let i = 0; i < list.length; i++) {
      set(i, { state: 'publicando' });
      const r = await setStoreVisibilityAction(list[i].id, 'publish');
      if (r.ok) set(i, { state: 'ok' }); else set(i, { state: 'error', error: r.error });
    }
    setRunning(false);
    router.refresh();
  };

  // Creates the jobs and starts the SERVER queue (progress in “Publicando en la tienda”; the page can be closed).
  const run = async () => {
    setError(null); setRunning(true);
    const r = await publishAllQueuedAction();
    setRunning(false);
    if (!r.ok) { setError(r.error); return; }
    setError(r.data.queued ? null : 'No hay modelos listos sin publicar.');
    router.refresh();
  };

  const done = rows?.filter((r) => r.state === 'ok').length ?? 0;
  const failed = rows?.filter((r) => r.state === 'error').length ?? 0;
  return (
    <div className="rounded-3xl border border-line bg-surface p-5" data-testid="publish-all">
      <p className="text-lg text-ink">Publicar en {storeName}</p>
      <p className="mt-1 text-sm text-ink-2">Publica <strong>todos los modelos listos</strong> que todavía no están en la tienda. Se crean <strong>ocultos (borrador)</strong>: nadie los ve hasta que en cada modelo elijas “Publicar en vivo”.</p>
      {!rows && !liveConfirm && (
        <div className="mt-4 flex flex-wrap gap-3">
          <button type="button" disabled={running} onClick={run} className="rounded-2xl bg-ink px-6 py-3.5 text-surface disabled:opacity-40">{running ? 'Buscando…' : 'Publicar todos los listos (borrador)'}</button>
          <button type="button" disabled={running} onClick={() => setLiveConfirm(true)} className="rounded-2xl bg-success px-6 py-3.5 text-surface disabled:opacity-40" data-testid="go-live-all">Poner EN VIVO todo lo publicado</button>
        </div>
      )}
      {liveConfirm && (
        <div className="mt-4 rounded-2xl border border-gold/40 bg-gold-soft p-4">
          <p className="text-ink">Todo lo que Fuxia 360 ya publicó en {storeName} se va a <strong>mostrar a las clientas</strong>, y los <strong>productos viejos</strong> de esos modelos salen del catálogo (su liga sigue funcionando). Se puede revertir modelo por modelo con “Ocultar de la tienda”.</p>
          <div className="mt-3 flex gap-3">
            <button type="button" onClick={goLiveAll} className="rounded-2xl bg-ink px-6 py-3.5 text-surface">Sí, poner todo en vivo</button>
            <button type="button" onClick={() => setLiveConfirm(false)} className="rounded-2xl px-4 text-muted">Cancelar</button>
          </div>
        </div>
      )}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
      {rows && (
        <div className="mt-4">
          <p className="text-ink">{running ? `Procesando… ${done + failed} de ${rows.length}` : rows.length ? `Listo: ${done} correctos${failed ? `, ${failed} con error (puedes reintentar en su ficha)` : ''}.` : 'No hay modelos pendientes.'}</p>
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
