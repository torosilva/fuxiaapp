'use client';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { addCustomerAction } from '../actions';

const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-[16px] outline-none focus:border-gold';
const EMPTY = { name: '', phone: '', country: 'MX', email: '', postalCode: '', birthday: '', shoeSize: '', street: '', neighborhood: '', city: '', state: '' };

// "Agregar clienta" (Mario 2026-10-08): only WhatsApp + name are required, like at the counter.
export function NewCustomer() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [f, setF] = useState(EMPTY);
  const [msg, setMsg] = useState<{ ok: boolean; text: string; ref?: string } | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof typeof EMPTY) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });

  const save = () => start(async () => {
    const r = await addCustomerAction(f);
    if (!r.ok) { setMsg({ ok: false, text: r.error }); return; }
    if (!r.data.ok) { setMsg({ ok: false, text: r.data.error }); return; }
    const name = f.name.trim();
    setMsg(r.data.created
      ? { ok: true, text: `${name} quedó registrada con su tarjeta Club Fuxia.`, ref: r.data.customer_ref }
      : r.data.role && r.data.role !== 'customer'
        ? { ok: false, text: 'Ese WhatsApp ya es de una cuenta del equipo (vendedora o admin).' }
        : { ok: true, text: 'Ese WhatsApp ya estaba registrado: no se cambió nada.', ref: r.data.customer_ref });
    setF(EMPTY);
    router.refresh();
  });

  if (!open) {
    return <button type="button" onClick={() => { setOpen(true); setMsg(null); }} className="rounded-full bg-ink px-5 py-3 text-surface" data-testid="add-customer">Agregar clienta</button>;
  }
  return (
    <section className="mt-6 w-full rounded-3xl border border-line bg-surface p-5" data-testid="new-customer">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-display text-3xl text-ink">Agregar clienta</h2>
        <button type="button" onClick={() => setOpen(false)} className="text-sm text-muted hover:text-ink">Cerrar</button>
      </div>
      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre de la clienta" value={f.name} onChange={set('name')} className={input} /></label>
        <div className="flex gap-2">
          <label className="w-24 text-sm text-ink-2">País
            <select aria-label="País del WhatsApp" value={f.country} onChange={set('country')} className={input}>
              <option value="MX">MX +52</option><option value="CO">CO +57</option><option value="US">US +1</option>
            </select></label>
          <label className="flex-1 text-sm text-ink-2">WhatsApp (10 dígitos)<input aria-label="WhatsApp de la clienta" inputMode="tel" value={f.phone} onChange={set('phone')} placeholder="81 1234 5678" className={input} /></label>
        </div>
        <label className="text-sm text-ink-2">Correo <span className="text-muted">(opcional)</span><input aria-label="Correo de la clienta" type="email" value={f.email} onChange={set('email')} className={input} /></label>
        <label className="text-sm text-ink-2">Código postal <span className="text-muted">(opcional)</span><input aria-label="Código postal" inputMode="numeric" value={f.postalCode} onChange={set('postalCode')} className={input} /></label>
        <label className="text-sm text-ink-2">Cumpleaños <span className="text-muted">(opcional)</span><input aria-label="Cumpleaños" type="date" value={f.birthday} onChange={set('birthday')} className={input} /></label>
        <label className="text-sm text-ink-2">Talla <span className="text-muted">(opcional)</span><input aria-label="Talla" inputMode="decimal" value={f.shoeSize} onChange={set('shoeSize')} placeholder="38" className={input} /></label>
      </div>
      <p className="kicker mt-5 text-muted">Dirección de envío <span className="normal-case tracking-normal">(opcional en tienda · siempre en ventas en línea)</span></p>
      <div className="mt-2 grid gap-3 sm:grid-cols-2">
        <label className="text-sm text-ink-2 sm:col-span-2">Calle y número<input aria-label="Calle y número" autoComplete="street-address" value={f.street} onChange={set('street')} className={input} /></label>
        <label className="text-sm text-ink-2">Colonia<input aria-label="Colonia" value={f.neighborhood} onChange={set('neighborhood')} className={input} /></label>
        <label className="text-sm text-ink-2">Ciudad o municipio<input aria-label="Ciudad o municipio" value={f.city} onChange={set('city')} className={input} /></label>
        <label className="text-sm text-ink-2">Estado<input aria-label="Estado" value={f.state} onChange={set('state')} className={input} /></label>
      </div>
      {msg && (
        <p className={`mt-3 rounded-xl px-4 py-3 text-sm ${msg.ok ? 'bg-success-soft text-success' : 'bg-danger-soft text-danger'}`}>
          {msg.text}{msg.ref && <> <Link href={`/clientes/${msg.ref}`} className="underline">Ver su ficha</Link></>}
        </p>
      )}
      <button type="button" disabled={pending || !f.name.trim() || !f.phone.trim()} onClick={save}
        className="mt-4 rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar clienta'}</button>
    </section>
  );
}
