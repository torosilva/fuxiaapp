import Link from 'next/link';
import { notFound } from 'next/navigation';
import { BoardMfa } from '@/app/(app)/estrategia/BoardMfa';
import { SubmitButton } from '@/components/SubmitButton';
import { boardAccessState } from '@/lib/board';
import { dayLabel, financeAccess, getClosePrep, money, monthLabel, when, type Commitment, type PrepEntry } from '@/lib/intel';
import { addCommitment, addEntry, commitmentEvent, voidEntry } from './actions';

// Cierre contable (I2). The contadora captures the month's amounts (bancos, efectivo, gastos…) and the upcoming payments;
// Mario or Carolina approve. The database decides everything (f360_close_prep_* / f360_finance_commitment_*): who may capture
// (preparer or board FINANCIAL, with second factor), which months are open, that only her own unapproved captures can be
// voided and that whoever captured never approves.
export const dynamic = 'force-dynamic';

const KIND: Record<string, string> = { proveedor: 'Proveedor', produccion: 'Producción', renta: 'Renta', nomina: 'Nómina', impuestos: 'Impuestos', credito: 'Crédito', servicios: 'Servicios', otro: 'Otro' };
const MONTH_STATUS: Record<string, string> = { OPEN: 'Abierto', REOPENED: 'Reabierto', UNDER_REVIEW: 'En revisión', CLOSED: 'Cerrado' };
const CURRENCIES = ['MXN', 'COP', 'USD'];
const input = 'w-full min-w-0 rounded-xl border border-line bg-surface px-3 py-2 text-sm';
const btn = 'rounded-full bg-ink px-4 py-2 text-sm font-semibold text-surface';
const box = 'rounded-2xl border border-line bg-surface p-4 sm:p-5';
const editable = (st: string) => st === 'OPEN' || st === 'REOPENED';

function EntryRow({ e, label, periodId, canVoid }: { e: PrepEntry; label: string; periodId: string; canVoid: boolean }) {
  return (
    <li className={`flex flex-col gap-1 py-3 ${e.status === 'voided' ? 'text-muted' : ''}`} data-testid="entry">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <span className={`text-ink ${e.status === 'voided' ? 'line-through' : ''}`}>{label}</span>
        <span className={`font-semibold tabular-nums ${e.status === 'voided' ? 'line-through' : 'text-ink'}`}>{money(e.amount, e.currency, 2)}</span>
      </div>
      <p className="break-words text-xs text-muted">Fuente: {e.source}{e.evidence ? ` · documento ${e.evidence}` : ''}{e.note ? ` · ${e.note}` : ''}</p>
      <p className="text-xs">
        <span className="text-muted">Capturó {e.captured_by} · {when(e.captured_at)} · </span>
        {e.status === 'voided' ? <span className="text-danger">Anulada: {e.void_reason}</span>
          : e.approved_by ? <span className="text-success">Aprobó {e.approved_by} · {when(e.approved_at)}</span>
          : <span className="text-amber-900">Por aprobar</span>}
      </p>
      {canVoid && (
        <details className="text-sm">
          <summary className="cursor-pointer text-xs text-danger">Anular esta captura</summary>
          <form action={voidEntry} className="mt-2 flex flex-col gap-2 sm:flex-row">
            <input type="hidden" name="period_id" value={periodId} /><input type="hidden" name="entry_id" value={e.id} />
            <input name="reason" required minLength={5} placeholder="¿Por qué se anula? (obligatorio)" className={input} />
            <SubmitButton pendingText="Anulando…" className="shrink-0 rounded-full border border-danger px-4 py-2 text-sm text-danger">Anular</SubmitButton>
          </form>
        </details>
      )}
    </li>
  );
}

