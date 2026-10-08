import type { CommerceSummary } from '@/lib/f360';
import { fecha } from '@/lib/format';

// G1 · Technical, read-only validation surface for Commerce Facts. Not the War Room: it only proves the facts are right.
// Every amount is in its ORIGINAL currency; rows are never added across currencies.
const ORIGIN: Record<string, string> = { storefront: 'Tienda en línea', manual_admin: 'Pedido manual', api_integration: 'Integración / API', physical_store: 'Tienda física', unknown: 'Desconocido' };
// Fuxia works with EXCHANGES (cambios), not refunds: refund states only appear if Woo technically sends one, as an exception.
const STATE: Record<string, string> = { never_paid: 'Nunca pagado', paid: 'Pagado', paid_cancelled: 'Pagado → cancelado (excepción, por revisar)',
  paid_refunded_partial: 'Pago anulado en Woo (excepción técnica)', paid_refunded_full: 'Pago anulado en Woo (excepción técnica)' };
const money = (n: number | null, currency: string) =>
  n === null ? '—' : new Intl.NumberFormat('es-MX', { style: 'currency', currency, maximumFractionDigits: currency === 'COP' ? 0 : 2 }).format(n);

export function CommerceFacts({ data }: { data: CommerceSummary }) {
  const th = 'px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted';
  const td = 'px-3 py-2 text-[15px] text-ink tabular-nums';
  return (
    <div className="mt-6" data-testid="commerce-facts">
      <p className="max-w-3xl text-ink-2">
        Hechos reales de venta (ACTUAL) por moneda original. Solo cuentan pedidos pagados; los no pagados o cancelados se listan aparte.
        La señal de compra de Meta no se usa: está en conflicto (DQ-01).
      </p>
      <div className="mt-4 flex flex-wrap gap-2">
        {data.sources.map((s) => (
          <span key={s.target} className={`rounded-full px-4 py-1.5 text-sm ${s.freshness === 'VERIFIED' ? 'bg-gold-soft text-ink' : 'bg-danger/10 text-danger'}`} data-testid="commerce-freshness">
            {s.target}: {s.freshness}{s.last_success_at ? ` · última sincronización ${fecha(s.last_success_at)}` : ''}{s.last_error ? ` · error: ${s.last_error}` : ''}
          </span>
        ))}
      </div>
      <div className="mt-5 overflow-x-auto rounded-2xl border border-line bg-surface">
        <table className="w-full min-w-[820px]">
          <thead><tr>
            <th className={th}>Moneda</th><th className={th}>Mercado</th><th className={th}>Origen</th><th className={th}>Pedidos</th><th className={th}>Pares</th>
            <th className={th}>Ventas de producto</th><th className={th}>Total de pedidos</th><th className={th}>AOV producto</th><th className={th}>Promedio por pedido</th>
            <th className={th}>Calidad</th>
          </tr></thead>
          <tbody>
            {data.groups.map((g) => (
              <tr key={`${g.currency}-${g.market}-${g.origin}-${g.channel}`} className="border-t border-line">
                <td className={td}>{g.currency}</td><td className={td}>{g.market}</td><td className={td}>{ORIGIN[g.origin] ?? g.origin}</td>
                <td className={td}>{g.orders}</td><td className={td}>{g.units}</td>
                <td className={td}>{money(g.product_sales, g.currency)}</td><td className={td}>{money(g.order_total, g.currency)}</td>
                <td className={td}>{money(g.aov_product, g.currency)}</td><td className={td}>{money(g.average_order_total, g.currency)}</td>
                <td className={td}>{g.quality.VERIFIED} ✓{g.quality.PARTIAL ? ` · ${g.quality.PARTIAL} parcial` : ''}{g.quality.UNVERIFIED ? ` · ${g.quality.UNVERIFIED} sin verificar` : ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-muted">Ventas de producto = líneas después de descuentos, sin envío ni impuestos. AOV producto = ventas de producto ÷ pedidos. Promedio por pedido = total cobrado ÷ pedidos.</p>

      <h2 className="font-display mt-8 text-2xl text-ink">No cuentan como venta</h2>
      <div className="mt-3 overflow-x-auto rounded-2xl border border-line bg-surface">
        <table className="w-full min-w-[600px]">
          <thead><tr><th className={th}>Moneda</th><th className={th}>Estado de pago</th><th className={th}>Pedidos</th><th className={th}>Total actual</th><th className={th}>Valor cuando se pagó</th></tr></thead>
          <tbody>
            {data.not_counted.map((x) => (
              <tr key={`${x.currency}-${x.payment_state}-${x.status_class}`} className="border-t border-line">
                <td className={td}>{x.currency}</td><td className={td}>{STATE[x.payment_state] ?? x.payment_state} <span className="text-xs text-muted">({x.status_class})</span></td>
                <td className={td}>{x.orders}</td><td className={td}>{money(x.order_total, x.currency)}</td><td className={td}>{money(x.paid_order_total, x.currency)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
