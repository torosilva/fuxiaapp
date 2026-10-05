import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { canWrite, getAdminCustomer, getCrmAccess, getMe } from '@/lib/f360';
import { fecha } from '@/lib/format';

// Ficha completa de clienta (CRM C4). Only customer_pii_viewers; the database refuses others and logs the view.
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const CONSENT: Record<string, string> = { none: 'Sin respuesta', requested: 'Pedido', granted: 'Aceptó', denied: 'No aceptó', withdrawn: 'Retiró' };
const PURPOSE: Record<string, string> = { privacy_notice: 'Uso de datos', marketing_whatsapp: 'Novedades por WhatsApp', marketing_email: 'Novedades por correo' };

export default async function Clienta({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!canWrite((await getMe()).role)) redirect('/');
  if (!(await getCrmAccess()).pii_viewer) redirect('/clientes');
  const r = await getAdminCustomer(id);
  if (!r.ok || !r.customer) notFound();
  const c = r.customer;
  const box = 'rounded-3xl border border-line bg-surface p-5';
  return (
    <div>
      <Link href="/clientes" className="text-sm text-muted">← Clientas</Link>
      <div className="mt-2 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-display text-5xl text-ink">{c.name}</h1>
          <p className="mt-1 text-ink-2">{c.phone}{c.email ? ` · ${c.email}` : ''}{c.postal_code ? ` · CP ${c.postal_code}` : ''}</p>
          <p className="text-sm text-muted">Alta: {fecha(c.created_at)}{c.registered_location ? ` en ${c.registered_location}` : ''} · {c.identity_verified ? 'WhatsApp verificado' : 'WhatsApp sin verificar'}</p>
        </div>
        <div className="rounded-3xl bg-ink px-6 py-4 text-center text-surface">
          <p className="text-xs uppercase tracking-[0.2em] text-surface/70">Talla</p>
          <p className="font-display text-5xl">{c.shoe_size ?? c.sizes_bought[0] ?? '—'}</p>
          {c.sizes_bought.length > 0 && <p className="text-xs text-surface/70">compra {c.sizes_bought.join(', ')}</p>}
        </div>
      </div>

      <div className="mt-6 grid gap-4 md:grid-cols-3">
        <div className={box}><p className="text-sm text-muted">Nivel</p><p className="font-display text-3xl capitalize text-ink">{c.tier}</p>
          <p className="tabular text-ink-2">{c.points.toLocaleString('es-MX')} pts{c.points_pending > 0 ? ` · ${c.points_pending} por liberar` : ''}</p></div>
        <div className={box}><p className="text-sm text-muted">Cumpleaños</p>
          <p className="font-display text-3xl text-ink">{c.birthday_day && c.birthday_month ? `${c.birthday_day} de ${MONTHS[c.birthday_month - 1]}` : '—'}</p></div>
        <div className={box}><p className="text-sm text-muted">Permisos</p>
          <ul className="mt-1 space-y-0.5 text-sm text-ink-2">{Object.entries(c.consents ?? {}).map(([k, v]) => <li key={k}>{PURPOSE[k] ?? k}: <b className="text-ink">{CONSENT[v] ?? v}</b></li>)}</ul></div>
      </div>

      <section className={`${box} mt-6`}>
        <h2 className="font-display text-3xl text-ink">Compras</h2>
        {c.purchases.length === 0 ? <p className="mt-2 text-muted">Sin compras registradas todavía.</p> : (
          <ul className="mt-3 divide-y divide-line">
            {c.purchases.map((p, i) => (
              <li key={i} className="flex flex-wrap justify-between gap-2 py-3 text-ink-2">
                <span className="text-ink">{p.product ?? 'Producto'}{p.color ? ` · ${p.color}` : ''}{p.size ? ` · talla ${p.size}` : ''}{p.quantity > 1 ? ` · ${p.quantity} pares` : ''}</span>
                <span className="text-sm">{p.channel} · {fecha(p.at)}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
