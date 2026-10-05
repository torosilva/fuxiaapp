'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { openingSetSimpleAction } from '../actions';

// Mario 2026-10-05 (b): an open double count can become ONE count (sizes with count 1 become final). Owner only.
export function SetSimpleButton({ id }: { id: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  return (
    <div className="mt-3">
      <button type="button" disabled={pending} onClick={() => start(async () => {
        const r = await openingSetSimpleAction(id);
        if (r.ok) router.refresh(); else setError(r.error);
      })} className="rounded-full border border-line bg-surface px-4 py-2 text-sm text-ink-2 disabled:opacity-50">
        {pending ? 'Cambiando…' : 'Cambiar a un solo conteo'}
      </button>
      {error && <p role="alert" className="mt-2 text-sm text-danger">{error}</p>}
    </div>
  );
}
