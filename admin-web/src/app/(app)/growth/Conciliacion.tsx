import Link from 'next/link';
import { payName } from '@/lib/growth-cockpit';
import { DECISIONS, FINANCIAL, FLAG_NAME, GATEWAY, REC_STATE, WOO_STATUS, type RecCase, type RecFilters, type RecFlag, type RecRow, type RecSummary } from '@/lib/sales-rec';
import { AnalyticsForm, DecisionForm, EvidencePanel } from './ConciliacionForms';

// Conciliación de Ventas. Every order comes from Commerce Facts (no copy); each mark says why; each state says where it comes from.
const MARKET: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto del mundo' };
const money = (v: number | null | undefined, cur?: string | null) =>
  v == null ? '—' : `${cur === 'COP' ? 'COP ' : cur === 'USD' ? 'US' : ''}$${Number(v).toLocaleString('es-MX', { maximumFractionDigits: 2 })}`;
const when = (s: string | null | undefined) => (s ? new Date(s).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : '—');
const day = (s: string) => new Date(s).toLocaleDateString('es-MX', { timeZone: 'America/Mexico_City', day: '2-digit', month: 'short', year: '2-digit' });
const FLAG_CLS: Record<RecFlag['kind'], string> = {
  financiera: 'bg-danger-soft text-danger', no_concretado: 'bg-surface-2 text-ink-2', revision: 'bg-gold-soft text-gold-strong',
  reembolso: 'bg-gold-soft text-gold-strong', info: 'bg-surface-2 text-muted',
};
const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-sm outline-none focus:border-gold';

