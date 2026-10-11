'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { updateProductAction } from '../../actions';

// Product title with "Cambiar nombre" (Mario 2026-10-11, same pattern as the colour rename). The server keeps code and SKUs;
// the new name goes to the store with the usual sync (the store address does not change).
export function ProductName({ productId, name, canEdit }: { productId: string; name: string; canEdit: boolean }) {
  const router = useRouter();
  const [value, setValue] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const save = () => start(async () => {
    setError(null);
    const next = (value ?? '').trim();
    if (!next) { setError('Escribe el nombre del producto.'); return; }
    if (next === name) { setValue(null); return; }
    const r = await updateProductAction(productId, { name: next });
    if (!r.ok) { setError(r.error); return; }
    setValue(null);
    router.refresh();
  });

  if (value === null) {
    return (
      <div className="mt-2">
        <h1 className="font-display break-words text-5xl text-ink md:text-6xl">{name}</h1>
        {canEdit && <button type="button" onClick={() => setValue(name)} className="mt-1 text-sm text-muted underline decoration-line underline-offset-4">Cambiar nombre</button>}
      </div>
    );
  }
  return (
    <div className="mt-2">
      <div className="flex flex-wrap items-center gap-2">
        <input aria-label="Nuevo nombre del producto" value={value} autoFocus disabled={pending} onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') save(); if (e.key === 'Escape') { setValue(null); setError(null); } }}
          className="min-w-0 flex-1 rounded-xl border border-line bg-bg px-4 py-3 text-2xl text-ink outline-none focus:border-gold" />
        <button type="button" onClick={save} disabled={pending} className="rounded-2xl bg-ink px-5 py-3 text-surface disabled:opacity-60">{pending ? 'Guardando…' : 'Guardar'}</button>
        <button type="button" onClick={() => { setValue(null); setError(null); }} disabled={pending} className="px-2 text-muted">Cancelar</button>
      </div>
      <p className="mt-2 text-sm text-muted">El nombre nuevo también se verá en la tienda. El código y los SKU no cambian.</p>
      {error && <p role="alert" className="mt-2 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
    </div>
  );
}
