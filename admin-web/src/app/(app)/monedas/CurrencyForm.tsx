'use client';
import { useState, useTransition } from 'react';
import { saveCurrencyAction } from '../actions';

export function CurrencyForm() {
  const [f, setF] = useState({ code: '', name: '', symbol: '', decimals: 0, wooMetaKey: '', active: true });
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const input = 'mt-1 block w-full rounded-xl border border-line bg-surface px-3 py-2.5 outline-none focus:border-gold';
  const submit = () => start(async () => {
    const r = await saveCurrencyAction({ ...f, code: f.code.toUpperCase() });
    setMsg(r.ok ? { ok: true, text: `Moneda ${f.code.toUpperCase()} guardada.` } : { ok: false, text: r.error });
  });
  return (
    <section className="mt-10 rounded-3xl border border-line bg-surface p-5">
      <h2 className="font-display text-3xl text-ink">Agregar o editar moneda</h2>
      <p className="mt-1 text-sm text-muted">Fuxia 360 la guarda y la publica en el campo indicado. Para que se vea en la tienda, el sitio también debe tener ese campo.</p>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-sm text-ink-2">Código (3 letras)<input aria-label="Código" maxLength={3} value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} placeholder="EUR" className={input} /></label>
        <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="Euro" className={input} /></label>
        <label className="text-sm text-ink-2">Símbolo<input aria-label="Símbolo" value={f.symbol} onChange={(e) => setF({ ...f, symbol: e.target.value })} placeholder="€" className={input} /></label>
        <label className="text-sm text-ink-2">Decimales
          <select aria-label="Decimales" value={f.decimals} onChange={(e) => setF({ ...f, decimals: Number(e.target.value) })} className={input}><option value={0}>0</option><option value={2}>2</option></select></label>
        <label className="text-sm text-ink-2 sm:col-span-2">Campo en la tienda (WooCommerce)<input aria-label="Campo en la tienda" value={f.wooMetaKey} onChange={(e) => setF({ ...f, wooMetaKey: e.target.value.trim() })} placeholder="_price_eur" className={input} /></label>
        <label className="flex items-center gap-2 text-sm text-ink-2"><input type="checkbox" checked={f.active} onChange={(e) => setF({ ...f, active: e.target.checked })} />Activa</label>
      </div>
      {msg && <p className={`mt-3 rounded-xl px-4 py-3 ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
      <button type="button" disabled={pending} onClick={submit} className="mt-4 rounded-2xl bg-ink px-5 py-3 text-surface disabled:opacity-50">{pending ? 'Guardando…' : 'Guardar moneda'}</button>
    </section>
  );
}