function qs(f: RecFilters, extra: Record<string, string | null> = {}) {
  const p = new URLSearchParams({ vista: 'conciliacion' });
  for (const [k, v] of Object.entries({ ...f, ...extra })) if (v) p.set(k, v);
  if (!p.has('conciliacion')) p.set('conciliacion', 'todos');   // no state filter = all (the page defaults to "por revisar")
  return `/growth?${p.toString()}`;
}
function State({ s }: { s: string }) {
  const x = REC_STATE[s] ?? { label: s, cls: 'bg-surface-2 text-ink-2' };
  return <span className={`inline-block rounded-full px-2.5 py-0.5 text-[11px] font-semibold ${x.cls}`}>{x.label}</span>;
}
function Flags({ flags }: { flags: RecFlag[] }) {
  return <span className="flex flex-wrap gap-1">{flags.map((f) => <span key={f.code} className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${FLAG_CLS[f.kind]}`}>{FLAG_NAME[f.code] ?? f.code}</span>)}</span>;
}

function Summary({ s, f }: { s: RecSummary; f: RecFilters }) {
  return (
    <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      {s.by_market.map((m) => (
        <div key={m.market} className="atelier-card rounded-[20px] p-4" data-testid={`rec-summary-${m.market}`}>
          <div className="flex items-baseline justify-between"><h3 className="text-lg font-semibold text-ink">{MARKET[m.market] ?? m.market}</h3><span className="text-xs text-muted">{m.currency} · {m.orders} pedidos</span></div>
          <div className="mt-3 grid grid-cols-3 gap-2 text-center">
            {([['Por revisar', m.pending, 'pendientes', null], ['Discrepancias financieras', m.financial_open, null, 'financiera'], ['Conflictos', m.conflicts, 'conflicto', null],
               ['No concretados', m.not_completed, 'todos', 'NO_CONCRETADO'], ['Posibles duplicados', m.duplicate_candidates, 'todos', 'POSIBLE_DUPLICADO'], ['Revisados', m.reviewed, 'revisado', null]] as const).map(([label, n, st, flag]) => (
              <Link key={label} href={qs({ ...f, mercado: m.market, conciliacion: st ?? 'todos', marca: flag }, { pedido: null })} className="rounded-xl bg-surface-2 px-1 py-2 hover:bg-gold-soft">
                <span className={`tabular block text-xl font-semibold ${n > 0 && (label.startsWith('Discrep') || label === 'Conflictos') ? 'text-danger' : 'text-ink'}`}>{n}</span>
                <span className="block text-[11px] leading-tight text-ink-2">{label}</span>
              </Link>
            ))}
          </div>
          {m.excluded > 0 && <p className="mt-2 text-xs text-muted">{m.excluded} excluido(s) de métricas por decisión autorizada</p>}
        </div>
      ))}
    </div>
  );
}

function Filters({ s, f }: { s: RecSummary; f: RecFilters }) {
  return (
    <form method="get" action="/growth" className="mt-6 grid grid-cols-2 gap-3 rounded-2xl border border-line bg-surface p-4 md:grid-cols-4 xl:grid-cols-8" data-testid="rec-filters">
      <input type="hidden" name="vista" value="conciliacion" />
      <label className="text-xs text-muted">Desde<input type="date" name="desde" defaultValue={f.desde ?? ''} className={field} /></label>
      <label className="text-xs text-muted">Hasta<input type="date" name="hasta" defaultValue={f.hasta ?? ''} className={field} /></label>
      <label className="text-xs text-muted">País<select name="mercado" defaultValue={f.mercado ?? ''} className={field}><option value="">Todos</option><option value="MX">México</option><option value="CO">Colombia</option><option value="ROW">Resto</option></select></label>
      <label className="text-xs text-muted">Estado Woo<select name="estado" defaultValue={f.estado ?? ''} className={field}><option value="">Todos</option>{s.statuses.map((x) => <option key={x} value={x}>{WOO_STATUS[x] ?? x}</option>)}</select></label>
      <label className="text-xs text-muted">Método de pago<select name="metodo" defaultValue={f.metodo ?? ''} className={field}><option value="">Todos</option>{s.methods.map((x) => <option key={x} value={x}>{x === 'sin_metodo' ? 'Sin método' : payName(x)}</option>)}</select></label>
      <label className="text-xs text-muted">Marca<select name="marca" defaultValue={f.marca ?? ''} className={field}><option value="">Todas</option><option value="financiera">Cualquier discrepancia financiera</option>
        {Object.entries(FLAG_NAME).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <label className="text-xs text-muted">Conciliación<select name="conciliacion" defaultValue={f.conciliacion ?? 'todos'} className={field}><option value="todos">Todos</option><option value="pendientes">Por revisar</option>
        {Object.entries(REC_STATE).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}</select></label>
      <label className="text-xs text-muted">Decisión<select name="decision" defaultValue={f.decision ?? ''} className={field}><option value="">Todas</option><option value="sin_decision">Sin decisión</option>
        {Object.entries(DECISIONS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <div className="col-span-2 flex gap-2 md:col-span-4 xl:col-span-8">
        <button className="rounded-full bg-ink px-5 py-2 text-sm text-surface">Filtrar</button>
        <Link href="/growth?vista=conciliacion" className="rounded-full border border-line px-5 py-2 text-sm text-ink-2">Limpiar</Link>
      </div>
    </form>
  );
}

function List({ rows, total, f }: { rows: RecRow[]; total: number; f: RecFilters }) {
  if (!rows.length) return <p className="mt-6 rounded-2xl border border-line bg-surface p-6 text-ink-2">No hay pedidos con estos filtros.</p>;
  const href = (r: RecRow) => qs(f, { pedido: `${r.target_id}:${r.woo_order_id}` });
  const tx = (r: RecRow) => r.evidence ? (r.evidence.transaction_ref ?? GATEWAY[r.evidence.gateway_result]) : 'sin consultar';
  return (
    <div className="mt-6">
      <p className="text-sm text-muted">{total} pedido(s){total > rows.length ? ` · mostrando ${rows.length}` : ''} · la clienta se ve al abrir el pedido (acceso restringido)</p>
      {/* mobile: cards */}
      <ul className="mt-3 flex flex-col gap-2 md:hidden" data-testid="rec-cards">
        {rows.map((r) => (
          <li key={`${r.target_id}:${r.woo_order_id}`}>
            <Link href={href(r)} className="block rounded-2xl border border-line bg-surface p-3">
              <div className="flex items-baseline justify-between gap-2"><span className="font-semibold text-ink">#{r.woo_order_id} · {r.market}</span><span className="tabular text-ink">{money(r.order_total, r.currency)}</span></div>
              <div className="mt-1 text-xs text-ink-2">{day(r.created_at)} · {WOO_STATUS[r.woo_status] ?? r.woo_status} · {r.payment_method ? payName(r.payment_method) : 'Sin método'}</div>
              <div className="mt-1 text-xs text-muted">{FINANCIAL[r.financial_state] ?? r.financial_state}</div>
              <div className="mt-2 flex flex-wrap items-center gap-1.5"><State s={r.rec_state} /><Flags flags={r.flags} />{r.decision && <span className="text-[11px] text-ink-2">· {DECISIONS[r.decision.decision]}</span>}</div>
            </Link>
          </li>
        ))}
      </ul>
      {/* desktop: table */}
      <div className="mt-3 hidden overflow-x-auto rounded-2xl border border-line bg-surface md:block">
        <table className="w-full text-sm" data-testid="rec-table">
          <thead className="bg-surface-2 text-left text-xs text-ink-2">
            <tr><th className="px-3 py-2">Pedido</th><th className="px-3 py-2">Fecha</th><th className="px-3 py-2">Clienta</th><th className="px-3 py-2 text-right">Total</th><th className="px-3 py-2">Estado Woo</th>
              <th className="px-3 py-2">Método</th><th className="px-3 py-2">Transacción</th><th className="px-3 py-2">Evidencia financiera</th><th className="px-3 py-2">Marcas</th><th className="px-3 py-2">Conciliación</th></tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={`${r.target_id}:${r.woo_order_id}`} className="border-t border-line align-top hover:bg-bg">
                <td className="px-3 py-2"><Link href={href(r)} className="font-semibold text-ink underline-offset-2 hover:underline">#{r.woo_order_id}</Link><span className="block text-xs text-muted">{r.market}</span></td>
                <td className="whitespace-nowrap px-3 py-2 text-ink-2">{day(r.created_at)}</td>
                <td className="px-3 py-2 text-xs text-muted">🔒 al abrir</td>
                <td className="tabular whitespace-nowrap px-3 py-2 text-right text-ink">{money(r.order_total, r.currency)}{r.refund_total > 0 && <span className="block text-xs text-danger">−{money(r.refund_total, r.currency)}</span>}</td>
                <td className="px-3 py-2 text-ink-2">{WOO_STATUS[r.woo_status] ?? r.woo_status}</td>
                <td className="px-3 py-2 text-ink-2">{r.payment_method ? payName(r.payment_method) : <span className="text-muted">Sin método</span>}</td>
                <td className="px-3 py-2 font-mono text-xs text-ink-2">{tx(r)}</td>
                <td className="px-3 py-2 text-xs text-ink-2">{FINANCIAL[r.financial_state] ?? r.financial_state}</td>
                <td className="px-3 py-2"><Flags flags={r.flags} /></td>
                <td className="px-3 py-2"><State s={r.rec_state} />{r.decision && <span className="mt-1 block text-xs text-ink-2">{DECISIONS[r.decision.decision]} · {r.decision.by}</span>}{r.excluded && <span className="block text-xs text-muted">Excluido de métricas</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function Box({ title, value, source, tone }: { title: string; value: string; source: string; tone?: 'danger' | 'ok' }) {
  return (
    <div className="rounded-2xl border border-line bg-bg p-3">
      <p className="kicker text-ink-2">{title}</p>
      <p className={`mt-1 text-[15px] font-semibold ${tone === 'danger' ? 'text-danger' : tone === 'ok' ? 'text-success' : 'text-ink'}`}>{value}</p>
      <p className="mt-1 text-[11px] leading-snug text-muted">{source}</p>
    </div>
  );
}

function CaseView({ c, f }: { c: RecCase; f: RecFilters }) {
  const ev = c.evidence_history[0];
  const dangerFin = ['CONTRADICTORIA', 'NO_EXISTE_EN_WOO', 'PAGO_SIN_TRANSACCION'].includes(c.financial_state);
  return (
    <section className="mt-6 rounded-[24px] border border-gold bg-surface p-4 md:p-6" data-testid="rec-case">
      <Link href={qs(f, { pedido: null })} className="text-sm text-ink-2">← Volver a la lista</Link>
      <div className="mt-2 flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-display text-3xl text-ink">Pedido #{c.woo_order_id} <span className="text-lg text-muted">· {MARKET[c.market] ?? c.market} · {c.currency}</span></h2>
        <span className="tabular text-2xl text-ink">{money(c.order_total, c.currency)}</span>
      </div>
      <p className="text-sm text-ink-2">Creado {when(c.created_at)} · {c.units} par(es) · {c.payment_method ? payName(c.payment_method) : 'Sin método de pago'}</p>
      {c.conflict && <p className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger" data-testid="rec-conflict">⚠ {c.conflict}</p>}

      <h3 className="mt-5 text-lg font-semibold text-ink">Por qué está aquí</h3>
      {c.flags.length ? (
        <ul className="mt-2 flex flex-col gap-2">{c.flags.map((x) => (
          <li key={x.code} className="flex flex-col gap-1 rounded-xl bg-bg p-3 sm:flex-row sm:items-start sm:gap-3">
            <span className={`w-fit shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold ${FLAG_CLS[x.kind]}`}>{FLAG_NAME[x.code] ?? x.code}</span>
            <span className="text-sm text-ink">{x.why}{x.candidates?.map((id) => <Link key={id} href={qs(f, { pedido: `${c.target_id}:${id}` })} className="ml-1 underline">ver #{id}</Link>)}
              {x.paid_order && <Link href={qs(f, { pedido: `${c.target_id}:${x.paid_order}` })} className="ml-1 underline">ver #{x.paid_order}</Link>}</span>
          </li>))}</ul>
      ) : <p className="mt-2 text-sm text-ink-2">Ninguna regla lo marcó: pedido pagado sin novedades.</p>}

      <h3 className="mt-5 text-lg font-semibold text-ink">Cinco estados, cada uno por separado</h3>
      <div className="mt-2 grid gap-2 sm:grid-cols-2 xl:grid-cols-5">
        <Box title="Estado en WooCommerce" value={WOO_STATUS[c.woo_status] ?? c.woo_status}
          source={`${c.facts?.source ?? 'Commerce Facts'} · capturado ${when(c.facts?.last_changed_at)}${c.paid_at ? ` · pago registrado ${when(c.paid_at)}` : ''}`} />
        <Box title="Evidencia financiera" value={FINANCIAL[c.financial_state] ?? c.financial_state} tone={dangerFin ? 'danger' : c.financial_state === 'COBRO_CON_TRANSACCION' ? 'ok' : undefined}
          source={ev ? `Consulta a WooCommerce (solo lectura) ${when(ev.at)} por ${ev.by} · huella ${ev.hash.slice(0, 10)}…` : 'Solo Commerce Facts: aún nadie consultó la pasarela en WooCommerce'} />
        <Box title="Clasificación humana" value={c.decision ? DECISIONS[c.decision.decision] : 'Sin decisión'}
          source={c.decision ? `${c.decision.by} · ${when(c.decision.at)}${c.decision.comment ? ` · “${c.decision.comment}”` : ''}` : 'Nadie lo ha clasificado'} />
        <Box title="Conciliación" value={(REC_STATE[c.rec_state] ?? { label: c.rec_state }).label} tone={['conflicto', 'pendiente_discrepancia', 'cambio_despues'].includes(c.rec_state) ? 'danger' : c.rec_state === 'revisado' ? 'ok' : undefined}
          source="Calculado: marcas + evidencia + decisión" />
        <Box title="Métricas de Growth" value={c.excluded ? 'Excluido' : 'Incluido'} source={c.exclusion_history[0] ? `${c.exclusion_history[0].by} · ${when(c.exclusion_history[0].at)} · “${c.exclusion_history[0].reason}”` : 'Sin cambios: cuenta según su estado de pago'} />
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        <div className="rounded-2xl border border-line p-4">
          <h3 className="text-lg font-semibold text-ink">Evidencia de la pasarela</h3>
          <EvidencePanel targetKey={c.target_key} orderId={c.woo_order_id} />
          {c.evidence_history.length > 0 && (
            <ul className="mt-3 flex flex-col gap-2 text-xs">{c.evidence_history.map((e) => (
              <li key={e.id} className="rounded-xl bg-bg p-2.5">
                <span className="font-semibold text-ink">{GATEWAY[e.gateway_result] ?? e.gateway_result}</span> · {e.result}
                <span className="mt-0.5 block text-muted">Fuente {e.source_ref} · Woo “{WOO_STATUS[e.woo_status] ?? e.woo_status}” · {e.payment_method ? payName(e.payment_method) : '—'} · {money(e.order_total, e.currency)}
                  {e.refund_total > 0 ? ` · reembolso ${money(e.refund_total, e.currency)}` : ''} · {e.by}, {when(e.at)} · huella {e.hash.slice(0, 12)}…</span>
              </li>))}</ul>
          )}
        </div>
        <div className="rounded-2xl border border-line p-4">
          <h3 className="text-lg font-semibold text-ink">Productos y origen</h3>
          <ul className="mt-2 flex flex-col gap-1 text-sm">{c.lines.map((l, i) => <li key={i} className="flex justify-between gap-2"><span className="text-ink">{l.quantity} × {l.product}</span><span className="tabular text-ink-2">{money(l.total, c.currency)}</span></li>)}</ul>
          {c.facts && <p className="mt-2 text-xs text-muted">Subtotal {money(c.facts.items_subtotal, c.currency)} · descuento {money(c.facts.discount_total, c.currency)} · envío {money(c.facts.shipping_total, c.currency)} · creado por {c.facts.created_via}</p>}
          <p className="mt-2 text-sm text-ink-2">Origen: {c.origin ? `${c.origin.channel}${c.origin.utm_campaign ? ` · campaña ${c.origin.utm_campaign}` : ''}${c.origin.device ? ` · ${c.origin.device}` : ''}` : 'sin atribución registrada'}</p>
          {c.duplicates.length > 0 && <div className="mt-3"><p className="text-sm font-semibold text-ink">Candidatos a duplicado</p>
            {c.duplicates.map((d) => <Link key={d.woo_order_id} href={qs(f, { pedido: `${d.target_id}:${d.woo_order_id}` })} className="mt-1 block text-sm underline">#{d.woo_order_id} · {day(d.created_at)} · {money(d.order_total, d.currency)} · {WOO_STATUS[d.woo_status] ?? d.woo_status}</Link>)}</div>}
        </div>
      </div>

      <div className="mt-5 grid gap-4 lg:grid-cols-2">
        <DecisionForm target={c.target_id} orderId={c.woo_order_id} latestEvidence={ev ? { id: ev.id, at: ev.at, label: GATEWAY[ev.gateway_result] ?? ev.gateway_result } : null}
          hasDecision={!!c.decision} candidates={c.flags.find((x) => x.code === 'POSIBLE_DUPLICADO')?.candidates ?? []} />
        <AnalyticsForm target={c.target_id} orderId={c.woo_order_id} excluded={c.excluded} />
      </div>

      {c.decision_history.length > 0 && (
        <div className="mt-5"><h3 className="text-lg font-semibold text-ink">Historial (no se puede editar ni borrar)</h3>
          <ul className="mt-2 flex flex-col gap-1.5 text-sm">{c.decision_history.map((d) => (
            <li key={d.id} className="rounded-xl bg-bg p-2.5"><span className="font-semibold text-ink">{DECISIONS[d.decision]}</span>{d.duplicate_of ? ` de #${d.duplicate_of}` : ''} · {d.by} · {when(d.at)}
              {d.comment && <span className="block text-ink-2">“{d.comment}”</span>}
              <span className="block text-xs text-muted">Vio: Woo “{WOO_STATUS[d.woo_status_seen] ?? d.woo_status_seen}”, evidencia “{FINANCIAL[d.financial_seen] ?? d.financial_seen}”{d.evidence_id ? ` · consulta #${d.evidence_id}` : ''}{d.supersedes ? ` · reemplaza a la decisión #${d.supersedes}` : ''}</span></li>))}
            {c.exclusion_history.map((x) => <li key={`x${x.id}`} className="rounded-xl bg-bg p-2.5"><span className="font-semibold text-ink">{x.action === 'exclude' ? 'Excluido de métricas' : 'Incluido otra vez en métricas'}</span> · {x.by} · {when(x.at)}<span className="block text-ink-2">“{x.reason}”</span></li>)}
          </ul></div>
      )}
    </section>
  );
}

export function Conciliacion({ summary, list, filters, detail }: { summary: RecSummary; list: { total: number; rows: RecRow[] }; filters: RecFilters; detail: RecCase | null }) {
  return (
    <div className="mt-8" data-testid="conciliacion">
      <h2 className="font-display text-3xl text-ink">Conciliación de ventas</h2>
      <p className="mt-1 max-w-3xl text-sm text-ink-2">Pedidos reales de la tienda en línea (Commerce Facts), separados por país. El sistema marca los casos raros y dice por qué; tú decides.
        Tu decisión no cambia WooCommerce ni el estado del cobro: una venta confirmada sin cobro comprobado se queda como conflicto.</p>
      <div className="mt-4"><Summary s={summary} f={filters} /></div>
      {detail && <CaseView c={detail} f={filters} />}
      <Filters s={summary} f={filters} />
      <List rows={list.rows} total={list.total} f={filters} />
    </div>
  );
}
