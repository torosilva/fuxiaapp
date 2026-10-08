import Link from 'next/link';
import { notFound } from 'next/navigation';
import { getBoardEarnin, type EarninTerms } from '@/lib/board';
import { actOnTerms, proposeTerms } from './actions';

// "Participación · earn-in" (Strategy & Board → Ownership). Shows the PROPOSED terms of Mario's participation and, per
// milestone year, target vs management target vs forecast vs actual (S-G0 revenue, Colombia excluded) with an INDICATIVE
// equity figure. Nothing here is a contract, a cap table or a valuation; Mario is a related party and never approves.
const money = (n: number | null | undefined) => (n === null || n === undefined ? '—' : `$${new Intl.NumberFormat('es-MX', { maximumFractionDigits: 0 }).format(n)}`);
const pct = (n: number | null | undefined, d = 1) => (n === null || n === undefined ? '—' : `${new Intl.NumberFormat('es-MX', { maximumFractionDigits: d }).format(n)}%`);
const when = (s: string) => new Date(s).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', dateStyle: 'short', timeStyle: 'short' });
const btn = 'rounded-full bg-ink px-4 py-2 text-sm font-semibold text-surface';
const ghost = 'rounded-full border border-line px-4 py-2 text-sm text-ink-2';
const input = 'rounded-xl border border-line bg-surface px-3 py-2 text-sm';
const LABEL: Record<string, string> = {
  NOT_RECORDED: 'SIN REGISTRAR', PROPOSED: 'PROPUESTA', ACCEPTED_FOR_TRACKING: 'ACEPTADA PARA SEGUIMIENTO', NOT_SIGNED: 'SIN FIRMAR',
  NOT_FUNDED: 'NO FONDEADO', PENDING_LEGAL_ASSIGNMENT: 'CESIÓN LEGAL PENDIENTE', PENDING_DEFINITION: 'MÍNIMO POR DEFINIR',
  DATA_INCOMPLETE: 'DATA INCOMPLETE', MEASURABLE_NOT_EVALUATED: 'POR EVALUAR', FUTURE: 'Futuro', IN_PROGRESS: 'En curso', ENDED: 'Terminado',
  APPROVED: 'Aprobada', REJECTED: 'Rechazada', DEFERRED: 'Pospuesta', WITHDRAWN: 'Retirada', SUPERSEDED: 'Sustituida',
};
const chip = (s: string) => `rounded-full px-2.5 py-0.5 text-xs font-semibold ${
  s === 'ACCEPTED_FOR_TRACKING' || s === 'APPROVED' ? 'bg-emerald-100 text-emerald-900'
  : s === 'PROPOSED' || s === 'PENDING_DEFINITION' || s === 'PENDING_LEGAL_ASSIGNMENT' || s === 'DEFERRED' ? 'bg-amber-100 text-amber-900'
  : s === 'NOT_FUNDED' || s === 'NOT_SIGNED' || s === 'DATA_INCOMPLETE' || s === 'REJECTED' ? 'bg-rose-100 text-rose-900' : 'bg-stone-100 text-stone-700'}`;

// Form defaults = the proposal presented to the Board (2026-10-08). Only defaults of an input: nothing is stored until submitted.
const PROPOSAL = {
  entity_label: 'Fuxia Ballerinas S.A. de C.V.', initial_pct: 20, cap_pct: 40, founder_min_pct: 60, cash_commitment: 500000,
  revenue_definition: 'Venta neta de producto pagada (tienda, ecommerce y app), neta de devoluciones, sin Colombia; MXN con tipo de cambio aprobado. Definitiva solo con estados financieros aprobados.',
  proposal_ref: 'https://claude.ai/code/artifact/50e7a032-eea0-44da-95c1-dc9708c3effd',
  milestones: [
    { year: 2027, revenue_target: 15000000, equity_pct: 8, partial_from: 9000000, gross_margin_min: null },
    { year: 2028, revenue_target: 22000000, equity_pct: 8, partial_from: 16000000, gross_margin_min: null },
    { year: 2029, revenue_target: 29000000, equity_pct: 2, partial_from: 22000000, gross_margin_min: null },
    { year: 2030, revenue_target: 36000000, equity_pct: 2, partial_from: 29000000, gross_margin_min: null },
  ],
};

