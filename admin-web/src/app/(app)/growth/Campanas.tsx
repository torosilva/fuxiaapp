import Link from 'next/link';
import type { CampaignVerdict, GrowthCampaigns } from '@/lib/growth-cockpit';

// S-G2 · Campañas: ¿qué campaña de Meta se paga sola? Gasto (Meta API) contra ventas pagadas cuyo último clic fue esa campaña.
// Sin tipo de cambio aprobado, COP y USD se muestran en su moneda y no se calcula "ingreso ÷ gasto".
const MARKET_NAME: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto', UNKNOWN: '—' };
const VERDICT: Record<CampaignVerdict, { label: string; cls: string }> = {
  recupera: { label: 'Recupera lo gastado', cls: 'bg-success-soft text-success' },
  no_recupera: { label: 'No recupera', cls: 'bg-gold-soft text-gold-strong' },
  sin_ventas: { label: 'Sin ventas', cls: 'bg-danger-soft text-danger' },
  falta_tc: { label: 'Vende en COP · falta tipo de cambio', cls: 'bg-surface-2 text-ink-2' },
  sin_gasto: { label: 'Sin gasto en el periodo', cls: 'bg-surface-2 text-muted' },
};

// War Room channel names → plain words for this view (the classification itself is unchanged).
const CHANNEL: Record<string, string> = { 'Meta (UTM no pagado)': 'Instagram / Facebook orgánico (bio, historias)', 'Meta pagado': 'Anuncios de Meta', 'Búsqueda orgánica': 'Google orgánico' };
const mxn = (v: number | null | undefined) => (v == null ? '—' : `$${Math.round(v).toLocaleString('es-MX')}`);
const byCur = (m: Record<string, number>) => {
  const parts = Object.entries(m).filter(([, v]) => v > 0).sort(([a], [b]) => (a === 'MXN' ? -1 : b === 'MXN' ? 1 : a.localeCompare(b)))
    .map(([c, v]) => `${c === 'MXN' ? '' : `${c} `}$${Math.round(v).toLocaleString('es-MX')}`);
  return parts.length ? parts.join(' + ') : '$0';
};
const day = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('es-MX', { day: 'numeric', month: 'short' });
const shift = (d: string, n: number) => { const x = new Date(`${d}T12:00:00Z`); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); };

function Card({ label, value, note }: { label: string; value: string; note?: string }) {
  return (
    <div className="atelier-card flex min-h-28 min-w-0 flex-col gap-1.5 rounded-[20px] p-4">
      <span className="kicker text-ink-2">{label}</span>
      <span className="tabular text-2xl font-semibold text-ink">{value}</span>
      {note && <span className="mt-auto text-[11px] leading-snug text-muted">{note}</span>}
    </div>
  );
}

