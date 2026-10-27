import { KPI, PARTY, STATUS, type Experiment, type ExperimentsList, type Measure } from '@/lib/growth-p0';
import { ExperimentActions, ExperimentDraft } from './ExperimentForms';

// Growth → Experimentos (P0-B, 06_EXPERIMENTS.md). Past results and each party's record come first, then what is open.
// Results are computed by the database from paid Woo orders; "observed attribution" is never shown as proven cause.
const MARKET: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto', ALL: 'Todos' };
const day = (d: string | null) => (d ? new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const thr = (t: Experiment['success_threshold']) => (t ? `${t.op} ${t.value.toLocaleString('es-MX')} (mín. ${t.min_sample} ventas)` : 'sin definir');
const val = (m: Measure) => (m.kpi_value == null ? '—' : `${m.kpi_currency ? '$' : ''}${Number(m.kpi_value).toLocaleString('es-MX')}${m.kpi_currency && m.kpi_currency !== 'MXN' ? ` ${m.kpi_currency}` : ''}`);
const DECISION: Record<string, string> = { SCALE: 'Escalar', ITERATE: 'Ajustar y repetir', KILL: 'Matar', NONE: 'Ninguna' };

function Result({ m, label }: { m: Measure; label: string }) {
  if (m.status !== 'OK') return <p className="mt-2 text-xs text-muted">{label}: todavía no empieza.</p>;
  return (
    <div className="mt-3 rounded-xl border border-line bg-bg p-3 text-sm" data-testid="exp-result">
      <p className="text-ink"><b>{label}:</b> {KPI[m.kpi as Experiment['primary_kpi']]} = <b>{val(m)}</b> con {m.sample} ventas pagadas · {day(m.from!)} – {day(m.to!)}
        {m.success_met ? ' · cumple la meta de éxito' : ''}{m.kill_met ? ' · llegó al criterio para cancelar' : ''}</p>
      <p className="mt-1 text-xs text-ink-2">Mercado en el periodo: {m.market_paid_orders} ventas pagadas; los {m.days} días anteriores: {m.baseline_paid_orders}.
        {m.attributed_paid_orders != null ? ` Con último clic en las campañas del experimento: ${m.attributed_paid_orders}.` : ''}
        {m.spend_mxn != null ? ` Gasto en esas campañas: $${Math.round(m.spend_mxn).toLocaleString('es-MX')} MXN.` : ''}</p>
      <p className="mt-1 text-[11px] text-muted">{m.evidence_note}</p>
    </div>
  );
}

export function Experimentos({ data }: { data: ExperimentsList }) {
  const closed = data.experiments.filter((e) => ['WINNER', 'LOSER', 'INCONCLUSIVE', 'STOPPED', 'ARCHIVED'].includes(e.status));
  const open = data.experiments.filter((e) => !closed.includes(e));
  return (
    <div className="mt-8" data-testid="growth-experimentos">
      <p className="max-w-3xl text-sm text-ink-2">Cada idea que pide dinero se escribe aquí antes de gastar: hipótesis, responsable, presupuesto, meta de éxito, criterio para
        cancelar y fecha de revisión. Al aprobarse queda fija. El resultado lo calcula Fuxia 360 con ventas pagadas de WooCommerce, con la misma regla para todos.</p>

      <h2 className="font-display mt-8 text-3xl text-ink">Récord por persona</h2>
      {data.track_record.length === 0 ? <p className="mt-2 text-sm text-muted">Todavía no hay experimentos.</p> : (
        <div className="mt-4 overflow-x-auto"><table className="w-full min-w-[720px] text-sm" data-testid="exp-track">
          <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Quién</th><th className="py-1.5 pl-3 text-right font-normal">Propuso</th>
            <th className="py-1.5 pl-3 text-right font-normal">Ganaron</th><th className="py-1.5 pl-3 text-right font-normal">Perdieron</th>
            <th className="py-1.5 pl-3 text-right font-normal">Sin conclusión</th><th className="py-1.5 pl-3 text-right font-normal">Detenidos</th>
            <th className="py-1.5 pl-3 text-right font-normal">Abiertos</th><th className="py-1.5 pl-3 text-right font-normal">Responsable de</th>
            <th className="py-1.5 pl-3 text-right font-normal">Presupuesto aprobado</th></tr></thead>
          <tbody>{data.track_record.map((t) => (
            <tr key={t.party} className="border-t border-line"><td className="py-2 text-ink">{PARTY[t.party]}</td><td className="tabular py-2 pl-3 text-right">{t.proposed}</td>
              <td className="tabular py-2 pl-3 text-right text-success">{t.winner}</td><td className="tabular py-2 pl-3 text-right text-danger">{t.loser}</td>
              <td className="tabular py-2 pl-3 text-right">{t.inconclusive}</td><td className="tabular py-2 pl-3 text-right">{t.stopped}</td>
              <td className="tabular py-2 pl-3 text-right">{t.open}</td><td className="tabular py-2 pl-3 text-right">{t.responsible}</td>
              <td className="tabular py-2 pl-3 text-right">{t.budget_mxn != null ? `$${Math.round(t.budget_mxn).toLocaleString('es-MX')}` : '—'}</td></tr>))}</tbody>
        </table></div>
      )}

      {closed.length > 0 && <>
        <h2 className="font-display mt-10 text-3xl text-ink">Resultados anteriores</h2>
        <p className="mt-1 text-sm text-ink-2">Antes de proponer algo nuevo, revisa qué ya se probó.</p>
        <div className="mt-4 flex flex-col gap-4">{closed.map((e) => <Card key={e.id} e={e} canApprove={data.can_approve} />)}</div>
      </>}

      <h2 className="font-display mt-10 text-3xl text-ink">Abiertos</h2>
      <div className="mt-4"><ExperimentDraft /></div>
      <div className="mt-4 flex flex-col gap-4">{open.map((e) => <Card key={e.id} e={e} canApprove={data.can_approve} />)}</div>
    </div>
  );
}

function Card({ e, canApprove }: { e: Experiment; canApprove: boolean }) {
  const s = STATUS[e.verdict && e.status === 'ARCHIVED' ? e.verdict : e.status];
  return (
    <div className="atelier-card min-w-0 break-words rounded-[20px] p-5" data-testid="exp-card">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-xs text-muted">{e.code}</span>
        <span className={`rounded-full px-2 py-0.5 text-[11px] font-semibold ${s.cls}`}>{s.label}{e.status === 'ARCHIVED' ? ' · archivado' : ''}</span>
        <span className="text-xs text-muted">{MARKET[e.market]} · propone {PARTY[e.proposed_by]} · responsable {PARTY[e.responsible]}{e.responsible_note ? ` (${e.responsible_note})` : ''}</span>
      </div>
      <h3 className="mt-2 text-lg font-semibold text-ink">{e.name}</h3>
      <p className="mt-1 text-sm text-ink-2">{e.hypothesis}</p>
      <p className="mt-2 text-xs text-ink-2">Cambia: {e.primary_variable} · Se mide con: {KPI[e.primary_kpi]} · Éxito {thr(e.success_threshold)} · Cancelar {thr(e.kill_threshold)} ·
        {' '}{day(e.start_date)} → revisión {day(e.end_date)} · Presupuesto {e.budget != null ? `$${e.budget.toLocaleString('es-MX')} ${e.budget_currency}` : 'sin definir'}
        {e.campaign_ids.length ? ` · Campañas ${e.campaign_ids.join(', ')}` : ''}</p>
      {e.approved_by_name && <p className="mt-1 text-[11px] text-muted">Aprobado por {e.approved_by_name} el {day(e.approved_at)} · creado por {e.created_by_name}</p>}
      {e.live && <Result m={e.live} label="Hasta hoy" />}
      {e.result && <Result m={e.result} label="Resultado al cierre" />}
      {e.learning && <p className="mt-2 text-sm text-ink"><b>Aprendizaje:</b> {e.learning}</p>}
      {e.stop_reason && <p className="mt-1 text-sm text-ink-2"><b>Se detuvo:</b> {e.stop_reason}</p>}
      {e.decision && <p className="mt-1 text-sm text-ink"><b>Decisión:</b> {DECISION[e.decision]}</p>}
      {e.status === 'DRAFT' && <div className="mt-3"><ExperimentDraft exp={e} /></div>}
      <ExperimentActions exp={e} canApprove={canApprove} />
      <details className="mt-3 text-xs text-muted"><summary className="cursor-pointer">Historial ({e.history.length})</summary>
        <ul className="mt-2 flex flex-col gap-1">{e.history.map((h, i) => (
          <li key={i}>{new Date(h.at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })} · {h.by} · {h.field ? `cambió ${h.field}` : `${h.from ?? '—'} → ${h.to}`}{h.reason ? ` · ${h.reason}` : ''}</li>))}</ul>
      </details>
    </div>
  );
}
