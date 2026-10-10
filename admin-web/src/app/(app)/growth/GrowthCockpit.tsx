import Link from 'next/link';
import type { Cockpit, Kpi, KpiStatus, MarketBlock } from '@/lib/growth-cockpit';

// S-G1 Growth War Room. Every number says where it comes from; a missing input is shown as such, never as 0.
const MARKET_NAME: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto del mundo', TODOS: 'Todos' };
const STATUS: Record<KpiStatus, { label: string; cls: string }> = {
  OK: { label: '', cls: '' },
  DATA_INCOMPLETE: { label: 'DATOS INCOMPLETOS', cls: 'bg-gold-soft text-gold-strong' },
  NOT_CONFIGURED: { label: 'NO CONFIGURADO', cls: 'bg-surface-2 text-muted' },
  STALE: { label: 'DESACTUALIZADO', cls: 'bg-danger-soft text-danger' },
};
const PAY: Record<string, string> = {
  'woo-mercado-pago-custom': 'Mercado Pago (tarjeta)', 'woo-mercado-pago-basic': 'Mercado Pago (checkout)', 'woo-mercado-pago-pix': 'Mercado Pago',
  'ppcp-card-button-gateway': 'PayPal · tarjeta', 'ppcp-gateway': 'PayPal', epayco: 'ePayco', f360_prueba: 'Prueba Fuxia 360', 'sin método': 'Sin método (abandonado antes de elegir)',
};
const payName = (m: string) => PAY[m] ?? m;
const CONF: Record<string, string> = { ALTA: 'bg-success-soft text-success', MEDIA: 'bg-gold-soft text-gold-strong', BAJA: 'bg-surface-2 text-ink-2', 'SIN DATOS': 'bg-surface-2 text-muted' };

const money = (v: number | null | undefined, cur?: string) =>
  v == null ? '—' : `${cur === 'COP' ? 'COP ' : cur === 'USD' ? 'US' : ''}$${Math.round(v).toLocaleString('es-MX')}`;
const num = (v: number | null | undefined) => (v == null ? '—' : v.toLocaleString('es-MX'));
const pct = (v: number | null | undefined) => (v == null ? '—' : `${v.toLocaleString('es-MX')}%`);
function delta(v: number | null | undefined, p: number | null | undefined) {
  if (v == null || p == null) return null;
  if (p === 0) return v === 0 ? '= periodo anterior' : 'sin base anterior';
  const d = ((v - p) / p) * 100;
  return `${d >= 0 ? '▲' : '▼'} ${Math.abs(d).toFixed(0)}% vs anterior`;
}

function KpiCard({ label, k, fmt }: { label: string; k: Kpi; fmt: (v: number | null | undefined) => string }) {
  const st = STATUS[k.status];
  const d = k.status === 'OK' ? delta(k.value, k.prev) : null;
  return (
    <div className="atelier-card flex min-h-32 min-w-0 flex-col gap-1.5 rounded-[20px] p-4">
      <div className="flex flex-wrap items-start justify-between gap-1.5">
        <span className="kicker text-ink-2">{label}</span>
        {st.label && <span className={`rounded-full px-2 py-0.5 text-[9px] font-bold tracking-wide sm:text-[10px] sm:tracking-wider ${st.cls}`}>{st.label}</span>}
      </div>
      <span className={`tabular text-2xl font-semibold ${k.status === 'OK' || k.status === 'STALE' ? 'text-ink' : 'text-muted'}`}>{k.status === 'NOT_CONFIGURED' ? '—' : fmt(k.value)}</span>
      {d && <span className="text-xs text-ink-2">{d}</span>}
      <span className="mt-auto text-[11px] leading-snug text-muted">{k.note ? `${k.note} · ` : ''}{k.source}</span>
    </div>
  );
}

