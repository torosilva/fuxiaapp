import Link from 'next/link';
import { notFound } from 'next/navigation';
import { academyVersion, STATUS } from '@/lib/academy';
import { CardView } from '../../../Card';
import { Decide, ItemEditor, LessonEditor, Submit, CommentBox } from './Editors';

// One course version: preview as the learner will see it, questions WITH answers (staff only), comments, submit / decide.
export default async function Version({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const v = await academyVersion(id);
  if (!v.ok) notFound();
  const ver = v.version;
  return (
    <>
      <Link href="/academy/admin" className="text-xs text-muted">← Contenido</Link>
      <h1 className="font-display text-3xl text-ink">{ver.title}</h1>
      <p className="text-sm text-muted">Versión {ver.version} · {STATUS[ver.status] ?? ver.status}</p>
      {ver.status === 'borrador' && <p className="rounded-2xl bg-gold-soft px-4 py-3 text-xs text-ink-2">En borrador las fichas se muestran con los datos validados de hoy. Al enviar a revisión quedan congeladas y forman parte de lo que Carolina aprueba.</p>}
      {v.request && (
        <section className="rounded-3xl border border-line bg-surface p-4 text-xs text-ink-2" data-testid="academy-request">
          <p className="font-semibold text-ink">Solicitud {v.request.operation} · {v.request.status}</p>
          <p>Pedida por {v.request.requested_by}: “{v.request.reason}” · vence {new Date(v.request.expires_at).toLocaleDateString('es-MX')}</p>
          <p className="break-all text-muted">Huella aprobada: {v.request.hash}</p>
          <ul className="mt-1">{v.request.events.map((e, k) => <li key={k}>{e.action} · {e.by}{e.self ? ' · autoaprobación' : ''}{e.aal ? ` · ${e.aal}` : ''}{e.reason ? ` — ${e.reason}` : ''}</li>)}</ul>
        </section>
      )}
      {v.can_edit && <Submit version={ver.id} />}
      {v.can_decide && <Decide version={ver.id} />}
      {v.lessons.map((l) => (
        <section key={l.id} className="rounded-3xl border border-line bg-surface p-5">
          <h2 className="text-lg font-semibold text-ink">{l.key} · {l.title} <span className="text-xs font-normal text-muted">{l.minutes} min</span></h2>
          {v.can_edit ? <LessonEditor version={ver.id} lesson={l} /> : (
            <ol className="mt-3 flex flex-col gap-4">{l.blocks.map((b, k) => <li key={k} className="rounded-2xl border border-line p-4"><CardView b={b} products={l.products} /></li>)}</ol>
          )}
          <CommentBox version={ver.id} lessonKey={l.key} comments={v.comments.filter((c) => c.lesson === l.key)} />
        </section>
      ))}
      <section className="rounded-3xl border border-line bg-surface p-5">
        <h2 className="text-lg font-semibold text-ink">Preguntas ({v.items.length})</h2>
        <p className="text-xs text-muted">Las respuestas solo las ve el equipo de contenido. En A1 solo se usan como práctica.</p>
        <ol className="mt-3 flex flex-col gap-3">{v.items.map((it) => <li key={it.id}><ItemEditor version={ver.id} item={it} editable={v.can_edit} /></li>)}</ol>
      </section>
    </>
  );
}
