import { getMe, listCurrencies } from '@/lib/f360';
import { CurrencyForm } from './CurrencyForm';

// Currencies of the online store. A currency is stored and published by Fuxia 360 to its store field; the storefront
// shows it only once the site supports that field (COP and USD already do).
export default async function Monedas() {
  const [me, data] = await Promise.all([getMe(), listCurrencies()]);
  const owner = me.role === 'owner';
  const fmt = (n: number) => Number(n).toLocaleString('es-MX');
  return (
    <div className="mx-auto max-w-3xl">
      <h1 className="font-display text-5xl text-ink">Monedas</h1>
      <p className="mt-2 text-sm text-muted">Cada zapato tiene un precio en cada moneda activa. La moneda base (MXN) es el precio normal de la tienda.</p>
      <div className="mt-6 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
        {data.currencies.map((c) => (
          <div key={c.code} className="flex flex-wrap items-center gap-3 px-5 py-4" data-testid={`currency-${c.code}`}>
            <div className="w-16 font-semibold text-ink">{c.code}</div>
            <div className="flex-1">
              <div className="text-ink">{c.name} <span className="text-muted">{c.symbol}</span></div>
              <div className="text-xs text-muted">{c.is_base ? 'Moneda base · precio normal de WooCommerce' : `Campo en la tienda: ${c.woo_meta_key} · ${c.decimals} decimales`}</div>
            </div>
            <span className={`rounded-full px-3 py-1 text-xs ${c.active ? 'bg-success-soft text-success' : 'bg-surface-2 text-muted'}`}>{c.active ? 'Activa' : 'Inactiva'}</span>
          </div>
        ))}
      </div>

      <h2 className="font-display mt-10 text-3xl text-ink">Sugerencias</h2>
      <p className="mt-1 text-sm text-muted">Solo prellenan el precio de un zapato nuevo; siempre se puede ajustar.</p>
      <div className="mt-3 flex flex-wrap gap-2">
        {data.suggestions.map((s) => <span key={`${s.currency}-${s.base}`} className="tabular rounded-xl bg-surface-2 px-3 py-2 text-sm text-ink-2">${fmt(s.base)} MXN → {fmt(s.amount)} {s.currency}</span>)}
      </div>

      {owner ? <CurrencyForm /> : <p className="mt-10 text-sm text-muted">Solo una dueña puede agregar monedas.</p>}
    </div>
  );
}