function CommitmentFields({ c }: { c?: Commitment }) {
  return (<>
    <label className="text-xs text-muted">Tipo<select name="kind" defaultValue={c?.kind ?? 'proveedor'} className={input}>{Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
    <label className="text-xs text-muted">A quién se paga<input name="counterparty" required minLength={2} defaultValue={c?.counterparty} className={input} /></label>
    <label className="text-xs text-muted">Fecha de pago<input name="due_date" type="date" required defaultValue={c?.due_date} className={input} /></label>
    <label className="text-xs text-muted">Monto<input name="amount" required inputMode="decimal" defaultValue={c?.amount} className={input} /></label>
    <label className="text-xs text-muted">Moneda<select name="currency" defaultValue={c?.currency ?? 'MXN'} className={input}>{CURRENCIES.map((x) => <option key={x}>{x}</option>)}</select></label>
    <label className="text-xs text-muted">¿Se repite?<select name="recurrence" defaultValue={c?.recurrence ?? 'una_vez'} className={input}><option value="una_vez">Una sola vez</option><option value="mensual">Cada mes</option></select></label>
    <label className="text-xs text-muted sm:col-span-2">Descripción<input name="description" defaultValue={c?.description ?? ''} className={input} /></label>
    <label className="text-xs text-muted">Fuente (p. ej. factura, contrato)<input name="source" required minLength={3} defaultValue={c?.source} className={input} /></label>
    <label className="text-xs text-muted">Referencia del documento<input name="evidence" defaultValue={c?.evidence ?? ''} className={input} /></label>
  </>);
}

function CommitmentRow({ c, periodId, board }: { c: Commitment; periodId: string; board: boolean }) {
  const pending = c.state === 'pendiente';
  return (
    <li className="flex flex-col gap-1 py-3" data-testid="commitment">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3">
        <span className="text-ink"><b>{c.counterparty}</b> · {KIND[c.kind] ?? c.kind}{c.recurrence === 'mensual' ? ' · cada mes' : ''}</span>
        <span className="font-semibold tabular-nums text-ink">{money(c.amount, c.currency, 2)}</span>
      </div>
      <p className="break-words text-xs text-muted">Vence {dayLabel(c.due_date)}{c.description ? ` · ${c.description}` : ''} · fuente {c.source}{c.evidence ? ` · ${c.evidence}` : ''}{c.corrects ? ' · corrige un registro anterior' : ''}</p>
      <p className="text-xs">
        <span className="text-muted">Capturó {c.captured_by} · {when(c.captured_at)} · </span>
        <span className={c.state === 'pagado' ? 'text-success' : 'text-amber-900'}>{c.state === 'pagado' ? 'Pagado' : 'Pendiente'}</span>
        {c.approved_by ? <span className="text-success"> · aprobó {c.approved_by}</span> : pending ? <span className="text-muted"> · sin aprobar</span> : null}
      </p>
      {pending && (
        <div className="flex flex-wrap gap-2 pt-1">
          {board && !c.approved_by && (
            <form action={commitmentEvent}><input type="hidden" name="period_id" value={periodId} /><input type="hidden" name="id" value={c.id} /><input type="hidden" name="action" value="approved" />
              <SubmitButton pendingText="Aprobando…" className="rounded-full bg-ink px-3 py-1.5 text-xs font-semibold text-surface">Aprobar</SubmitButton></form>
          )}
          <details className="w-full text-sm">
            <summary className="cursor-pointer text-xs text-ink-2">Marcar pagado · cancelar · corregir</summary>
            <form action={commitmentEvent} className="mt-2 flex flex-col gap-2 sm:flex-row">
              <input type="hidden" name="period_id" value={periodId} /><input type="hidden" name="id" value={c.id} />
              <input name="reason" required minLength={5} placeholder="Motivo o referencia del pago (obligatorio)" className={input} />
              <SubmitButton name="action" value="paid" className="shrink-0 rounded-full border border-success px-3 py-1.5 text-xs text-success">Marcar pagado</SubmitButton>
              <SubmitButton name="action" value="cancelled" className="shrink-0 rounded-full border border-danger px-3 py-1.5 text-xs text-danger">Cancelar</SubmitButton>
            </form>
            <form action={addCommitment} className="mt-3 grid gap-2 rounded-xl bg-surface-2 p-3 sm:grid-cols-2">
              <p className="text-xs text-ink-2 sm:col-span-2">Corregir: se guarda un registro nuevo y el original queda en el historial como corregido.</p>
              <input type="hidden" name="period_id" value={periodId} /><input type="hidden" name="corrects" value={c.id} />
              <CommitmentFields c={c} />
              <label className="text-xs text-muted sm:col-span-2">Qué se corrige (obligatorio)<input name="reason" required minLength={5} className={input} /></label>
              <SubmitButton className={`${btn} sm:justify-self-start`}>Guardar corrección</SubmitButton>
            </form>
          </details>
        </div>
      )}
    </li>
  );
}

export default async function CierreContable({ searchParams }: { searchParams: Promise<{ mes?: string; ok?: string; error?: string }> }) {
  const sp = await searchParams;
  const ctx = await getClosePrep();
  const board = await boardAccessState();
  if (!ctx.ok) {
    if (board === 'mfa_required') return <BoardMfa area="Cierre contable" next="/cierre-contable" />;
    if ((await financeAccess()) === 'mfa_required') return <BoardMfa area="Cierre contable" next="/cierre-contable" />;
    notFound();
  }
  const isBoard = board === 'ok';
  const period = ctx.periods.find((p) => p.id === sp.mes) ?? ctx.periods.find((p) => editable(p.status)) ?? ctx.periods[0];
  const label = (k: string) => ctx.accounts.find((a) => a.key === k)?.label ?? k;
  const open = period ? editable(period.status) : false;
  const pendingApproval = period ? period.entries.filter((e) => e.status === 'active' && !e.approved_by).length : 0;
  const pid = period?.id ?? '';

  return (
    <div className="flex min-w-0 flex-col gap-5">
      <header className="flex flex-col gap-2">
        <h1 className="font-display text-4xl text-ink sm:text-5xl">Cierre contable</h1>
        <p className="max-w-3xl text-sm text-ink-2">Aquí se capturan los montos del cierre de cada mes y los pagos que vienen. Todo lo que se captura lo aprueba <b>Mario o Carolina</b>; quien captura no aprueba. Nada se borra: una corrección deja el registro original en el historial.</p>
        <p className="text-xs text-muted">Sesión de {ctx.me} · cada acceso queda registrado</p>
        {sp.ok && <p className="rounded-xl bg-success-soft px-4 py-2 text-sm text-success">{sp.ok}</p>}
        {sp.error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-2 text-sm text-danger">{sp.error}</p>}
      </header>

      <section className={box} data-testid="months">
        <h2 className="font-semibold text-ink">Mes</h2>
        <nav className="mt-2 flex flex-wrap gap-2 text-sm">
          {ctx.periods.map((p) => (
            <Link key={p.id} href={`/cierre-contable?mes=${p.id}`} aria-current={p.id === pid ? 'page' : undefined}
              className={`rounded-full px-3 py-1 capitalize ${p.id === pid ? 'bg-ink text-surface' : 'border border-line text-ink-2'}`}>
              {monthLabel(p.month)}{editable(p.status) ? '' : ` · ${MONTH_STATUS[p.status] ?? p.status}`}
            </Link>
          ))}
        </nav>
      </section>

      {period && (
        <section id="capturas" className={box} data-testid="entries">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h2 className="font-semibold text-ink">Cierre de {monthLabel(period.month)}</h2>
            <span className="text-xs text-muted">{MONTH_STATUS[period.status] ?? period.status}{open ? ' · se puede capturar' : ' · ya no se captura'}</span>
          </div>
          {period.entries.length === 0 && <p className="mt-2 text-sm text-muted">Sin capturas en este mes.</p>}
          <ul className="mt-1 flex flex-col divide-y divide-line">
            {period.entries.map((e) => <EntryRow key={e.id} e={e} label={label(e.account)} periodId={pid} canVoid={open && e.mine && e.status === 'active' && !e.approved_by} />)}
          </ul>
          {isBoard && pendingApproval > 0 && (
            <p className="mt-3 text-sm"><Link href={`/estrategia/cierre/${pid}`} className="font-semibold text-gold-strong underline">Aprobar {pendingApproval} captura(s) en Strategy &amp; Board →</Link></p>)}

          {open && (
            <form action={addEntry} className="mt-4 grid gap-2 border-t border-line pt-4 sm:grid-cols-3" data-testid="entry-form">
              <h3 className="text-sm font-medium text-ink sm:col-span-3">Capturar un monto</h3>
              <input type="hidden" name="period_id" value={pid} /><input type="hidden" name="idempotency_key" value={crypto.randomUUID()} />
              <label className="text-xs text-muted sm:col-span-3">Cuenta<select name="account" required className={input}>{ctx.accounts.map((a) => <option key={a.key} value={a.key}>{a.label}</option>)}</select></label>
              <label className="text-xs text-muted">Monto<input name="amount" required inputMode="decimal" placeholder="0.00" className={input} /></label>
              <label className="text-xs text-muted">Moneda<select name="currency" defaultValue="MXN" className={input}>{CURRENCIES.map((x) => <option key={x}>{x}</option>)}</select></label>
              <label className="text-xs text-muted">Referencia del documento<input name="evidence" className={input} /></label>
              <label className="text-xs text-muted sm:col-span-2">Fuente (obligatoria, p. ej. «estado de cuenta BBVA»)<input name="source" required minLength={3} className={input} /></label>
              <label className="text-xs text-muted">Nota<input name="note" className={input} /></label>
              <SubmitButton className={`${btn} sm:col-span-3 sm:justify-self-start`}>Guardar monto</SubmitButton>
            </form>
          )}
        </section>
      )}

      <section id="compromisos" className={box} data-testid="commitments">
        <h2 className="font-semibold text-ink">Pagos próximos (compromisos)</h2>
        <p className="mt-1 text-xs text-muted">Proveedores, producción, renta, nómina, impuestos, créditos… Se ven los pendientes y los pagados de los últimos 60 días.</p>
        {ctx.commitments.length === 0 && <p className="mt-2 text-sm text-muted">No hay compromisos capturados.</p>}
        <ul className="mt-1 flex flex-col divide-y divide-line">
          {ctx.commitments.map((c) => <CommitmentRow key={c.id} c={c} periodId={pid} board={isBoard} />)}
        </ul>
        <details className="mt-4 rounded-xl border border-line p-3">
          <summary className="cursor-pointer text-sm font-medium text-ink">Agregar un compromiso</summary>
          <form action={addCommitment} className="mt-3 grid gap-2 sm:grid-cols-2" data-testid="commitment-form">
            <input type="hidden" name="period_id" value={pid} />
            <CommitmentFields />
            <SubmitButton className={`${btn} sm:justify-self-start`}>Guardar compromiso</SubmitButton>
          </form>
        </details>
      </section>
    </div>
  );
}
