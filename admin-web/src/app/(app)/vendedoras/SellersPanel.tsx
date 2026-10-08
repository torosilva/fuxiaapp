'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { Seller } from '../actions';
import { addSellerAction, deactivateSellerAction, resetSellerPinAction, setSellerStoreAction } from '../actions';

type Store = { id: string; name: string };
const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 outline-none focus:border-gold';
const ESTADO: Record<Seller['status'], { label: string; cls: string }> = {
  activa: { label: 'Activa', cls: 'bg-success-soft text-success' },
  pendiente: { label: 'Falta su primer ingreso', cls: 'bg-gold-soft text-ink' },
  inactiva: { label: 'Dada de baja', cls: 'bg-surface-2 text-muted' },
};

export function SellersPanel({ sellers, stores }: { sellers: Seller[]; stores: Store[] }) {
  const router = useRouter();
  const [f, setF] = useState({ name: '', phone: '', store: stores[0]?.id ?? '', pin: '' });
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  const add = () => start(async () => {
    const r = await addSellerAction({ name: f.name, phone: f.phone, locationId: f.store, pin: f.pin });
    if (!r.ok) { setMsg({ ok: false, text: r.error }); return; }
    setMsg({ ok: true, text: r.data.status === 'activa'
      ? `${r.data.name} ya puede vender en ${r.data.location.name}: Perfil → Modo Vendedora → su PIN.`
      : `${r.data.name} quedó dada de alta en ${r.data.location.name}. Pídele que abra la app Fuxia, toque "Ya tengo cuenta · Iniciar sesión" con su WhatsApp, y luego Perfil → Modo Vendedora → su PIN. Se activa sola en ese momento.` });
    setF({ name: '', phone: '', store: f.store, pin: '' });
    router.refresh();
  });

  return (
    <>
      <section className="mt-8 rounded-3xl border border-line bg-surface p-5" data-testid="new-seller">
        <h2 className="font-display text-3xl text-ink">Agregar vendedora</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">
          <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre de la vendedora" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} className={input} /></label>
          <label className="text-sm text-ink-2">WhatsApp (10 dígitos)<input aria-label="WhatsApp de la vendedora" inputMode="tel" value={f.phone} onChange={(e) => setF({ ...f, phone: e.target.value })} placeholder="55 1234 5678" className={input} /></label>
          <label className="text-sm text-ink-2">Tienda
            <select aria-label="Tienda" value={f.store} onChange={(e) => setF({ ...f, store: e.target.value })} className={input}>
              {stores.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
            </select></label>
          <label className="text-sm text-ink-2">PIN (4 dígitos)<input aria-label="PIN de la vendedora" inputMode="numeric" maxLength={4} value={f.pin} onChange={(e) => setF({ ...f, pin: e.target.value.replace(/\D/g, '') })} className={input} /></label>
        </div>
        {msg && <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>{msg.text}</p>}
        <button type="button" disabled={pending || !f.name.trim() || !f.phone.trim() || f.pin.length !== 4 || !f.store} onClick={add}
          className="mt-4 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Agregar vendedora'}</button>
      </section>

      <div className="mt-8 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface" data-testid="sellers">
        {sellers.length === 0 && <p className="px-5 py-6 text-ink-2">Todavía no hay vendedoras. Agrega la primera arriba.</p>}
        {sellers.map((s) => <SellerRow key={s.id} s={s} stores={stores} />)}
      </div>
    </>
  );
}

function SellerRow({ s, stores }: { s: Seller; stores: Store[] }) {
  const router = useRouter();
  const [mode, setMode] = useState<null | 'store' | 'pin' | 'off'>(null);
  const [store, setStore] = useState(s.location.id);
  const [pin, setPin] = useState('');
  const [err, setErr] = useState('');
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>) => start(async () => {
    const r = await fn();
    if (!r.ok) { setErr(r.error ?? 'No se pudo.'); return; }
    setErr(''); setMode(null); setPin(''); router.refresh();
  });
  const e = ESTADO[s.status];
  const btn = 'rounded-full border border-line px-4 py-2 text-sm text-ink-2 hover:text-ink';
  return (
    <div className="px-5 py-4">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <div className="min-w-0 flex-1">
          <div className="text-lg text-ink">{s.name}</div>
          <div className="text-sm text-muted">WhatsApp ···{s.phone_last4} · {s.location.name}{s.locked ? ' · PIN bloqueado' : ''}</div>
        </div>
        <span className={`rounded-full px-3 py-1 text-xs ${e.cls}`}>{e.label}</span>
        {s.status !== 'inactiva' && (
          <div className="flex flex-wrap gap-2">
            <button type="button" className={btn} onClick={() => setMode(mode === 'store' ? null : 'store')}>Cambiar tienda</button>
            <button type="button" className={btn} onClick={() => setMode(mode === 'pin' ? null : 'pin')}>{s.locked ? 'Desbloquear / nuevo PIN' : 'Nuevo PIN'}</button>
            <button type="button" className={btn} onClick={() => setMode(mode === 'off' ? null : 'off')}>Dar de baja</button>
          </div>
        )}
      </div>
      {s.status === 'pendiente' && <p className="mt-2 text-sm text-ink-2">Pídele que entre a la app Fuxia con este WhatsApp («Ya tengo cuenta · Iniciar sesión»). Se activa sola.</p>}
      {mode === 'store' && (
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-sm text-ink-2">Nueva tienda
            <select aria-label={`Nueva tienda de ${s.name}`} value={store} onChange={(ev) => setStore(ev.target.value)} className={input}>
              {stores.map((x) => <option key={x.id} value={x.id}>{x.name}</option>)}
            </select></label>
          <button type="button" disabled={pending || store === s.location.id} onClick={() => run(() => setSellerStoreAction(s.id, store))} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">Guardar</button>
        </div>
      )}
      {mode === 'pin' && (
        <div className="mt-3 flex flex-wrap items-end gap-3">
          <label className="text-sm text-ink-2">Nuevo PIN (4 dígitos)<input aria-label={`Nuevo PIN de ${s.name}`} inputMode="numeric" maxLength={4} value={pin} onChange={(ev) => setPin(ev.target.value.replace(/\D/g, ''))} className={input} /></label>
          <button type="button" disabled={pending || pin.length !== 4} onClick={() => run(() => resetSellerPinAction(s.id, pin))} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">Guardar PIN</button>
        </div>
      )}
      {mode === 'off' && (
        <div className="mt-3 flex flex-wrap items-center gap-3">
          <span className="text-sm text-ink-2">{s.name} ya no podrá vender en la app. Su historial de ventas se queda.</span>
          <button type="button" disabled={pending} onClick={() => run(() => deactivateSellerAction(s.id))} className="rounded-full bg-danger px-5 py-3 text-sm text-surface disabled:opacity-40">Sí, dar de baja</button>
        </div>
      )}
      {err && <p className="mt-2 rounded-xl bg-danger-soft px-4 py-2 text-sm text-danger">{err}</p>}
    </div>
  );
}
