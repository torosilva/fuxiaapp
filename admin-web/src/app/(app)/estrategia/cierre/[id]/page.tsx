import Link from 'next/link';
import { notFound } from 'next/navigation';
import { MONTHS, STATUS_LABEL, getBoardClose } from '@/lib/board';
import { approveEntries, captureEntry, transitionPeriod, voidEntry } from '../../actions';

// "Cierre de <mes>" (SB0): what the database has for the month — manual captures with who captured / who approved, what a
// close consolidates and what is still DATA INCOMPLETE, the status history and the frozen snapshots. Sales are NOT typed here
// (they come from Commerce Facts, SB1); marketing spend comes from S-G0.
const fmt = (n: number) => new Intl.NumberFormat('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(n);
const when = (s: string) => new Date(s).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', dateStyle: 'short', timeStyle: 'short' });
const btn = 'rounded-full bg-ink px-4 py-2 text-sm font-semibold text-surface';
const input = 'rounded-xl border border-line bg-surface px-3 py-2 text-sm';

export default async function Cierre({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ ok?: string; error?: string }> }) {
  const [{ id }, sp] = await Promise.all([params, searchParams]);
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const c = await getBoardClose(id);
  if (!c.ok) notFound();
  const p = c.period;
  const editable = p.status === 'OPEN' || p.status === 'REOPENED';
  const label = (k: string) => c.accounts.find((a) => a.key === k)?.label ?? k;
  const pendingOthers = c.entries.filter((e) => e.status === 'active' && !e.approved_by && !e.captured_by_me).length;
  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-1">
        <Link href={`/estrategia?anio=${p.year}`} className="text-sm text-muted">← Strategy &amp; Board</Link>
        <h1 className="font-display text-5xl capitalize text-ink">Cierre de {MONTHS[p.month - 1]} {p.year}</h1>
        <p className="text-ink-2">Estado: <b>{STATUS_LABEL[p.status]}</b>{p.close_version > 0 ? ` · versión de cierre ${p.close_version}` : ''}{p.status === 'UNDER_REVIEW' ? ` · enviado por ${p.submitted_by}` : ''}</p>
        {sp.ok && <p className="rounded-xl bg-emerald-50 px-4 py-2 text-sm text-emerald-900">{sp.ok}</p>}
        {sp.error && <p className="rounded-xl bg-rose-50 px-4 py-2 text-sm text-rose-900">{sp.error}</p>}
      </header>

      <section className="rounded-2xl border border-line bg-surface p-5">
        <h2 className="font-semibold text-ink">Qué consolida el cierre</h2>
        <ul className="mt-2 grid gap-1 text-sm sm:grid-cols-2">
          {c.readiness.map((r) => (
            <li key={r.component} className="flex flex-wrap gap-2"><b className="w-36 text-ink">{r.component}</b>
              <span className={r.status === 'AVAILABLE' ? 'text-emerald-800' : r.status === 'PARTIAL' ? 'text-amber-800' : 'text-rose-800'}>{r.status === 'DATA_INCOMPLETE' ? 'DATA INCOMPLETE' : r.status}</span>
              <span className="text-xs text-muted">{r.reason ?? r.source}</span></li>
          ))}
        </ul>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-5">
        <h2 className="font-semibold text-ink">Capturas del mes</h2>
        {c.entries.length === 0 && <p className="mt-1 text-sm text-muted">Sin capturas.</p>}
        <div className="mt-2 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <tbody>{c.entries.map((e) => (
              <tr key={e.id} className={`border-t border-line align-top ${e.status === 'voided' ? 'text-muted line-through' : ''}`}>
                <td className="py-1.5 pr-3">{label(e.account_key)}{e.dimension_key ? ` · ${e.dimension_key}` : ''}</td>
                <td className="pr-3 text-right tabular-nums">{fmt(e.amount)} {e.currency}</td>
                <td className="pr-3 text-xs">{e.source}{e.evidence_ref ? ` · ${e.evidence_ref}` : ''}</td>
                <td className="pr-3 text-xs">capturó {e.captured_by} · {when(e.captured_at)}{e.approved_by ? ` · aprobó ${e.approved_by}` : e.status === 'active' ? ' · por aprobar' : ''}{e.void_reason ? ` · anulada: ${e.void_reason}` : ''}</td>
                <td>{editable && e.status === 'active' && (
                  <form action={voidEntry} className="flex gap-1"><input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="entry_id" value={e.id} />
                    <input name="reason" required minLength={5} placeholder="motivo" className={`${input} w-28`} /><button className="text-xs text-rose-800">Anular</button></form>)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div>
        {pendingOthers > 0 && p.status !== 'CLOSED' && (
          <form action={approveEntries} className="mt-3"><input type="hidden" name="period_id" value={p.id} /><button className={btn}>Aprobar {pendingOthers} captura(s) de la otra persona</button></form>)}
      </section>

      {editable && (
        <section className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Capturar un monto</h2>
          <form action={captureEntry} className="mt-3 grid gap-2 sm:grid-cols-3">
            <input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="idempotency_key" value={crypto.randomUUID()} />
            <select name="account" required className={input}>{c.accounts.map((a) => <option key={a.key} value={a.key}>{a.label}</option>)}</select>
            <input name="amount" required inputMode="decimal" placeholder="Monto" className={input} />
            <select name="currency" defaultValue="MXN" className={input}>{c.currencies.map((x) => <option key={x}>{x}</option>)}</select>
            <input name="source" required minLength={3} placeholder="Fuente (p. ej. estado de cuenta BBVA)" className={`${input} sm:col-span-2`} />
            <input name="evidence" placeholder="Referencia del documento" className={input} />
            <input name="dimension" placeholder="Cuenta / detalle (opcional)" pattern="[a-z0-9_:\-]*" className={input} />
            <input name="note" placeholder="Nota" className={`${input} sm:col-span-2`} />
            <button className={`${btn} sm:col-span-3 sm:justify-self-start`}>Guardar captura</button>
          </form>
        </section>
      )}

      <section className="rounded-2xl border border-line bg-surface p-5">
        <h2 className="font-semibold text-ink">Estado del mes</h2>
        <div className="mt-3 flex flex-wrap gap-3">
          {editable && <form action={transitionPeriod}><input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="to" value="UNDER_REVIEW" /><button className={btn}>Mandar a revisión</button></form>}
          {p.status === 'UNDER_REVIEW' && (<>
            <form action={transitionPeriod} className="flex flex-wrap gap-2"><input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="to" value="CLOSED" />
              <input name="exception" placeholder="Excepción si faltan datos (DATA INCOMPLETE)" className={`${input} w-80`} /><button className={btn}>Cerrar el mes</button></form>
            <form action={transitionPeriod} className="flex gap-2"><input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="to" value="OPEN" />
              <input name="reason" required minLength={5} placeholder="Qué falta corregir" className={input} /><button className="text-sm text-ink-2">Regresar</button></form>
          </>)}
          {p.status === 'CLOSED' && (
            <form action={transitionPeriod} className="flex gap-2"><input type="hidden" name="period_id" value={p.id} /><input type="hidden" name="to" value="REOPENED" />
              <input name="reason" required minLength={10} placeholder="Motivo para reabrir" className={`${input} w-72`} /><button className="text-sm text-rose-800">Reabrir</button></form>)}
        </div>
        {p.exception_note && <p className="mt-2 text-sm text-ink-2">Excepción del cierre: {p.exception_note}</p>}
        <ul className="mt-3 text-xs text-muted">{c.events.map((ev, i) => <li key={i}>{when(ev.at)} · {ev.by}: {ev.from ?? '—'} → {ev.to}{ev.version ? ` (v${ev.version})` : ''}{ev.reason ? ` · ${ev.reason}` : ''}</li>)}</ul>
        {c.snapshots.length > 0 && <ul className="mt-2 text-xs text-muted">{c.snapshots.map((s) => <li key={s.version}>Foto del cierre v{s.version} · {when(s.taken_at)} · {s.by} · {s.hash.slice(0, 12)}…</li>)}</ul>}
      </section>
    </div>
  );
}
