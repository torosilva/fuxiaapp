'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { saveSkillAction, setSkillStatusAction } from '../actions';

export type SkillDetail = {
  can_edit: boolean;
  skill: { key: string; name: string; purpose: string; area: string; status: string; status_note: string | null };
  shown: { version: number; description: string; body: string; note: string; by: string; at: string } | null;
  versions: { version: number; note: string; by: string; at: string }[];
  status_changes: { before: string | null; after: string; note: string; by: string; at: string }[];
};

const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 outline-none focus:border-gold';

export function SkillEditor({ d, readOnly }: { d: SkillDetail; readOnly: boolean }) {
  const router = useRouter();
  const [edit, setEdit] = useState(false);
  const [desc, setDesc] = useState(d.shown?.description ?? '');
  const [body, setBody] = useState(d.shown?.body ?? '');
  const [note, setNote] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  const save = () => start(async () => {
    const r = await saveSkillAction({ key: d.skill.key, description: desc, body, note });
    setMsg(r.ok ? { ok: true, text: `Guardada como versión ${r.version}.` } : { ok: false, text: r.error });
    if (r.ok) { setEdit(false); setNote(''); router.refresh(); }
  });
  const status = (s: string) => start(async () => {
    const r = await setSkillStatusAction({ key: d.skill.key, status: s, note });
    setMsg(r.ok ? { ok: true, text: 'Estado actualizado.' } : { ok: false, text: r.error });
    if (r.ok) { setNote(''); router.refresh(); }
  });

  if (!d.shown) return <p className="mt-6 text-ink-2">Esta skill todavía no tiene contenido.</p>;
  return (
    <section className="mt-6 rounded-3xl border border-line bg-surface p-5" data-testid="skill-body">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-ink-2">Versión {d.shown.version} · {d.shown.by}</p>
        {!readOnly && !edit && <button type="button" onClick={() => setEdit(true)} className="rounded-full border border-line px-4 py-2 text-sm text-ink">Editar</button>}
      </div>
      {edit ? (
        <>
          <label className="mt-4 block text-sm text-ink-2">Cuándo usarla (descripción)
            <textarea aria-label="Descripción" value={desc} onChange={(e) => setDesc(e.target.value)} rows={3} maxLength={1024} className={input} /></label>
          <label className="mt-4 block text-sm text-ink-2">Instrucciones
            <textarea aria-label="Instrucciones" value={body} onChange={(e) => setBody(e.target.value)} rows={24} className={`${input} font-mono text-sm`} /></label>
        </>
      ) : (
        <>
          <p className="mt-4 text-sm text-ink">{d.shown.description}</p>
          <pre className="mt-4 max-h-[36rem] overflow-auto whitespace-pre-wrap rounded-2xl bg-bg p-4 font-mono text-sm text-ink">{d.shown.body}</pre>
        </>
      )}
      {!readOnly && (
        <div className="mt-4">
          <label className="block text-sm text-ink-2">Nota del cambio (obligatoria, queda en el historial)
            <input aria-label="Nota del cambio" value={note} onChange={(e) => setNote(e.target.value)} maxLength={300} className={input} /></label>
          {msg && <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
          <div className="mt-3 flex flex-wrap gap-2">
            {edit && <button type="button" disabled={pending || note.trim().length < 5} onClick={save} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar versión nueva'}</button>}
            {edit && <button type="button" onClick={() => { setEdit(false); setDesc(d.shown!.description); setBody(d.shown!.body); }} className="rounded-full border border-line px-5 py-2.5 text-sm text-ink">Cancelar</button>}
            {!edit && ['revisada', 'actualizar', 'archivada'].filter((s) => s !== d.skill.status).map((s) => (
              <button key={s} type="button" disabled={pending || note.trim().length < 5} onClick={() => status(s)}
                className="rounded-full border border-line px-4 py-2 text-sm text-ink disabled:opacity-40">Marcar como {s}</button>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}
