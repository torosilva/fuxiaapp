'use client';
import { useState, useTransition } from 'react';
import Link from 'next/link';
import type { AdminItem, Block, Lesson } from '@/lib/academy';
import { CardView } from '../../../Card';
import { comment, decide, saveItem, saveLesson, submit } from '../../../actions';

const input = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-sm text-ink';
const btn = 'rounded-2xl bg-ink px-4 py-2.5 text-sm font-semibold text-surface disabled:opacity-50';

export function LessonEditor({ version, lesson }: { version: string; lesson: Lesson }) {
  const [blocks, setBlocks] = useState<Block[]>(lesson.blocks);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, start] = useTransition();
  const set = (k: number, f: Partial<Block>) => setBlocks((b) => b.map((x, i) => (i === k ? { ...x, ...f } : x)));
  return (
    <div className="mt-3 flex flex-col gap-3">
      {blocks.map((b, k) => (
        <div key={k} className="rounded-2xl border border-line p-3">
          {b.type === 'ficha' || b.type === 'ficha_talla' ? <CardView b={b} products={lesson.products} /> : (
            <>
              <label className="text-xs text-muted">Tarjeta {k + 1}</label>
              <textarea className={input} rows={3} value={b.text ?? ''} onChange={(e) => set(k, { text: e.target.value })} />
              <input className={input} value={b.source ?? ''} onChange={(e) => set(k, { source: e.target.value })} placeholder="Fuente: [PEDAGOGÍA], [SISTEMA]…" />
            </>
          )}
        </div>
      ))}
      <button disabled={busy} className={btn} onClick={() => start(async () => {
        const r = await saveLesson(version, lesson.id, lesson.title, lesson.minutes, blocks, Object.keys(lesson.products));
        setMsg(r.ok ? 'Guardado.' : String(r.error));
      })}>Guardar lección</button>
      {msg && <p className="text-xs text-muted">{msg}</p>}
    </div>
  );
}

export function ItemEditor({ version, item, editable }: { version: string; item: AdminItem; editable: boolean }) {
  const [prompt, setPrompt] = useState(item.prompt);
  const [explanation, setExplanation] = useState(item.explanation);
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, start] = useTransition();
  return (
    <div className={`rounded-2xl border p-3 text-sm ${item.status === 'bloqueada' ? 'border-danger' : 'border-line'}`}>
      <p className="text-xs text-muted">{item.key} · {item.area} · {item.uses.join(' + ')} · {item.source}{item.status === 'bloqueada' ? ' · BLOQUEADA' : ''}</p>
      {editable ? <textarea className={input} rows={2} value={prompt} onChange={(e) => setPrompt(e.target.value)} /> : <p className="font-semibold text-ink">{item.prompt}</p>}
      <ul className="mt-1 text-xs text-ink-2">{item.options.map((o) => <li key={o.id}>{o.id}) {o.text}</li>)}</ul>
      <p className="mt-1 text-xs text-success">Respuesta: {JSON.stringify(item.answer)}</p>
      {editable ? <textarea className={input} rows={2} value={explanation} onChange={(e) => setExplanation(e.target.value)} /> : <p className="text-xs text-muted">{item.explanation}</p>}
      {editable && (
        <div className="mt-2 flex gap-2">
          <button disabled={busy} className={btn} onClick={() => start(async () => { const r = await saveItem(version, item.id, { prompt, explanation }); setMsg(r.ok ? 'Guardado.' : String(r.error)); })}>Guardar</button>
          <button disabled={busy} className="rounded-2xl border border-line px-3 py-2 text-xs" onClick={() => start(async () => {
            const r = await saveItem(version, item.id, { status: item.status === 'ok' ? 'bloqueada' : 'ok' }); setMsg(r.ok ? 'Listo.' : String(r.error)); })}>
            {item.status === 'ok' ? 'Bloquear' : 'Desbloquear'}</button>
        </div>
      )}
      {msg && <p className="text-xs text-muted">{msg}</p>}
    </div>
  );
}

export function CommentBox({ version, lessonKey, comments }: { version: string; lessonKey: string; comments: { body: string; by: string; at: string }[] }) {
  const [body, setBody] = useState('');
  const [busy, start] = useTransition();
  return (
    <div className="mt-4">
      {comments.map((c, k) => <p key={k} className="text-xs text-ink-2">💬 <b>{c.by}</b>: {c.body}</p>)}
      <div className="mt-2 flex gap-2">
        <input className={input} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Comentario para esta lección" />
        <button disabled={busy || body.trim().length < 2} className="rounded-xl border border-line px-3 text-xs" onClick={() => start(async () => { const r = await comment(version, lessonKey, null, null, body); if (r.ok) setBody(''); })}>Enviar</button>
      </div>
    </div>
  );
}

export function Submit({ version }: { version: string }) {
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [busy, start] = useTransition();
  return (
    <section className="rounded-3xl border border-line bg-surface p-4">
      <p className="text-sm font-semibold text-ink">Enviar a revisión</p>
      <input className={input} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Qué cambió o por qué se envía" />
      <button disabled={busy || reason.trim().length < 3} className={`${btn} mt-2`} data-testid="academy-submit"
        onClick={() => start(async () => { const r = await submit(version, reason); setMsg(r.ok ? 'Enviado. Ya no se puede editar esta versión.' : String(r.error)); })}>Enviar</button>
      {msg && <p className="mt-1 text-xs text-muted">{msg}</p>}
    </section>
  );
}

export function Decide({ version }: { version: string }) {
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [mfa, setMfa] = useState(false);
  const [busy, start] = useTransition();
  const run = (approve: boolean) => start(async () => {
    const r = await decide(version, approve, reason);
    setMfa(r.error === 'mfa_required');
    setMsg(r.ok ? (r.status === 'publicado' ? `Publicado${r.self_approval ? ' (autoaprobación registrada)' : ''}.` : 'Devuelto a borrador.') : r.error === 'mfa_required' ? 'Falta la verificación en dos pasos.' : String(r.error));
  });
  return (
    <section className="rounded-3xl border border-gold bg-surface p-4" data-testid="academy-decide">
      <p className="text-sm font-semibold text-ink">Revisión: aprobar o devolver</p>
      <input className={input} value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Comentario (obligatorio para devolver)" />
      <div className="mt-2 flex gap-2">
        <button disabled={busy} className={btn} onClick={() => run(true)}>Aprobar y publicar</button>
        <button disabled={busy} className="rounded-2xl border border-line px-4 py-2.5 text-sm" onClick={() => run(false)}>Devolver con cambios</button>
      </div>
      {msg && <p className="mt-2 text-xs text-ink-2">{msg} {mfa && <Link className="underline" href="/academy/verificar">Verificar ahora</Link>}</p>}
    </section>
  );
}
