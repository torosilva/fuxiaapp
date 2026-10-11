import Link from 'next/link';
import { SubmitButton } from '@/components/SubmitButton';
import { CHANNEL, MARKET, MONTHS_ES, getBudgets, getGoals, money, monthLabel, when, type BudgetVersion } from '@/lib/intel';
import { approveBudget, draftBudget, saveBudgetLines, setGoal, validateBudget } from '../actions';

// Presupuesto y metas (I2). Budgets are versions (borrador → validación comercial de Carolina → aprobación de Mario); approving
// supersedes the previous approved version of the year, which stays in the history. Goals are versioned too (a change = a new
// version with its reason). Every rule lives in the database (f360_board_budget_* / f360_board_goal_*); this page only shows
// the versions and passes the forms through. No totals are computed here.
export const dynamic = 'force-dynamic';

const COLS = [
  { market: 'MX', channel: 'online', label: 'México en línea', cur: 'MXN' },
  { market: 'MX', channel: 'store', label: 'México tiendas', cur: 'MXN' },
  { market: 'CO', channel: 'online', label: 'Colombia en línea', cur: 'COP' },
  { market: 'ROW', channel: 'online', label: 'Resto del mundo en línea', cur: 'USD' },
] as const;
const STATUS: Record<string, { t: string; c: string }> = {
  DRAFT: { t: 'Borrador', c: 'bg-amber-100 text-amber-900' },
  APPROVED: { t: 'Aprobado', c: 'bg-success-soft text-success' },
  SUPERSEDED: { t: 'Reemplazado', c: 'bg-surface-2 text-muted' },
};
const input = 'w-full min-w-0 rounded-xl border border-line bg-surface px-3 py-2 text-sm';
const btn = 'rounded-full bg-ink px-4 py-2 text-sm font-semibold text-surface';
const box = 'rounded-2xl border border-line bg-surface p-4 sm:p-5';
const cell = (v: BudgetVersion, m: number, market: string, channel: string) =>
  v.lines.find((l) => Number(l.month.slice(5, 7)) === m && l.market === market && l.channel === channel)?.amount;

function Grid({ v, year, editable }: { v: BudgetVersion; year: number; editable: boolean }) {
  return (
    <div className="flex flex-col gap-1" data-testid="budget-grid">
      <div className="hidden grid-cols-[6.5rem_repeat(4,minmax(0,1fr))] gap-2 text-xs text-muted sm:grid">
        <span>Mes</span>{COLS.map((c) => <span key={c.label}>{c.label} ({c.cur})</span>)}
      </div>
      {MONTHS_ES.map((name, i) => (
        <div key={name} className="grid grid-cols-2 items-center gap-2 border-t border-line py-1.5 sm:grid-cols-[6.5rem_repeat(4,minmax(0,1fr))] sm:border-0 sm:py-0">
          <span className="col-span-2 text-sm capitalize text-ink sm:col-span-1">{name} {year}</span>
          {COLS.map((c) => {
            const val = cell(v, i + 1, c.market, c.channel);
            return editable ? (
              <label key={c.label} className="flex min-w-0 flex-col text-[11px] text-muted sm:block">
                <span className="sm:sr-only">{c.label} ({c.cur})</span>
                <input name={`c_${i + 1}_${c.market}_${c.channel}`} defaultValue={val ?? ''} inputMode="decimal" placeholder="—" className={`${input} tabular-nums`} />
              </label>
            ) : (
              <span key={c.label} className="flex min-w-0 flex-col text-sm tabular-nums text-ink-2"><span className="text-[11px] text-muted sm:hidden">{c.label}</span>{val === undefined ? '—' : money(val, c.cur)}</span>
            );
          })}
        </div>
      ))}
    </div>
  );
}

