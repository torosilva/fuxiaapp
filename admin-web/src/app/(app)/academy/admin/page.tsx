import Link from 'next/link';
import { notFound } from 'next/navigation';
import { academyOverview, academyTeam, APPROVAL, OPERATION, STATUS } from '@/lib/academy';
import { NewDraftButton } from './NewDraftButton';

// Content panel (editor / approver). Approval history comes from the shared registry f360.approval_* (academy scopes only).
export default async function AcademyAdmin() {
  const [o, team] = await Promise.all([academyOverview(), academyTeam()]);
  if (!o.ok) notFound();
  const me = o.me;
  return (
    <>
      <Link href="/academy" className="text-xs text-muted">← Academy</Link>
      <h1 className="font-display text-4xl text-ink">Contenido</h1>
      <div className="rounded-2xl bg-gold-soft px-4 py-3 text-xs text-ink-2" data-testid="academy-gates">
        {me.gates.note} Acceso real de vendedoras: <b>{me.gates.learner_access_enabled ? 'sí' : 'bloqueado'}</b> · Certificados: <b>no</b> · Puntos: <b>no</b> · Canjes: <b>no</b>.
      </div>
      {o.courses.map((c) => (
        <section key={c.id} className="rounded-3xl border border-line bg-surface p-5">
          <div className="flex items-start justify-between gap-3">
            <div><h2 className="text-lg font-semibold text-ink">{c.title}</h2><p className="text-xs text-muted">{c.school === 'sales' ? 'Sales Academy' : 'Escuela Ejecutiva'} · {c.key}</p></div>
            {me.editor && c.school === 'sales' && <NewDraftButton course={c.id} />}
          </div>
          <ul className="mt-3 flex flex-col gap-2">
            {(c.versions ?? []).map((v) => (
              <li key={v.id}>
                <Link href={`/academy/admin/version/${v.id}`} className="flex flex-col rounded-2xl border border-line px-3 py-2 text-sm hover:bg-surface-2" data-testid="academy-version">
                  <span className="font-semibold text-ink">Versión {v.version} · {STATUS[v.status] ?? v.status}</span>
                  <span className="text-xs text-muted">{v.lessons} lecciones · {v.items} preguntas · {v.comments} comentarios
                    {v.request ? ` · solicitud ${APPROVAL[v.request.status] ?? v.request.status} (${OPERATION[v.request.operation] ?? v.request.operation})${v.request.self_approval ? ' · autoaprobación' : ''}` : ''}</span>
                  {!!v.stale_products?.length && <span className="text-xs text-danger">Ficha actualizada desde la publicación: {v.stale_products.join(', ')}. Revisar.</span>}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      ))}
      <section className="rounded-3xl border border-line bg-surface p-5">
        <h2 className="text-lg font-semibold text-ink">Avance por persona y tienda</h2>
        {team.ok && team.learners.length ? (
          <table className="mt-3 w-full text-left text-sm"><thead className="text-xs text-muted"><tr><th>Persona</th><th>Tienda</th><th>Lecciones</th><th>Práctica</th></tr></thead>
            <tbody>{team.learners.map((l, k) => (
              <tr key={k} className="border-t border-line"><td className="py-2">{l.name}{l.tester ? ' (prueba)' : ''}</td><td>{l.store ?? '—'}</td>
                <td>{l.lessons_done}/{l.lessons_total}</td><td>{l.practice.correct}/{l.practice.answered}</td></tr>))}</tbody></table>
        ) : <p className="mt-2 text-sm text-muted">Nadie ha empezado todavía.</p>}
      </section>
      <section className="rounded-3xl border border-line bg-surface p-5">
        <h2 className="text-lg font-semibold text-ink">Historial de aprobaciones</h2>
        <ul className="mt-2 flex flex-col gap-1 text-xs text-ink-2">
          {o.events.slice(0, 40).map((e, k) => (
            <li key={k}>{new Date(e.at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })} · v{e.version} · {OPERATION[e.operation] ?? e.operation} · <b>{APPROVAL[e.action] ?? e.action}</b> · {e.by}{e.self ? ' · autoaprobación' : ''}{e.aal ? ` · ${e.aal}` : ''}{e.reason ? ` — ${e.reason}` : ''}</li>
          ))}
          {!o.events.length && <li className="text-muted">Sin movimientos.</li>}
        </ul>
      </section>
    </>
  );
}
