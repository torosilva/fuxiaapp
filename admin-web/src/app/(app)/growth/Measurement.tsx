import type { HealthStatus, Kpi, MeasurementTruth } from '@/lib/measurement';
import { fecha } from '@/lib/format';
import { SpendUpload } from './SpendUpload';

// S-G0 · Medición: is each source healthy, what does Fuxia 360 know, and what is still missing. Real data only: a missing
// input is shown as "Faltan datos" with the reason — never as 0. Amounts always in their ORIGINAL currency.
const STATUS: Record<HealthStatus, { label: string; cls: string }> = {
  HEALTHY: { label: 'Sana', cls: 'bg-gold-soft text-ink' },
  DEGRADED: { label: 'Con fallas', cls: 'bg-gold/30 text-ink' },
  STALE: { label: 'Atrasada', cls: 'bg-danger/10 text-danger' },
  NOT_CONFIGURED: { label: 'Sin conectar', cls: 'border border-line text-muted' },
  ERROR: { label: 'Error', cls: 'bg-danger/15 text-danger' },
};
const CHANNEL: Record<string, string> = { online: 'En línea', store: 'Tienda (Fuxia 360)', legacy_store: 'Tienda (histórico, LEGACY_IMPORT)' };
const CAPTURE: Record<string, string> = { woo_realtime_webhook: 'Tiempo real (webhook)', woo_reconciliation_recovered: 'Recuperado por conciliación',
  woo_history_import: 'Importación histórica Woo', f360_store_rpc: 'Venta registrada en la app', LEGACY_IMPORT: 'LEGACY_IMPORT', test_fixture: 'Prueba' };
const TIMING: Record<string, string> = { realtime: 'Tiempo real', historical_import: 'Importación histórica', legacy_import: 'Legado (LEGACY_IMPORT)', test: 'Prueba' };
const money = (n: number | null | undefined, currency: string) =>
  n == null ? '—' : new Intl.NumberFormat('es-MX', { style: 'currency', currency, maximumFractionDigits: currency === 'COP' ? 0 : 2 }).format(n);
const reason = (r: string) => r.replace(/_/g, ' ');

function KpiCard({ title, k, money: isMoney }: { title: string; k: Kpi; money?: boolean }) {
  return (
    <div className="rounded-2xl border border-line bg-surface p-4" data-testid={`kpi-${title}`}>
      <p className="text-sm text-muted">{title}</p>
      {k.status === 'OK' && k.value != null ? (
        <p className="mt-1 font-display text-3xl text-ink tabular-nums">{isMoney ? money(k.value, 'MXN') : k.value.toLocaleString('es-MX')}</p>
      ) : (
        <>
          <p className="mt-1 text-lg text-danger">DATA INCOMPLETE</p>
          <p className="mt-1 text-xs text-muted">Falta: {(k.missing ?? []).map(reason).join(' · ')}</p>
        </>
      )}
      {k.basis ? <p className="mt-1 text-xs text-muted">{k.basis}</p> : null}
    </div>
  );
}

