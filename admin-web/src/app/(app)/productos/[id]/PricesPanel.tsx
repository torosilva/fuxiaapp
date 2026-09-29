'use client';
import Link from 'next/link';
import { useState, useTransition } from 'react';
import type { CurrencyPrice } from '@/lib/f360';
import { setProductPriceAction } from '../../actions';

const fmt = (n: number | null, d: number) => (n == null ? '' : Number(n).toLocaleString('es-MX', { minimumFractionDigits: 0, maximumFractionDigits: d }));

// Price of this model in every currency. MXN (base) is edited in "Información del producto"; the others here.
// Each price goes to the store field the variation form already uses (COP → _price_cop, USD → _price_usd).
export function PricesPanel({ productId, prices, canEdit }: { productId: string; prices: CurrencyPrice[]; canEdit: boolean }) {
  const [draft, setDraft] = useState<Record<string, string>>(() => Object.fromEntries(prices.map((p) => [p.code, p.amount != null ? String(Number(p.amount)) : ''])));
  const [msg, setMsg] = useState<{ code: string; ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  const save = (p: CurrencyPrice, value: string) => start(async () => {
    const v = value.replace(/[^\d.]/g, '');
    const r = await setProductPriceAction(productId, p.code, v === '' ? null : Number(v));
    setMsg(r.ok ? { code: p.code, ok: true, text: 'Guardado' } : { code: p.code, ok: false, text: r.error });
  });

  return (
    <section className="mt-10 rounded-3xl border border-line bg-surface p-5 md:p-6" id="precios">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h2 className="font-display text-3xl text-ink">Precios por moneda</h2>
        <Link href="/monedas" className="text-sm text-gold-strong hover:underline">Monedas</Link>
      </div>
      <p className="mt-1 text-sm text-muted">Un precio por modelo, igual para todos los colores y tallas. Se publica en la tienda en línea de cada país.</p>
      <div className="mt-5 divide-y divide-line">
        {prices.map((p) => (
          <div key={p.code} className="flex flex-wrap items-center gap-3 py-3" data-testid={`price-${p.code}`}>
            <div className="w-40">
              <div className="font-medium text-ink">{p.code}</div>
              <div className="text-xs text-muted">{p.name}</div>
            </div>
            {p.is_base ? (
              <div className="flex-1 text-ink-2">
                <span className="tabular text-lg text-ink">{p.symbol}{fmt(p.amount, p.decimals) || '—'}</span>
                <span className="ml-2 text-sm text-muted">se cambia en la información del producto</span>
              </div>
            ) : (
              <div className="flex flex-1 flex-wrap items-center gap-2">
                <span className="text-muted">{p.symbol}</span>
                <input aria-label={`Precio en ${p.code}`} inputMode="decimal" disabled={!canEdit || pending} value={draft[p.code] ?? ''}
                  placeholder={p.suggested != null ? `Sugerido ${fmt(p.suggested, p.decimals)}` : 'Sin precio'}
                  onChange={(e) => setDraft({ ...draft, [p.code]: e.target.value.replace(/[^\d.]/g, '') })}
                  className="tabular w-40 rounded-xl border border-line bg-surface px-3 py-2.5 text-lg outline-none focus:border-gold disabled:bg-surface-2" />
                {canEdit && p.suggested != null && Number(draft[p.code] || 0) !== Number(p.suggested) && (
                  <button type="button" onClick={() => setDraft({ ...draft, [p.code]: String(Number(p.suggested)) })} className="rounded-xl border border-line px-3 py-2 text-sm text-ink-2 hover:border-gold/50">
                    Usar sugerido {fmt(p.suggested, p.decimals)}
                  </button>
                )}
                {canEdit && (
                  <button type="button" disabled={pending || (draft[p.code] ?? '') === (p.amount != null ? String(Number(p.amount)) : '')} onClick={() => save(p, draft[p.code] ?? '')}
                    className="rounded-xl bg-ink px-4 py-2 text-sm text-surface disabled:bg-surface-2 disabled:text-muted">Guardar</button>
                )}
                {msg?.code === p.code && <span className={`text-sm ${msg.ok ? 'text-success' : 'text-danger'}`}>{msg.text}</span>}
                {p.updated_by_name && <span className="w-full text-xs text-muted">Último cambio: {p.updated_by_name}</span>}
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
