import { SubmitButton } from '@/components/SubmitButton';
import { dayLabel, getFxStatus, monthLabel, rateSentence, when } from '@/lib/intel';
import { approveRate } from '../actions';

// Tipo de cambio (I2). The daily official reading (Banxico FIX / TRM) proposes one monthly rate per currency; it only counts
// for the consolidated MXN figures once the authorized approver (Mario) approves it. Approve = f360_fx_rate_approve, which
// checks the approver in the database; the button is just a convenience shown when can_approve is true.
export const dynamic = 'force-dynamic';

const ESTADO: Record<string, { t: string; c: string }> = {
  proposed: { t: 'Propuesta', c: 'bg-amber-100 text-amber-900' },
  approved: { t: 'Aprobada', c: 'bg-success-soft text-success' },
};

export default async function TipoDeCambio({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const sp = await searchParams;
  const fx = await getFxStatus();
  if (!fx.ok) return <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{fx.error}</p>;
  const proposed = fx.months.filter((m) => m.estado === 'proposed');
  const history = fx.months.filter((m) => m.estado !== 'proposed');
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <header className="flex flex-col gap-2">
        <h1 className="font-display text-4xl text-ink sm:text-5xl">Tipo de cambio</h1>
        <p className="max-w-3xl text-sm text-ink-2">Cada día se lee el tipo de cambio oficial. Al terminar el mes se propone el promedio. Solo una tasa <b>aprobada</b> se usa para sumar todo en pesos; mientras tanto, el mes en curso usa la última tasa como «provisional».</p>
        <p className="text-xs text-muted">Quién aprueba: {fx.approvers.join(', ') || 'nadie asignado'}{fx.can_approve ? ' · tú puedes aprobar' : ' · tú solo puedes consultar'}</p>
        {sp.ok && <p className="rounded-xl bg-success-soft px-4 py-2 text-sm text-success">{sp.ok}</p>}
        {sp.error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-2 text-sm text-danger">{sp.error}</p>}
      </header>

      <section className="rounded-2xl border border-line bg-surface p-4 sm:p-5" data-testid="fx-latest">
        <h2 className="font-semibold text-ink">Lectura diaria más reciente</h2>
        <ul className="mt-2 flex flex-col gap-2">
          {fx.latest.map((l) => (
            <li key={l.moneda} className="flex flex-col">
              <span className="font-display text-2xl text-ink">{rateSentence(l.moneda, Number(l.tasa))}</span>
              <span className="text-xs text-muted">{dayLabel(l.fecha)} · {l.fuente} · leída {when(l.leida)}</span>
            </li>
          ))}
          {fx.latest.length === 0 && <li className="text-sm text-muted">Todavía no hay lecturas.</li>}
        </ul>
        <p className={`mt-2 text-xs ${fx.last_run && !fx.last_run.ok ? 'text-danger' : 'text-muted'}`}>
          Última lectura automática: {fx.last_run ? `${when(fx.last_run.at)} · ${fx.last_run.ok ? 'correcta' : `con error: ${fx.last_run.error ?? 'sin detalle'}`}` : 'nunca'}
        </p>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-4 sm:p-5" data-testid="fx-proposed">
        <h2 className="font-semibold text-ink">Por aprobar ({proposed.length})</h2>
        {proposed.length === 0 && <p className="mt-1 text-sm text-muted">No hay tasas pendientes.</p>}
        <ul className="mt-2 flex flex-col divide-y divide-line">
          {proposed.map((m) => (
            <li key={m.id} className="flex flex-col gap-2 py-3 sm:flex-row sm:items-center sm:justify-between" data-testid={`fx-month-${m.mes.slice(0, 7)}-${m.moneda}`}>
              <div className="min-w-0">
                <p className="text-ink"><b className="capitalize">{monthLabel(m.mes)}</b> · {m.moneda} <span className={`ml-1 rounded-full px-2 py-0.5 text-xs ${ESTADO.proposed.c}`}>Propuesta</span></p>
                <p className="font-display text-xl text-ink">{rateSentence(m.moneda, Number(m.tasa))}</p>
                <p className="break-words text-xs text-muted">{m.fuente}{m.notas ? ` · ${m.notas}` : ''} · propuso {m.propuesta_por ?? '—'}</p>
              </div>
              {fx.can_approve && (
                <form action={approveRate}>
                  <input type="hidden" name="id" value={m.id} />
                  <SubmitButton pendingText="Aprobando…" className="w-full rounded-full bg-ink px-4 py-2 text-sm font-semibold text-surface sm:w-auto">Aprobar {m.moneda} de {monthLabel(m.mes)}</SubmitButton>
                </form>
              )}
            </li>
          ))}
        </ul>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-4 sm:p-5" data-testid="fx-history">
        <h2 className="font-semibold text-ink">Historial</h2>
        {history.length === 0 && <p className="mt-1 text-sm text-muted">Aún no se ha aprobado ninguna tasa mensual.</p>}
        <ul className="mt-2 flex flex-col gap-1 text-sm">
          {history.map((m) => (
            <li key={m.id} className="break-words text-ink-2"><b className="capitalize text-ink">{monthLabel(m.mes)}</b> · {rateSentence(m.moneda, Number(m.tasa))} · <span className={`rounded-full px-2 py-0.5 text-xs ${ESTADO[m.estado]?.c ?? 'bg-surface-2 text-muted'}`}>{ESTADO[m.estado]?.t ?? m.estado}</span>{m.aprobada_por ? ` · aprobó ${m.aprobada_por} ${when(m.aprobada)}` : ''}</li>
          ))}
        </ul>
        {fx.manual.length > 0 && (<>
          <h3 className="mt-4 text-xs font-bold uppercase tracking-[0.18em] text-muted">Referencias manuales</h3>
          <ul className="mt-1 text-xs text-ink-2">{fx.manual.map((x, i) => <li key={i}>{dayLabel(x.fecha)} · {rateSentence(x.moneda, Number(x.tasa))} · {x.fuente} · {x.por}</li>)}</ul>
        </>)}
      </section>
    </div>
  );
}
