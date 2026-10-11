'use client';
import { useState, useTransition } from 'react';
import { newDraft } from '../actions';

export function NewDraftButton({ course }: { course: string }) {
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, start] = useTransition();
  return (
    <div className="text-right">
      <button disabled={busy} onClick={() => start(async () => { const r = await newDraft(course); setMsg(r.ok ? 'Borrador creado.' : String(r.error)); })}
        className="rounded-xl border border-line px-3 py-1.5 text-xs font-semibold text-ink disabled:opacity-50">Nueva versión</button>
      {msg && <p className="mt-1 text-xs text-muted">{msg}</p>}
    </div>
  );
}