function DecisionBox({ t, interested }: { t: EarninTerms; interested: boolean }) {
  const d = t.decision;
  const open = d.status === 'PROPOSED' || d.status === 'DEFERRED';
  return (
    <div className="rounded-xl border border-line p-4 text-sm">
      <div className="flex flex-wrap items-center gap-2"><b className="text-ink">{d.number} · {d.title}</b><span className={chip(d.status)}>{LABEL[d.status] ?? d.status}</span>
        <span className="rounded-full bg-violet-100 px-2.5 py-0.5 text-xs font-semibold text-violet-900">PARTE RELACIONADA: {d.interested.join(', ')}</span></div>
      <p className="mt-1 text-ink-2">{d.decision}</p>
      <p className="mt-1 text-xs text-muted">Propuso {d.proposed_by} · {when(d.created_at)}{d.approved_at ? ` · aprobó ${d.approved_by.join(', ')} el ${when(d.approved_at)}` : ''}</p>
      {open && (interested ? (
        <p className="mt-2 rounded-lg bg-violet-50 px-3 py-2 text-violet-900"><b>RELATED PARTY — CANNOT APPROVE.</b> Esta propuesta la aprueba o rechaza Carolina.</p>
      ) : (
        <form action={actOnTerms} className="mt-3 flex flex-wrap items-center gap-2">
          <input type="hidden" name="decision_id" value={d.id} />
          <input name="note" placeholder="Nota (opcional)" className={`${input} w-56`} />
          <button name="action" value="APPROVE" className={btn}>Aceptar para seguimiento</button>
          <button name="action" value="REJECT" className={ghost}>Rechazar</button>
          {d.status === 'PROPOSED' && <button name="action" value="DEFER" className={ghost}>Posponer</button>}
        </form>
      ))}
      {open && d.proposed_by_me && (
        <form action={actOnTerms} className="mt-2"><input type="hidden" name="decision_id" value={d.id} /><button name="action" value="WITHDRAW" className="text-xs text-rose-800">Retirar mi propuesta</button></form>
      )}
    </div>
  );
}