export function Measurement({ data, canUpload }: { data: MeasurementTruth; canUpload: boolean }) {
  const th = 'px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted';
  const td = 'px-3 py-2 text-[15px] text-ink tabular-nums';
  const recon = data.q2_q3_reconciliation.targets;
  return (
    <div className="mt-6" data-testid="measurement">
      <p className="max-w-3xl text-ink-2">
        Salud de cada fuente de datos y lo que Fuxia 360 sabe hoy de las ventas pagadas. Si falta un dato, se dice qué falta; nunca se muestra 0.
        {data.includes_test_data ? ' Incluye datos de prueba (esta base no tiene tienda de producción).' : ''}
      </p>

      <h2 className="font-display mt-8 text-3xl text-ink">Salud de la medición</h2>
      <div className="mt-3 overflow-x-auto rounded-2xl border border-line bg-surface">
        <table className="w-full min-w-[760px]">
          <thead><tr><th className={th}>Fuente</th><th className={th}>Estado</th><th className={th}>Último éxito</th><th className={th}>Detalle</th></tr></thead>
          <tbody>
            {data.health.map((s) => (
              <tr key={s.key} className="border-t border-line" data-testid={`health-${s.key}`}>
                <td className={td}>{s.label}</td>
                <td className={td}><span className={`rounded-full px-3 py-1 text-sm ${STATUS[s.status].cls}`}>{STATUS[s.status].label} · {s.status}</span></td>
                <td className={td}>{s.last_success_at ? fecha(s.last_success_at) : '—'}</td>
                <td className="px-3 py-2 text-sm text-ink-2">{s.reasons.length ? s.reasons.map(reason).join(' · ') : 'Sin observaciones'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2 className="font-display mt-10 text-3xl text-ink">Conciliación Woo ↔ Fuxia 360</h2>
      <div className="mt-3 grid gap-3 md:grid-cols-2">
        {recon.length === 0 ? <p className="text-ink-2">Ningún canal manda pedidos a Fuxia 360.</p> : recon.map((t) => {
          const st = t.last_run?.stats ?? {};
          return (
            <div key={t.target} className="rounded-2xl border border-line bg-surface p-4 text-[15px] text-ink" data-testid="reconciliation">
              <p className="font-medium">{t.target} · <span className={`rounded-full px-3 py-0.5 text-sm ${STATUS[t.status].cls}`}>{t.status}</span></p>
              <p className="mt-2">Última revisión: {t.last_run ? `${fecha(t.last_run.started_at)} (${t.last_run.kind}${t.last_run.ok === false ? ', falló' : ''})` : 'nunca'}</p>
              <p>Último éxito: {t.last_success_at ? fecha(t.last_success_at) : '—'}</p>
              <p>Pedidos revisados en Woo: {String(st.woo_seen ?? st.fetched ?? '—')} · faltantes detectados: {String(st.detected_missing ?? st.inserted ?? 0)} · recuperados: {String(st.recovered ?? st.inserted ?? 0)} · errores: {String(st.errors ?? 0)}</p>
              {Number(st.before_cutover_missing ?? 0) > 0 ? <p className="text-danger">Anteriores al corte sin importar: {String(st.before_cutover_missing)} (van en la importación histórica)</p> : null}
              {t.reasons.length ? <p className="mt-1 text-sm text-muted">{t.reasons.map(reason).join(' · ')}</p> : null}
            </div>
          );
        })}
      </div>

      <h2 className="font-display mt-10 text-3xl text-ink">Ventas pagadas que Fuxia 360 conoce</h2>
      <p className="mt-1 text-ink-2">{data.q1_paid_orders.total} ventas pagadas{data.from || data.to ? ` (${data.from ?? 'inicio'} → ${data.to ?? 'hoy'})` : ' (todo el historial capturado)'}.
        {Object.keys(data.q1_paid_orders.not_paid).length ? ` No cuentan: ${Object.entries(data.q1_paid_orders.not_paid).map(([k, v]) => `${v} ${k}`).join(', ')}.` : ''}</p>
      <div className="mt-3 overflow-x-auto rounded-2xl border border-line bg-surface">
        <table className="w-full min-w-[900px]">
          <thead><tr>
            <th className={th}>Canal</th><th className={th}>Cómo llegó</th><th className={th}>Moneda</th><th className={th}>Pagadas</th>
            <th className={th}>Bruto (GMV)</th><th className={th}>Descuentos</th><th className={th}>Envío cobrado</th><th className={th}>Reembolsos</th>
            <th className={th}>Venta neta de producto</th><th className={th}>Total cobrado</th>
          </tr></thead>
          <tbody>
            {data.q1_paid_orders.groups.map((g) => (
              <tr key={`${g.sales_channel}-${g.capture_source}-${g.currency}`} className="border-t border-line">
                <td className={td}>{CHANNEL[g.sales_channel] ?? g.sales_channel}</td><td className={td}>{CAPTURE[g.capture_source] ?? g.capture_source}</td>
                <td className={td}>{g.currency}</td><td className={td}>{g.paid_orders}</td>
                <td className={td}>{money(g.gross_merchandise_value, g.currency)}</td><td className={td}>{money(g.discounts, g.currency)}</td>
                <td className={td}>{money(g.shipping_charged, g.currency)}</td><td className={td}>{money(g.refunds, g.currency)}</td>
                <td className={td}>{money(g.net_product_revenue, g.currency)}</td><td className={td}>{money(g.total_collected, g.currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-muted">Venta neta de producto = líneas después de cupones, sin envío, menos reembolsos de producto (base de ROAS / MER). Total cobrado = lo que pagó la clienta menos reembolsos. El IVA no viene separado en Woo: no se calcula.</p>

      <div className="mt-6 grid gap-3 md:grid-cols-3">
        <div className="rounded-2xl border border-line bg-surface p-4 text-[15px] text-ink">
          <p className="text-sm text-muted">Tiempo real vs histórico</p>
          {Object.entries(data.q5_timing).map(([k, v]) => <p key={k}>{TIMING[k] ?? k}: {v.paid} pagadas</p>)}
        </div>
        <div className="rounded-2xl border border-line bg-surface p-4 text-[15px] text-ink">
          <p className="text-sm text-muted">En línea / tienda / legado</p>
          {Object.entries(data.q6_channels).map(([k, v]) => <p key={k}>{CHANNEL[k] ?? k}: {v.paid} pagadas{v.not_counted ? ` · ${v.not_counted} no cuentan` : ''}</p>)}
        </div>
        <div className="rounded-2xl border border-line bg-surface p-4 text-[15px] text-ink">
          <p className="text-sm text-muted">Venta neta de producto por moneda</p>
          {data.q8_net_product_revenue.by_currency.map((c) => <p key={c.currency}>{c.currency}: {money(c.net_product_revenue, c.currency)} ({c.paid_orders})</p>)}
          <p className="mt-2 text-sm">Consolidado MXN: {data.q8_net_product_revenue.consolidated_mxn.status === 'OK'
            ? money(data.q8_net_product_revenue.consolidated_mxn.value, 'MXN')
            : <span className="text-danger">DATA INCOMPLETE — falta tipo de cambio aprobado: {(data.q8_net_product_revenue.consolidated_mxn.fx_missing ?? []).map((f) => `${f.currency} ${f.month}`).join(', ')}</span>}</p>
        </div>
      </div>

      <h2 className="font-display mt-10 text-3xl text-ink">Gasto y eficiencia</h2>
      <p className="mt-1 text-ink-2">Gasto: {STATUS[data.q9_spend.status]?.label ?? data.q9_spend.status}.
        {data.q9_spend.by_currency.length ? ' ' + data.q9_spend.by_currency.map((s) => `${s.platform} ${money(s.spend, s.currency)} (${s.days} días)`).join(' · ') : ' No hay gasto cargado.'}</p>
      <div className="mt-3 grid gap-3 md:grid-cols-3">
        <KpiCard title="MER" k={data.q10_efficiency.mer} />
        <KpiCard title="ROAS" k={data.q10_efficiency.roas} />
        <KpiCard title="CAC" k={data.q10_efficiency.cac} money />
      </div>
      {canUpload ? <SpendUpload /> : null}
      <p className="mt-6 text-xs text-muted">Generado {fecha(data.generated_at)} · hora de Ciudad de México · fuente: Fuxia 360 (Commerce Facts, ventas de tienda, registro LEGACY_IMPORT, gasto importado).</p>
    </div>
  );
}
