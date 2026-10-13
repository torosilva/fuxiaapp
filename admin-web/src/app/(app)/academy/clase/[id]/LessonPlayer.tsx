'use client';
import Link from 'next/link';
import { useEffect, useState, useTransition } from 'react';
import type { LessonView, PracticeItem } from '@/lib/academy';
import { CardView } from '../../Card';
import { answer, saveProgress } from '../../actions';

// Card by card. Progress is saved on every "Siguiente" and resumes on the same card. Practice answers are graded by the server.
export function LessonPlayer({ view }: { view: LessonView }) {
  const { lesson, practice } = view;
  const total = lesson.blocks.length;
  const [i, setI] = useState(Math.min(view.progress?.card_index ?? 0, total));
  const [, start] = useTransition();
  const go = (n: number) => { setI(n); start(() => { void saveProgress(lesson.id, n, n >= total && practice.length === 0); }); };
  const finished = i >= total;
  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between text-xs text-muted">
        <Link href="/academy">← Academy</Link>
        <span>{Math.min(i + 1, total)} de {total}</span>
      </div>
      <div className="h-1.5 rounded-full bg-surface-2"><div className="h-1.5 rounded-full bg-gold" style={{ width: `${(100 * Math.min(i, total)) / total}%` }} /></div>
      <h1 className="font-display text-3xl text-ink">{lesson.title}</h1>
      {!finished ? (
        <section className="min-h-64 rounded-3xl border border-line bg-surface p-5" data-testid="academy-card">
          <CardView b={lesson.blocks[i]} products={lesson.products} />
        </section>
      ) : (
        <Practice items={practice} lessonId={lesson.id} total={total} next={view.next} />
      )}
      {!finished && (
        <div className="grid grid-cols-2 gap-3">
          <button disabled={i === 0} onClick={() => go(i - 1)} className="min-h-12 rounded-2xl border border-line bg-surface text-sm font-semibold text-ink disabled:opacity-40">Anterior</button>
          <button onClick={() => go(i + 1)} className="min-h-12 rounded-2xl bg-ink text-sm font-semibold text-surface" data-testid="academy-next">Siguiente</button>
        </div>
      )}
    </div>
  );
}

function Practice({ items, lessonId, total, next }: { items: PracticeItem[]; lessonId: string; total: number; next: string | null }) {
  const [done, setDone] = useState<Record<string, { correct: boolean; explanation: string; source: string }>>({});
  const all = items.every((q) => done[q.id]);
  useEffect(() => { if (all) void saveProgress(lessonId, total, true); }, [all, lessonId, total]);
  return (
    <section className="flex flex-col gap-4">
      {items.length > 0 && <p className="text-sm text-muted">Práctica (no cuenta para ningún certificado)</p>}
      {items.map((q) => <Question key={q.id} q={q} result={done[q.id]} onResult={(r) => setDone((d) => ({ ...d, [q.id]: r }))} />)}
      {all && (
        <div className="rounded-3xl border border-line bg-success-soft p-5 text-sm text-ink" data-testid="academy-lesson-done">
          ✓ Lección terminada.
          <div className="mt-3 flex gap-3">
            <Link href="/academy" className="rounded-2xl border border-line bg-surface px-4 py-2 font-semibold">Inicio</Link>
            {next && <Link href={`/academy/clase/${next}`} className="rounded-2xl bg-ink px-4 py-2 font-semibold text-surface">Siguiente lección</Link>}
          </div>
        </div>
      )}
    </section>
  );
}

function Question({ q, result, onResult }: { q: PracticeItem; result?: { correct: boolean; explanation: string; source: string }; onResult: (r: { correct: boolean; explanation: string; source: string }) => void }) {
  const [sel, setSel] = useState<string[]>([]);
  const [busy, start] = useTransition();
  const options = q.kind === 'vf' ? [{ id: 'true', text: 'Verdadero' }, { id: 'false', text: 'Falso' }] : q.options;
  const toggle = (id: string) => setSel((s) => q.kind === 'varias' || q.kind === 'ordenar' ? (s.includes(id) ? s.filter((x) => x !== id) : [...s, id]) : [id]);
  const payload = () => q.kind === 'opcion' ? { choice: sel[0] } : q.kind === 'vf' ? { value: sel[0] === 'true' } : q.kind === 'varias' ? { choices: sel } : { order: sel };
  return (
    <div className="rounded-3xl border border-line bg-surface p-5" data-testid="academy-question">
      <p className="font-semibold text-ink">{q.prompt}</p>
      {q.kind === 'ordenar' && <p className="mt-1 text-xs text-muted">Toca los pasos en orden.</p>}
      <div className="mt-3 flex flex-col gap-2">
        {options.map((o) => (
          <button key={o.id} disabled={!!result} onClick={() => toggle(o.id)}
            className={`min-h-11 rounded-xl border px-3 py-2 text-left text-sm ${sel.includes(o.id) ? 'border-ink bg-surface-2 font-semibold' : 'border-line'}`}>
            {q.kind === 'ordenar' && sel.includes(o.id) ? `${sel.indexOf(o.id) + 1}. ` : ''}{o.text}
          </button>
        ))}
      </div>
      {!result ? (
        <button disabled={!sel.length || busy} onClick={() => start(async () => { const r = await answer(q.id, payload()); if (r.ok) onResult({ correct: !!r.correct, explanation: String(r.explanation ?? ''), source: String(r.source ?? '') }); })}
          className="mt-3 w-full rounded-2xl bg-ink px-4 py-3 text-sm font-semibold text-surface disabled:opacity-40" data-testid="academy-answer">Responder</button>
      ) : (
        <p className={`mt-3 rounded-xl px-3 py-2 text-sm ${result.correct ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>
          {result.correct ? '✓ Correcto. ' : '✗ No es correcto. '}{result.explanation} <span className="text-muted">({result.source})</span>
        </p>
      )}
    </div>
  );
}
