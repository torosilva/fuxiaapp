'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { saveHistSaleAction } from '../../actions';

type Store = { id: string; name: string; starts_on: string | null };
type Bazaar = { id: string; name: string; starts_on: string | null; ends_on: string | null };

// Last finished month as YYYY-MM (the current month can't be loaded: it is still being sold).
const lastMonth = () => {
  const d = new Date(new Date().toLocaleString('en-US', { timeZone: 'America/Mexico_City' }));
  d.setDate(1); d.setMonth(d.getMonth() - 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
};
const NEW_BAZAAR = '__nuevo__';

export function HistForm({ stores, bazaars }: { stores: Store[]; bazaars: Bazaar[] }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [kind, setKind] = useState<'store_month' | 'bazaar'>('store_month');
  const [storeId, setStoreId] = useState(stores[0]?.id ?? '');
  const [month, setMonth] = useState(lastMonth());
  const [bazaarId, setBazaarId] = useState(NEW_BAZAAR);
  const [bazaarName, setBazaarName] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [amount, setAmount] = useState('');
  const [pairs, setPairs] = useState('');
  const [estimated, setEstimated] = useState(true);
  const [notes, setNotes] = useState('');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  const input = 'mt-1 block w-full rounded-xl border border-line bg-surface px-3 py-3 text-[16px] text-ink outline-none focus:border-gold';
  const tab = (on: boolean) => `flex-1 rounded-full px-4 py-3 text-[15px] ${on ? 'bg-ink text-surface' : 'text-ink-2'}`;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    setMsg(null);
    const amt = Number(amount.replace(/[$,\s]/g, ''));
    const prs = Number(pairs);
    start(async () => {
      const r = await saveHistSaleAction({
        kind,
        locationId: kind === 'store_month' ? storeId : bazaarId === NEW_BAZAAR ? null : bazaarId,
        bazaarName: kind === 'bazaar' && bazaarId === NEW_BAZAAR ? bazaarName : null,
        start: kind === 'store_month' ? `${month}-01` : from,
        end: kind === 'store_month' ? null : to || from,
        amount: amt, pairs: Number.isFinite(prs) ? prs : -1, pairsEstimated: estimated, notes,
      });
      if (r.ok) {
        setMsg({ ok: true, text: 'Guardado.' });
        setAmount(''); setPairs(''); setNotes(''); setBazaarName(''); setFrom(''); setTo('');
        router.refresh();
      } else setMsg({ ok: false, text: r.error });
    });
  };

  return (
    <form onSubmit={submit} className="flex flex-col gap-4 rounded-3xl border border-line bg-surface p-5">
      <div className="flex rounded-full bg-surface-2 p-1" role="tablist" aria-label="Qué vas a cargar">
        <button type="button" role="tab" aria-selected={kind === 'store_month'} className={tab(kind === 'store_month')} onClick={() => setKind('store_month')}>Tienda · un mes</button>
        <button type="button" role="tab" aria-selected={kind === 'bazaar'} className={tab(kind === 'bazaar')} onClick={() => setKind('bazaar')}>Bazar</button>
      </div>

      {kind === 'store_month' ? (
        <>
          <label className="text-sm text-muted">Tienda
            <select className={input} value={storeId} onChange={(e) => setStoreId(e.target.value)} required>
              {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select>
          </label>
          <label className="text-sm text-muted">Mes
            <input type="month" className={input} value={month} max={lastMonth()} min="2025-01" onChange={(e) => setMonth(e.target.value)} required />
          </label>
        </>
      ) : (
        <>
          <label className="text-sm text-muted">Bazar
            <select className={input} value={bazaarId} onChange={(e) => setBazaarId(e.target.value)}>
              <option value={NEW_BAZAAR}>Otro bazar (escribir nombre)</option>
              {bazaars.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}
            </select>
          </label>
          {bazaarId === NEW_BAZAAR && (
            <label className="text-sm text-muted">Nombre del bazar
              <input className={input} value={bazaarName} onChange={(e) => setBazaarName(e.target.value)} placeholder="Ej. Bazar Las Lomas" required maxLength={80} />
            </label>
          )}
          <div className="grid grid-cols-2 gap-3">
            <label className="text-sm text-muted">Del<input type="date" className={input} value={from} min="2025-01-01" onChange={(e) => setFrom(e.target.value)} required /></label>
            <label className="text-sm text-muted">Al<input type="date" className={input} value={to} min={from || '2025-01-01'} onChange={(e) => setTo(e.target.value)} /></label>
          </div>
        </>
      )}

      <div className="grid grid-cols-2 gap-3">
        <label className="text-sm text-muted">Vendido (pesos)
          <input inputMode="decimal" className={`${input} tabular`} value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="120,000" required />
        </label>
        <label className="text-sm text-muted">Pares
          <input inputMode="numeric" className={`${input} tabular`} value={pairs} onChange={(e) => setPairs(e.target.value.replace(/\D/g, ''))} placeholder="48" required />
        </label>
      </div>
      <label className="flex items-center gap-3 text-[15px] text-ink-2">
        <input type="checkbox" className="h-5 w-5 accent-[var(--color-gold-strong)]" checked={estimated} onChange={(e) => setEstimated(e.target.checked)} />
        Los pares son aproximados
      </label>
      <label className="text-sm text-muted">Nota (opcional)
        <input className={input} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="Ej. abrió el 6 de septiembre" maxLength={500} />
      </label>

      {msg && <p role="status" className={`rounded-xl px-4 py-3 text-[15px] ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
      <button type="submit" disabled={pending} className="rounded-full bg-ink px-5 py-3.5 text-[16px] text-surface disabled:opacity-50">
        {pending ? 'Guardando…' : 'Guardar'}
      </button>
    </form>
  );
}
