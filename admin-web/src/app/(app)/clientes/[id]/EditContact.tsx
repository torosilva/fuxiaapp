'use client';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { AdminCustomerDetail } from '@/lib/f360';
import { setCustomerContactAction } from '../../actions';

const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-[16px] outline-none focus:border-gold';

// Ficha: address + contact, editable by Carolina / Mario (Mario 2026-10-08). The WhatsApp is her identity: not editable here.
export function EditContact({ c }: { c: AdminCustomerDetail }) {
  const router = useRouter();
  const a = c.address;
  const start0 = { name: c.name, email: c.email ?? '', postalCode: c.postal_code ?? '', street: a?.street ?? '', neighborhood: a?.neighborhood ?? '', city: a?.city ?? '', state: a?.state ?? '' };
  const [open, setOpen] = useState(false);
  const [f, setF] = useState(start0);
  const [err, setErr] = useState('');
  const [pending, start] = useTransition();
  const set = (k: keyof typeof start0) => (e: { target: { value: string } }) => setF({ ...f, [k]: e.target.value });
  const line = [a?.street, a?.neighborhood, [a?.city, a?.state].filter(Boolean).join(', '), c.postal_code ? `CP ${c.postal_code}` : null].filter(Boolean).join(' · ');

  const save = () => start(async () => {
    const r = await setCustomerContactAction(c.customer_ref, f);
    if (!r.ok) { setErr(r.error); return; }
    if (!r.data.ok) { setErr(r.data.error); return; }
    setErr(''); setOpen(false); router.refresh();
  });

  return (
    <section className="atelier-card flex flex-col gap-3 p-7" data-testid="customer-address">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="font-display text-3xl text-ink">Dirección de envío</h2>
        {!open && <button type="button" onClick={() => { setF(start0); setOpen(true); }} className="rounded-full border border-line px-4 py-2 text-sm text-ink-2 hover:text-ink">Editar datos</button>}
      </div>
      {!open && <p className="text-ink-2">{line || <span className="text-muted">Sin dirección registrada.</span>}</p>}
      {open && (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <label className="text-sm text-ink-2">Nombre<input aria-label="Nombre" value={f.name} onChange={set('name')} className={input} /></label>
            <label className="text-sm text-ink-2">Correo <span className="text-muted">(opcional)</span><input aria-label="Correo" type="email" value={f.email} onChange={set('email')} className={input} /></label>
            <label className="text-sm text-ink-2 sm:col-span-2">Calle y número<input aria-label="Calle y número" value={f.street} onChange={set('street')} className={input} /></label>
            <label className="text-sm text-ink-2">Colonia<input aria-label="Colonia" value={f.neighborhood} onChange={set('neighborhood')} className={input} /></label>
            <label className="text-sm text-ink-2">Ciudad o municipio<input aria-label="Ciudad o municipio" value={f.city} onChange={set('city')} className={input} /></label>
            <label className="text-sm text-ink-2">Estado<input aria-label="Estado" value={f.state} onChange={set('state')} className={input} /></label>
            <label className="text-sm text-ink-2">Código postal<input aria-label="Código postal" inputMode="numeric" value={f.postalCode} onChange={set('postalCode')} className={input} /></label>
          </div>
          {err && <p className="rounded-xl bg-danger-soft px-4 py-2 text-sm text-danger">{err}</p>}
          <div className="flex gap-2">
            <button type="button" disabled={pending || !f.name.trim()} onClick={save} className="rounded-full bg-ink px-5 py-3 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar'}</button>
            <button type="button" onClick={() => setOpen(false)} className="rounded-full border border-line px-5 py-3 text-sm text-ink-2">Cancelar</button>
          </div>
        </>
      )}
    </section>
  );
}