export function Campanas({ data, today }: { data: GrowthCampaigns; today: string }) {
  const t = data.totals;
  const ret = t.spend && t.ad_revenue_mxn != null ? t.ad_revenue_mxn / t.spend : null;
  const stale = t.spend_last_day && shift(t.spend_last_day, 2) < today ? t.spend_last_day : null;
  const noFx = t.no_fx_currencies.length > 0;
  const lost = data.campaigns.filter((c) => c.verdict === 'sin_ventas').reduce((s, c) => s + (c.spend ?? 0), 0);
  const preset = (label: string, from: string) => {
    const active = data.from === from && data.to === today;
    return <Link key={label} href={`/growth?vista=campanas&desde=${from}&hasta=${today}`}
      className={`rounded-full px-4 py-1.5 text-sm ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>{label}</Link>;
  };
  return (
    <div className="mt-8" data-testid="growth-campanas">
      <div className="flex flex-wrap items-center gap-2">
        {preset('30 días', shift(today, -29))}{preset('90 días', shift(today, -89))}{preset('Último año', shift(today, -364))}
        <span className="text-sm text-muted">{day(data.from)} – {day(data.to)}</span>
      </div>

      {stale && (
        <p className="mt-4 rounded-xl bg-danger-soft p-3 text-sm text-danger" data-testid="campanas-stale">
          El gasto de Meta no se ha actualizado desde el {day(stale)}: lo gastado después de esa fecha no aparece aquí.
        </p>
      )}

      <div className="mt-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Card label="Gastado en Meta" value={mxn(t.spend)} note="MXN · México y Colombia en la misma cuenta" />
        <Card label="Ventas en línea" value={`${t.paid_orders}`} note={byCur(t.revenue_by_currency)} />
        <Card label="Vendido por anuncios" value={`${t.ad_orders}`} note={t.ad_revenue_mxn != null ? `${mxn(t.ad_revenue_mxn)} · último clic en un anuncio` : 'Incluye ventas en COP sin tipo de cambio'} />
        <Card label="Por cada $1 en anuncios" value={ret != null ? `$${ret.toFixed(2)}` : '—'}
          note={ret != null ? 'vendido por anuncios ÷ gastado (sin costo del producto)' : 'Falta tipo de cambio aprobado para COP'} />
      </div>
      {lost > 0 && <p className="mt-3 text-sm text-ink"><strong>{mxn(lost)}</strong> se gastaron en campañas que no cerraron ninguna venta en este periodo.</p>}
      {noFx && <p className="mt-1 text-xs text-muted">Sin tipo de cambio aprobado para {t.no_fx_currencies.join(' y ')}: esas ventas se muestran en su moneda y no se convierten.</p>}

      <h2 className="font-display mt-10 text-3xl text-ink">Campañas</h2>
      <p className="mt-1 text-sm text-ink-2">Cada campaña con lo que gastó y lo que vendió. Una venta cuenta para la campaña si fue el último clic antes de comprar.</p>
      <div className="mt-4 overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="text-xs text-muted">
            <tr><th className="py-1.5 pr-2 text-left font-normal">Campaña</th><th className="py-1.5 pl-3 text-right font-normal">Gasto</th>
              <th className="py-1.5 pl-3 text-right font-normal">Clics</th><th className="py-1.5 pl-3 text-right font-normal">Ventas</th>
              <th className="py-1.5 pl-3 text-right font-normal">Vendido</th><th className="py-1.5 pl-3 text-right font-normal">Por $1</th>
              <th className="py-1.5 pl-3 text-left font-normal" /></tr>
          </thead>
          <tbody>
            {data.campaigns.map((c) => (
              <tr key={c.campaign_id} className="border-t border-line align-top" data-testid="campana-row">
                <td className="py-2 pr-2"><span className="text-ink">{c.name}</span>
                  <span className="block text-[11px] text-muted">{c.market ? `${MARKET_NAME[c.market] ?? c.market} · ` : ''}{c.first_day && c.last_day ? `${day(c.first_day)} – ${day(c.last_day)}` : c.campaign_id}</span></td>
                <td className="tabular py-2 pl-3 text-right">{mxn(c.spend)}</td>
                <td className="tabular py-2 pl-3 text-right text-ink-2">{c.clicks == null ? '—' : c.clicks.toLocaleString('es-MX')}</td>
                <td className="tabular py-2 pl-3 text-right">{c.paid_orders}</td>
                <td className="tabular py-2 pl-3 text-right">{c.paid_orders ? byCur(c.revenue_by_currency) : '—'}</td>
                <td className="tabular py-2 pl-3 text-right font-semibold">{c.return != null ? `$${c.return.toFixed(2)}` : '—'}</td>
                <td className="py-2 pl-3"><span className={`whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-semibold ${VERDICT[c.verdict].cls}`}>{VERDICT[c.verdict].label}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="font-display mt-12 text-3xl text-ink">Ventas por origen</h2>
      <p className="mt-1 text-sm text-ink-2">De dónde llegó cada clienta que pagó (último clic antes de comprar).</p>
      <table className="mt-4 w-full text-sm">
        <thead className="text-xs text-muted"><tr><th className="py-1.5 text-left font-normal">Origen</th><th className="py-1.5 pl-3 text-right font-normal">Ventas</th>
          <th className="py-1.5 pl-3 text-right font-normal">Vendido</th></tr></thead>
        <tbody>
          {data.channels.map((c) => (
            <tr key={c.channel} className="border-t border-line" data-testid="origen-row">
              <td className="py-2 text-ink">{CHANNEL[c.channel] ?? c.channel}</td><td className="tabular py-2 pl-3 text-right">{c.paid_orders}</td>
              <td className="tabular py-2 pl-3 text-right">{byCur(c.revenue_by_currency)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p className="mt-6 text-[11px] leading-relaxed text-muted">
        Fuentes: {data.sources.sales} · {data.sources.origin} · {data.sources.spend} · {data.sources.fx}. Solo cuenta el último clic: un anuncio que
        hizo que la clienta conociera la marca y regresara después como directo no le suma al anuncio. “Por $1” no descuenta el costo del producto.
      </p>
    </div>
  );
}
