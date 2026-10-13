import Link from 'next/link';
import { notFound } from 'next/navigation';
import { academyHome, academyMe } from '@/lib/academy';
import { WelcomeVideo } from './WelcomeVideo';

// Academy home (mobile first): pending courses, progress, "Continuar". Staff also get the content panel link.
export default async function AcademyHome() {
  const me = await academyMe();
  if (!me.ok) notFound();
  const staff = me.editor || me.approver;
  if (me.sales === 'none' && !staff) notFound();
  const home = me.sales === 'ok' ? await academyHome() : null;
  const all = home?.ok ? home.courses : [];
  const welcome = all.find((c) => c.kind === 'bienvenida');
  const wl = welcome?.lessons[0];
  const courses = all.filter((c) => c.kind !== 'bienvenida');
  // Mario 2026-10-13: every visit = the welcome video pinned on top, then one button straight into the course.
  const first = courses[0];
  const firstNext = first?.lessons.find((l) => l.status !== 'completada') ?? first?.lessons[0];
  const staging = process.env.NEXT_PUBLIC_F360_ENV === 'staging';
  return (
    <>
      <header>
        <p className="text-xs uppercase tracking-[0.2em] text-muted">Fuxia Sales Academy{staging ? ' · pruebas' : ''}</p>
        <h1 className="font-display text-4xl text-ink">Hola, {me.name.split(' ')[0]}</h1>
      </header>
      <WelcomeVideo lessonId={wl?.id} src="/academy/bienvenida-720.mp4" poster="/academy/bienvenida-poster.jpg" />
      {firstNext && (
        <Link href={`/academy/clase/${firstNext.id}`} className="block rounded-2xl bg-gold px-4 py-4 text-center text-base font-semibold text-ink" data-testid="academy-go-course">
          Ir al curso: {first.title} →
        </Link>
      )}
      {staff && (
        <Link href="/academy/admin" className="rounded-2xl border border-line bg-surface px-4 py-3 text-sm font-semibold text-ink" data-testid="academy-admin-link">
          Contenido y aprobaciones →
        </Link>
      )}
      {me.sales === 'bloqueado' && (
        <div className="rounded-3xl border border-line bg-surface p-5 text-sm text-ink-2" data-testid="academy-blocked">
          Academy todavía no está abierta para vendedoras. Te avisaremos cuando esté lista.
        </div>
      )}
      {me.sales === 'ok' && courses.length === 0 && (
        <div className="rounded-3xl border border-line bg-surface p-5 text-sm text-ink-2">Todavía no hay cursos publicados.</div>
      )}
      {courses.map((c) => {
        const done = c.lessons.filter((l) => l.status === 'completada').length;
        const next = c.lessons.find((l) => l.status !== 'completada');
        return (
          <section key={c.id} className="rounded-3xl border border-line bg-surface p-5" data-testid="academy-course">
            <h2 className="text-lg font-semibold text-ink">{c.title}</h2>
            {c.summary && <p className="mt-1 text-sm text-muted">{c.summary}</p>}
            <div className="mt-4 h-2 rounded-full bg-surface-2"><div className="h-2 rounded-full bg-gold" style={{ width: `${Math.round((100 * done) / Math.max(1, c.lessons.length))}%` }} /></div>
            <p className="mt-2 text-xs text-muted">{done} de {c.lessons.length} lecciones</p>
            {next && (
              <Link href={`/academy/clase/${next.id}`} className="mt-4 block rounded-2xl bg-ink px-4 py-4 text-center text-base font-semibold text-surface" data-testid="academy-continue">
                {next.status === 'en_curso' ? 'Continuar' : 'Empezar'}: {next.title}
              </Link>
            )}
            <ol className="mt-4 flex flex-col gap-1">
              {c.lessons.map((l) => (
                <li key={l.id}>
                  <Link href={`/academy/clase/${l.id}`} className="flex min-h-11 items-center justify-between rounded-xl px-2 text-sm text-ink hover:bg-surface-2">
                    <span>{l.status === 'completada' ? '✓' : l.status === 'en_curso' ? '◐' : '○'} {l.title}</span>
                    <span className="text-xs text-muted">{l.minutes} min</span>
                  </Link>
                </li>
              ))}
            </ol>
          </section>
        );
      })}
      {me.sales === 'ok' && <Link href="/academy/fichas" className="rounded-2xl border border-line bg-surface px-4 py-3 text-sm font-semibold text-ink">Fichas de producto →</Link>}
      <p className="text-xs text-muted">{staging ? 'Ambiente de pruebas. ' : ''}Sin certificados ni puntos en esta etapa.</p>
    </>
  );
}