export default async function Presupuesto({ searchParams }: { searchParams: Promise<{ anio?: string; version?: string; ok?: string; error?: string }> }) {
  const sp = await searchParams;
  const thisYear = Number(new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' }).slice(0, 4));
  const years = [thisYear, thisYear + 1];
  const year = years.includes(Number(sp.anio)) ? Number(sp.anio) : thisYear + 1;
  const [b, g] = await Promise.all([getBudgets(year), getGoals()]);
  if (!b.ok) return <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{b.error}</p>;
  const selected = b.versions.find((v) => v.id === sp.version) ?? b.versions.find((v) => v.status === 'DRAFT') ?? b.versions.find((v) => v.status === 'APPROVED') ?? null;
  const approved = b.versions.find((v) => v.status === 'APPROVED');
  const keys = g.ok ? [...new Map(g.goals.map((x) => [x.key, x])).values()] : [];

  return (
    <div className="flex min-w-0 flex-col gap-5">
      <header className="flex flex-col gap-2">
        <h1 className="font-display text-4xl text-ink sm:text-5xl">Presupuesto y metas</h1>
        <p className="max-w-3xl text-sm text-ink-2">El presupuesto es la venta neta esperada por mes, en la moneda de cada mercado. Se aprueba en tres pasos: alguien arma el borrador, <b>Carolina</b> lo valida comercialmente y <b>Mario</b> lo aprueba. Ninguna versión se borra: cada cambio queda en el historial con su motivo.</p>
        <nav className="flex gap-2 text-sm">{years.map((y) => <Link key={y} href={`/direccion/presupuesto?anio=${y}`} className={`rounded-full px-3 py-1 ${y === year ? 'bg-ink text-surface' : 'border border-line text-ink-2'}`}>{y}</Link>)}</nav>
        {sp.ok && <p className="rounded-xl bg-success-soft px-4 py-2 text-sm text-success">{sp.ok}</p>}
        {sp.error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-2 text-sm text-danger">{sp.error}</p>}
      </header>

      <section className={box} data-testid="goals">
        <h2 className="font-semibold text-ink">Metas</h2>
        {!g.ok && <p className="mt-1 text-sm text-danger">{g.error}</p>}
        {g.ok && g.goals.length === 0 && <p className="mt-1 text-sm text-muted">No hay metas registradas.</p>}
        {keys.map((k) => (
          <div key={k.key} className="mt-3">
            <p className="text-ink"><b>{k.label}</b> · {MARKET[k.market ?? ''] ?? k.market} {k.channel ? CHANNEL[k.channel] : ''}</p>
            <ul className="mt-1 flex flex-col gap-1 text-sm">
              {g.ok && g.goals.filter((x) => x.key === k.key).map((x, i) => (
                <li key={x.id} className={`break-words ${i === 0 ? 'text-ink' : 'text-muted'}`}>
                  <b className="tabular-nums">{money(x.amount, x.currency)}</b> al mes desde {monthLabel(x.from)} · {x.by}, {when(x.at)}{i === 0 ? ' · vigente' : ' · versión anterior'}
                  <span className="block text-xs text-muted">Motivo: {x.reason}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
        {g.ok && g.can_set && (
          <details className="mt-4 rounded-xl border border-line p-3">
            <summary className="cursor-pointer text-sm font-medium text-ink">Nueva versión de una meta</summary>
            <form action={setGoal} className="mt-3 grid gap-2 sm:grid-cols-2">
              <input type="hidden" name="year" value={year} />
              <label className="text-xs text-muted">Clave (minúsculas, sin espacios)<input name="key" required pattern="[a-z][a-z0-9_]*" defaultValue={keys[0]?.key ?? ''} className={input} /></label>
              <label className="text-xs text-muted">Nombre<input name="label" required minLength={3} defaultValue={keys[0]?.label ?? ''} className={input} /></label>
              <label className="text-xs text-muted">Mercado<select name="market" defaultValue={keys[0]?.market ?? 'MX'} className={input}><option value="MX">México (MXN)</option><option value="CO">Colombia (COP)</option><option value="ROW">Resto del mundo (USD)</option></select></label>
              <label className="text-xs text-muted">Canal<select name="channel" defaultValue={keys[0]?.channel ?? 'online'} className={input}><option value="online">En línea</option><option value="store">Tiendas</option></select></label>
              <label className="text-xs text-muted">Monto mensual<input name="amount" required inputMode="decimal" className={input} /></label>
              <label className="text-xs text-muted">Desde el mes<input name="from" type="month" required className={input} /></label>
              <label className="text-xs text-muted sm:col-span-2">Motivo del cambio (obligatorio)<input name="reason" required minLength={5} className={input} /></label>
              <SubmitButton className={`${btn} sm:justify-self-start`}>Guardar nueva versión</SubmitButton>
            </form>
          </details>
        )}
        {g.ok && !g.can_set && <p className="mt-3 text-xs text-muted">Solo quien aprueba presupuestos define metas.</p>}
      </section>

      <section className={box} data-testid="budgets">
        <h2 className="font-semibold text-ink">Presupuesto {year}</h2>
        <p className="mt-1 text-sm text-ink-2">{approved ? <>Vigente: <b>{approved.name}</b>, aprobado por {approved.approved_by ?? '—'} el {when(approved.approved_at)}.</> : 'Todavía no hay un presupuesto aprobado para este año.'}</p>
        <ul className="mt-3 flex flex-col divide-y divide-line" data-testid="budget-history">
          {b.versions.map((v) => (
            <li key={v.id} className="flex flex-col gap-0.5 py-2">
              <div className="flex flex-wrap items-center gap-2">
                <Link href={`/direccion/presupuesto?anio=${year}&version=${v.id}`} className={`font-medium ${selected?.id === v.id ? 'text-gold-strong' : 'text-ink'} underline-offset-2 hover:underline`}>{v.name}</Link>
                <span className={`rounded-full px-2 py-0.5 text-xs ${STATUS[v.status]?.c}`}>{STATUS[v.status]?.t ?? v.status}</span>
              </div>
              <p className="break-words text-xs text-muted">Creó {v.created_by} el {when(v.created_at)}{v.reason ? ` · motivo: ${v.reason}` : ''}{v.supersedes ? ' · basada en una versión anterior' : ''}
                {v.validated_by ? ` · validó ${v.validated_by} ${when(v.validated_at)}` : ''}{v.approved_by ? ` · aprobó ${v.approved_by} ${when(v.approved_at)}` : ''}{v.content_hash ? ` · huella ${v.content_hash.slice(0, 10)}…` : ''}</p>
            </li>
          ))}
          {b.versions.length === 0 && <li className="py-2 text-sm text-muted">Sin versiones para {year}.</li>}
        </ul>
      </section>

      {selected && (
        <section className={box} data-testid="budget-version">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="font-semibold text-ink">{selected.name}</h2>
            <span className={`rounded-full px-2 py-0.5 text-xs ${STATUS[selected.status]?.c}`}>{STATUS[selected.status]?.t}</span>
          </div>
          {selected.status === 'DRAFT' ? (
            <>
              <p className="mt-1 text-xs text-muted">Escribe el monto de cada mes; deja vacío lo que no aplica. Guardar reemplaza los montos del borrador y, si ya estaba validado, pide validar de nuevo.</p>
              <form action={saveBudgetLines} className="mt-3 flex flex-col gap-3">
                <input type="hidden" name="year" value={year} /><input type="hidden" name="version" value={selected.id} />
                <Grid v={selected} year={year} editable />
                <SubmitButton className={`${btn} self-start`}>Guardar montos</SubmitButton>
              </form>
              <div className="mt-5 flex flex-col gap-3 border-t border-line pt-4">
                <p className="text-sm text-ink-2">{selected.validated_by ? <>Validación comercial: <b>{selected.validated_by}</b> {when(selected.validated_at)}{selected.validation_note ? ` · ${selected.validation_note}` : ''}</> : 'Falta la validación comercial (Carolina).'}</p>
                <form action={validateBudget} className="flex flex-col gap-2 sm:flex-row">
                  <input type="hidden" name="year" value={year} /><input type="hidden" name="version" value={selected.id} />
                  <input name="note" placeholder="Nota de la validación (opcional)" className={input} />
                  <SubmitButton className="shrink-0 rounded-full border border-ink px-4 py-2 text-sm font-semibold text-ink">Validar comercialmente</SubmitButton>
                </form>
                {b.can_approve && (
                  <form action={approveBudget}>
                    <input type="hidden" name="year" value={year} /><input type="hidden" name="version" value={selected.id} />
                    <SubmitButton pendingText="Aprobando…" className={btn}>Aprobar este presupuesto</SubmitButton>
                    <p className="mt-1 text-xs text-muted">Al aprobar, queda congelado y reemplaza al aprobado anterior del año (que se conserva en el historial).</p>
                  </form>
                )}
              </div>
            </>
          ) : <div className="mt-3"><Grid v={selected} year={year} editable={false} /></div>}
        </section>
      )}

      <section className={box}>
        <details>
          <summary className="cursor-pointer font-semibold text-ink">Nuevo borrador de presupuesto {year}</summary>
          <form action={draftBudget} className="mt-3 grid gap-2 sm:grid-cols-2">
            <input type="hidden" name="year" value={year} />
            <label className="text-xs text-muted">Nombre<input name="name" required minLength={3} placeholder={`Presupuesto ${year}`} className={input} /></label>
            <label className="text-xs text-muted">Partir de
              <select name="copy_from" className={input} defaultValue={approved?.id ?? ''}>
                <option value="">En blanco</option>
                {b.versions.map((v) => <option key={v.id} value={v.id}>{v.name} ({STATUS[v.status]?.t})</option>)}
              </select>
            </label>
            <label className="text-xs text-muted sm:col-span-2">Motivo de esta versión (obligatorio)<input name="reason" required minLength={5} className={input} /></label>
            <SubmitButton className={`${btn} sm:justify-self-start`}>Crear borrador</SubmitButton>
          </form>
        </details>
      </section>
    </div>
  );
}