export default async function Participacion({ searchParams }: { searchParams: Promise<{ ok?: string; error?: string }> }) {
  const sp = await searchParams;
  const e = await getBoardEarnin();
  if (!e.ok) notFound();
  const t = e.terms;
  const pendingTerms = e.pending ?? (t && t.tracking_status === 'PROPOSED' ? t : null);
  const base = t ?? PROPOSAL;
  const interested = e.related_party.i_am_interested;
  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-col gap-2">
        <Link href="/estrategia" className="text-sm text-muted">← Strategy &amp; Board</Link>
        <h1 className="font-display text-5xl text-ink">Participación · earn-in</h1>
        <p className="max-w-3xl rounded-xl bg-amber-50 px-4 py-2 text-sm text-amber-900"><b>INDICATIVO.</b> {e.label} El porcentaje ganado solo se reconoce con el cierre anual aprobado por Carolina, el margen mínimo cumplido y documentos firmados.</p>
        <p className="text-sm text-ink-2">{e.related_party.rule}</p>
        {sp.ok && <p className="rounded-xl bg-emerald-50 px-4 py-2 text-sm text-emerald-900">{sp.ok}</p>}
        {sp.error && <p className="rounded-xl bg-rose-50 px-4 py-2 text-sm text-rose-900">{sp.error}</p>}
      </header>

      <section className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <div className="rounded-2xl border border-line bg-surface p-4">
          <div className="text-xs uppercase text-muted">Participación inicial</div>
          <div className="font-display text-4xl text-ink">{t ? pct(t.initial_pct, 2) : '—'}</div>
          <span className={chip(e.statuses.initial_equity)}>{LABEL[e.statuses.initial_equity]}</span>
        </div>
        <div className="rounded-2xl border border-line bg-surface p-4">
          <div className="text-xs uppercase text-muted">Aportación en efectivo</div>
          <div className="font-display text-4xl text-ink">{t ? money(t.cash_commitment) : '—'}</div>
          <span className={chip(e.statuses.cash)}>{LABEL[e.statuses.cash]}</span>
        </div>
        <div className="rounded-2xl border border-line bg-surface p-4">
          <div className="text-xs uppercase text-muted">Tecnología (PI específica de Fuxia)</div>
          <div className="mt-2"><span className={chip(e.statuses.technology)}>{LABEL[e.statuses.technology]}</span></div>
          <div className="mt-2"><span className={chip(e.statuses.legal)}>CONTRATO {LABEL[e.statuses.legal]}</span></div>
        </div>
        <div className="rounded-2xl border border-line bg-surface p-4">
          <div className="text-xs uppercase text-muted">Earn-in</div>
          {e.totals ? (
            <>
              <div className="font-display text-4xl text-ink">{pct(e.totals.indicative_total_pct, 2)}</div>
              <div className="text-xs text-muted">indicativo hoy · inicial {pct(e.totals.initial_pct)} + metas hasta {pct(e.totals.milestones_pct)} · tope {pct(e.totals.cap_pct)} · Carolina ≥ {pct(e.totals.founder_min_pct)}</div>
            </>
          ) : <div className="text-sm text-muted">Sin términos registrados.</div>}
        </div>
      </section>

      {pendingTerms && (
        <section className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Propuesta pendiente (v{pendingTerms.version})</h2>
          <div className="mt-2"><DecisionBox t={pendingTerms} interested={interested} /></div>
        </section>
      )}

      {t && (
        <section className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Equity Earn-In Tracker · {t.entity_label} · v{t.version} <span className={chip(t.tracking_status)}>{LABEL[t.tracking_status] ?? t.tracking_status}</span></h2>
          <p className="mt-1 text-xs text-muted">Ventas: {t.revenue_definition} Mercados excluidos: {t.excluded_markets.join(', ') || 'ninguno'}.</p>
          <div className="mt-3 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-xs uppercase text-muted"><tr>
                <th className="py-1 pr-3">Año</th><th className="pr-3 text-right">Meta para acciones</th><th className="pr-3 text-right">Meta de la dirección</th>
                <th className="pr-3 text-right">Pronóstico</th><th className="pr-3 text-right">Real (acumulado)</th><th className="pr-3 text-right">Cumplimiento</th>
                <th className="pr-3 text-right">Acciones (indicativo)</th><th className="pr-3">Filtro de margen</th><th>Cierre</th></tr></thead>
              <tbody>{e.years.map((y) => (
                <tr key={y.year} className="border-t border-line align-top" data-testid={`earnin-${y.year}`}>
                  <td className="py-1.5 pr-3 text-ink">{y.year}<div className="text-xs text-muted">{LABEL[y.period_state]}</div></td>
                  <td className="pr-3 text-right tabular-nums">{money(y.revenue_target)}<div className="text-xs text-muted">+{pct(y.equity_pct)} · desde {money(y.partial_from)}</div></td>
                  <td className="pr-3 text-right tabular-nums">{money(y.management_target)}</td>
                  <td className="pr-3 text-right tabular-nums">{y.forecast === null ? <span className="text-xs text-muted">sin pronóstico publicado</span> : money(y.forecast)}</td>
                  <td className="pr-3 text-right tabular-nums">{y.period_state === 'FUTURE' ? '—' : money(y.actual)}
                    {y.period_state !== 'FUTURE' && y.actual_basis === 'MXN_ONLY' && <div className="text-xs text-rose-800">solo MXN · falta FX aprobado: {y.revenue.fx_missing.join(', ')}</div>}</td>
                  <td className="pr-3 text-right tabular-nums">{y.attainment === null ? '—' : pct(y.attainment * 100)}</td>
                  <td className="pr-3 text-right tabular-nums">{y.period_state === 'FUTURE' ? (y.indicative_equity_forecast === null ? '—' : `${pct(y.indicative_equity_forecast, 2)} (pronóstico)`) : pct(y.indicative_equity_actual, 2)}
                    <div className="text-xs text-muted">de {pct(y.equity_pct)}</div></td>
                  <td className="pr-3"><span className={chip(y.margin_gate)}>{LABEL[y.margin_gate]}</span>{y.gross_margin_min !== null && <div className="text-xs text-muted">mín. {pct(y.gross_margin_min * 100)}</div>}</td>
                  <td className="text-xs text-muted">{y.months_closed}/12 meses cerrados<div>Ganado formal: —</div></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
          <p className="mt-2 text-xs text-muted">Real = ventas de Medición (S-G0) del año en curso o terminado. Indicativo = proporcional entre &quot;desde&quot; y la meta. &quot;Ganado formal&quot; queda vacío hasta el cierre anual aprobado por Carolina y los documentos firmados. Meta de la dirección = plan del consejo (solo los años cargados).</p>
          {!pendingTerms && <div className="mt-3"><DecisionBox t={t} interested={interested} /></div>}
        </section>
      )}

      {!pendingTerms && (
        <section className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">{t ? 'Registrar una propuesta nueva (sustituye a la actual al aprobarse)' : 'Registrar la propuesta de participación'}</h2>
          <p className="mt-1 text-sm text-ink-2">Queda como PROPUESTA hasta que la apruebe Carolina. Aprobarla la acepta para seguimiento; no la convierte en contrato.</p>
          <form action={proposeTerms} className="mt-3 flex flex-col gap-3">
            <input type="hidden" name="idempotency_key" value={crypto.randomUUID()} />
            <div className="grid gap-2 sm:grid-cols-3">
              <label className="flex flex-col text-xs text-muted sm:col-span-3">Sociedad<input name="entity_label" required defaultValue={base.entity_label} className={input} /></label>
              <label className="flex flex-col text-xs text-muted">Participación inicial (%)<input name="initial_pct" required inputMode="decimal" defaultValue={base.initial_pct} className={input} /></label>
              <label className="flex flex-col text-xs text-muted">Tope de Mario antes de rondas (%)<input name="cap_pct" required inputMode="decimal" defaultValue={base.cap_pct} className={input} /></label>
              <label className="flex flex-col text-xs text-muted">Mínimo de la fundadora (%)<input name="founder_min_pct" required inputMode="decimal" defaultValue={base.founder_min_pct} className={input} /></label>
              <label className="flex flex-col text-xs text-muted">Aportación en efectivo (MXN)<input name="cash_commitment" inputMode="decimal" defaultValue={base.cash_commitment ?? ''} className={input} /></label>
              <label className="flex flex-col text-xs text-muted sm:col-span-2">Liga a la propuesta escrita<input name="proposal_ref" type="url" defaultValue={base.proposal_ref ?? ''} className={input} /></label>
              <label className="flex flex-col text-xs text-muted sm:col-span-3">Cómo se miden las ventas<textarea name="revenue_definition" required rows={2} defaultValue={base.revenue_definition} className={input} /></label>
              <fieldset className="flex flex-wrap gap-3 text-sm text-ink-2 sm:col-span-3"><legend className="text-xs text-muted">Mercados excluidos</legend>
                {['CO', 'ROW', 'MX'].map((mk) => <label key={mk} className="flex items-center gap-1"><input type="checkbox" name="excluded" value={mk} defaultChecked={t ? t.excluded_markets.includes(mk) : mk === 'CO'} />{mk === 'CO' ? 'Colombia' : mk === 'ROW' ? 'Resto del mundo' : 'México'}</label>)}
              </fieldset>
            </div>
            <div className="overflow-x-auto">
              <table className="text-sm">
                <thead className="text-xs uppercase text-muted"><tr><th className="pr-2 text-left">Año</th><th className="pr-2 text-left">Meta de ventas (MXN)</th><th className="pr-2 text-left">Acciones (%)</th><th className="pr-2 text-left">Proporcional desde (MXN)</th><th className="text-left">Margen bruto mín. (%)</th></tr></thead>
                <tbody>{[0, 1, 2, 3, 4, 5].map((i) => {
                  const m = base.milestones[i];
                  return (
                    <tr key={i}>
                      <td className="pr-2 py-1"><input name={`m${i}_year`} inputMode="numeric" defaultValue={m?.year ?? ''} className={`${input} w-20`} /></td>
                      <td className="pr-2"><input name={`m${i}_target`} inputMode="decimal" defaultValue={m?.revenue_target ?? ''} className={`${input} w-36`} /></td>
                      <td className="pr-2"><input name={`m${i}_pct`} inputMode="decimal" defaultValue={m?.equity_pct ?? ''} className={`${input} w-20`} /></td>
                      <td className="pr-2"><input name={`m${i}_from`} inputMode="decimal" defaultValue={m?.partial_from ?? ''} className={`${input} w-36`} /></td>
                      <td><input name={`m${i}_margin`} inputMode="decimal" placeholder="por definir" defaultValue={m?.gross_margin_min === null || m?.gross_margin_min === undefined ? '' : m.gross_margin_min * 100} className={`${input} w-28`} /></td>
                    </tr>
                  );
                })}</tbody>
              </table>
            </div>
            <button className={`${btn} self-start`}>Registrar propuesta</button>
          </form>
        </section>
      )}

      {e.history.length > 0 && (
        <section className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Historial de propuestas</h2>
          <ul className="mt-2 text-sm text-ink-2">{e.history.map((h) => (
            <li key={h.version} className="flex flex-wrap gap-2 border-t border-line py-1.5">v{h.version} · {pct(h.initial_pct)} inicial · tope {pct(h.cap_pct)} · {h.decision_number}
              <span className={chip(h.decision_status)}>{LABEL[h.decision_status] ?? h.decision_status}</span><span className="text-xs text-muted">{h.created_by} · {when(h.created_at)}</span></li>
          ))}</ul>
        </section>
      )}
    </div>
  );
}