function Market({ m }: { m: MarketBlock }) {
  const k = m.kpis, c = m.currency;
  const cards: [string, Kpi, (v: number | null | undefined) => string][] = [
    ['Ingresos pagados', k.revenue, (v) => money(v, c)], ['Pedidos pagados', k.paid_orders, num], ['Ticket promedio', k.aov, (v) => money(v, c)],
    ['Conversión por sesión', k.cvr_session, pct], ['Gasto publicitario', k.spend, (v) => money(v, c)], ['CPA', k.cpa, (v) => money(v, c)],
    ['ROAS', k.roas, (v) => (v == null ? '—' : `${v}×`)], ['MER', k.mer, (v) => (v == null ? '—' : `${v}×`)],
    ['CPC', k.cpc, (v) => money(v, c)], ['CTR', k.ctr, pct], ['CPM', k.cpm, (v) => money(v, c)], ['Conversión por clic', k.cvr_click, pct],
  ];
  const top = Math.max(1, ...m.funnel.map((f) => f.value ?? 0));
  return (
    <section className="flex flex-col gap-5" data-testid={`cockpit-${m.market}`}>
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-display text-3xl text-ink">{MARKET_NAME[m.market]} <span className="text-lg text-muted">· {c}</span></h2>
        <span className="text-xs text-muted">Origen registrado en {m.attribution_coverage.attributed} de {m.attribution_coverage.paid} pedidos pagados</span>
      </div>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">{cards.map(([l, kk, f]) => <KpiCard key={l} label={l} k={kk} fmt={f} />)}</div>

      <div className="grid gap-4 lg:grid-cols-2">
        <div className="atelier-card rounded-[20px] p-5">
          <h3 className="text-lg font-semibold text-ink">Embudo</h3>
          <ul className="mt-3 flex flex-col gap-2.5">
            {m.funnel.map((f) => (
              <li key={f.stage}>
                <div className="flex items-baseline justify-between gap-2 text-sm">
                  <span className="text-ink">{f.stage}</span>
                  <span className="tabular font-semibold text-ink">{f.status === 'OK' ? num(f.value) : <span className={`rounded-full px-2 py-0.5 text-[10px] font-bold ${STATUS[f.status].cls}`}>{STATUS[f.status].label}</span>}</span>
                </div>
                <div className="mt-1 h-2 overflow-hidden rounded-full bg-line">{f.status === 'OK' && <div className="h-full rounded-full bg-gold" style={{ width: `${((f.value ?? 0) / top) * 100}%` }} />}</div>
                <span className="text-[11px] text-muted">{f.source}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="atelier-card rounded-[20px] p-5">
          <h3 className="text-lg font-semibold text-ink">Pedidos por método de pago</h3>
          <p className="text-xs text-muted">Pedidos que llegaron al pago · cuántos se pagaron</p>
          <table className="mt-3 w-full text-sm">
            <thead className="text-left text-[11px] uppercase tracking-wider text-muted"><tr><th className="py-1">Método</th><th className="text-right">Pedidos</th><th className="text-right">Pagados</th><th className="text-right">Sin pago</th></tr></thead>
            <tbody className="divide-y divide-line">
              {m.checkout.by_payment.map((p) => (
                <tr key={p.method}><td className="py-1.5 text-ink-2">{payName(p.method)}</td><td className="tabular text-right">{p.created}</td><td className="tabular text-right">{p.paid}</td>
                  <td className={`tabular text-right ${p.created > 0 && p.never_paid / p.created >= 0.3 ? 'font-semibold text-danger' : ''}`}>{p.never_paid}{p.created > 0 ? ` (${Math.round((p.never_paid / p.created) * 100)}%)` : ''}</td></tr>
              ))}
              {m.checkout.by_payment.length === 0 && <tr><td colSpan={4} className="py-2 text-muted">Sin pedidos en el periodo.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Breakdown title="Por canal" note="Atribución de WooCommerce (último toque, por pedido)" rows={m.by_channel.map((r) => [r.channel, r.paid_orders, money(r.revenue, c), r.orders_created])} />
        <Breakdown title="Por campaña" note="Campaña registrada en el pedido · gasto solo si está cargado" rows={m.by_campaign.map((r) => [`${r.campaign}${r.source ? ` · ${r.source}` : ''}`, r.paid_orders, money(r.revenue, c), r.spend == null ? 'sin gasto' : money(r.spend, c)])} last="Gasto" />
        <Breakdown title="Por producto" note="Pares pagados por modelo" rows={m.by_product.map((r) => [r.product, r.paid_units, money(r.revenue, c), null])} unit="pares" />
      </div>
    </section>
  );
}

function Breakdown({ title, note, rows, last = 'Pedidos', unit = 'pagados' }: { title: string; note: string; rows: [string, number, string, number | string | null][]; last?: string; unit?: string }) {
  return (
    <div className="atelier-card rounded-[20px] p-5">
      <h3 className="text-lg font-semibold text-ink">{title}</h3>
      <p className="text-xs text-muted">{note}</p>
      <ul className="mt-3 divide-y divide-line text-sm">
        {rows.map(([name, n, money, extra]) => (
          <li key={name} className="flex items-baseline justify-between gap-3 py-1.5">
            <span className="min-w-0 truncate text-ink-2" title={name}>{name}</span>
            <span className="tabular shrink-0 text-right"><b className="text-ink">{money}</b> <span className="text-muted">· {n} {unit}{extra != null && last !== 'Pedidos' ? ` · ${extra}` : extra != null ? ` · ${extra} ${last.toLowerCase()}` : ''}</span></span>
          </li>
        ))}
        {rows.length === 0 && <li className="py-2 text-muted">Sin datos en el periodo.</li>}
      </ul>
    </div>
  );
}

export function GrowthCockpit({ data, market }: { data: Cockpit; market: string }) {
  const presets = [['7 días', 6], ['30 días', 29], ['90 días', 89]] as const;
  const today = data.to;
  const from = (n: number) => new Date(new Date(`${today}T12:00:00`).getTime() - n * 86400000).toISOString().slice(0, 10);
  const shown = market === 'TODOS' ? data.markets.filter((m) => m.checkout.created > 0 || m.market !== 'ROW') : data.markets.filter((m) => m.market === market);
  const pill = (on: boolean) => `rounded-full px-4 py-2 text-sm ${on ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  const q = (o: Record<string, string>) => `/growth?${new URLSearchParams({ desde: data.from, hasta: data.to, mercado: market, ...o })}`;
  return (
    <div className="mt-6 flex flex-col gap-8">
      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center gap-2">
          {presets.map(([l, n]) => <Link key={l} href={q({ desde: from(n), hasta: today })} className={pill(data.from === from(n))}>{l}</Link>)}
          <form action="/growth" className="flex flex-wrap items-center gap-2 text-sm">
            <input type="hidden" name="mercado" value={market} />
            <input type="date" name="desde" defaultValue={data.from} className="rounded-xl border border-line bg-surface px-3 py-2" aria-label="Desde" />
            <input type="date" name="hasta" defaultValue={data.to} className="rounded-xl border border-line bg-surface px-3 py-2" aria-label="Hasta" />
            <button className="rounded-full border border-line bg-surface px-4 py-2 text-ink-2">Aplicar</button>
          </form>
        </div>
        <div className="flex flex-wrap gap-2">
          {['TODOS', 'MX', 'CO', 'ROW'].map((m) => <Link key={m} href={q({ mercado: m })} className={pill(market === m)}>{MARKET_NAME[m]}</Link>)}
        </div>
        <p className="text-xs text-muted">
          {data.from} → {data.to} · comparado con {data.prev_from} → {data.prev_to} ·
          Pedidos actualizados {data.freshness.last_success_at ? new Date(data.freshness.last_success_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', dateStyle: 'medium', timeStyle: 'short' }) : '—'}
          {data.freshness.status === 'STALE' && <b className="text-danger"> · DESACTUALIZADO</b>} · {data.consolidated.note}.
        </p>
      </div>

      <section className="atelier-card rounded-[24px] p-6" data-testid="cockpit-findings">
        <h2 className="font-display text-3xl text-ink">Hallazgos</h2>
        <p className="text-sm text-muted">Dónde se pierden las ventas, con la evidencia y qué tan seguros estamos. Sin recomendaciones automáticas.</p>
        <ul className="mt-4 flex flex-col gap-3">
          {data.findings.filter((f) => market === 'TODOS' || f.market === market || f.market === 'TODOS').map((f) => (
            <li key={`${f.market}-${f.kind}`} className="rounded-2xl border border-line bg-surface p-4">
              <div className="flex flex-wrap items-center gap-2">
                <span className={`rounded-full px-2.5 py-0.5 text-[10px] font-bold tracking-wider ${CONF[f.confidence] ?? ''}`}>CONFIANZA {f.confidence}</span>
                <span className="text-xs text-muted">{MARKET_NAME[f.market] ?? f.market}</span>
              </div>
              <p className="mt-1.5 font-semibold text-ink">{f.title}</p>
              <p className="text-sm text-ink-2">{f.evidence}</p>
              {f.detail && f.detail.length > 0 && (
                <p className="mt-1 text-xs text-ink-2">{f.detail.filter((x) => x.never_paid > 0).map((x) => `${payName(x.method)}: ${x.never_paid} de ${x.created} sin pago`).join(' · ')}</p>
              )}
              <p className="mt-1 text-[11px] text-muted">Fuente: {f.source}</p>
            </li>
          ))}
        </ul>
      </section>

      {shown.map((m) => <Market key={m.market} m={m} />)}
    </div>
  );
}
