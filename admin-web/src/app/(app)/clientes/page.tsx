import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getCrmAccess, getMe, listAdminCustomers } from '@/lib/f360';

// Clientas (CRM C4 · Mario 2026-10-05). Full personal data only for customer_pii_viewers (Carolina, Mario), enforced by the
// database (f360_admin_customers refuses everyone else and logs every access). Others see counts only. No export button.
const MONTHS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const TIER: Record<string, string> = { gold: 'tier-gold', silver: 'tier-silver', bronze: 'tier-bronze' };
const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('') || '·';
const SOURCE: Record<string, string> = { app: 'App', store: 'Tienda', import: 'Carga', woo: 'En línea', admin: 'Admin' };

export default async function Clientes({ searchParams }: { searchParams: Promise<{ q?: string; cumple?: string }> }) {
  if (!canWrite((await getMe()).role)) redirect('/');
  const sp = await searchParams;
  const access = await getCrmAccess();
  if (!access.pii_viewer) {
    return (
      <div className="mx-auto max-w-3xl">
        <h1 className="font-display text-5xl text-ink">Clientas</h1>
        <p className="mt-6 rounded-3xl border border-line bg-surface p-6 text-ink-2">
          Hay <b className="tabular text-ink">{access.customers.toLocaleString('es-MX')}</b> clientas registradas. Sus datos personales solo los ven Carolina y Mario.
        </p>
      </div>
    );
  }
  const all = await listAdminCustomers(sp.q);
  const month = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City', month: 'numeric' });
  const rows = sp.cumple ? all.filter((c) => String(c.birthday_month) === month) : all;
  const pill = (on: boolean) => `rounded-full px-4 py-2 text-sm ${on ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-3">
        <h1 className="font-display text-5xl text-ink">Clientas</h1>
        <span className="text-sm text-muted">{access.customers.toLocaleString('es-MX')} registradas · solo Carolina y Mario ven estos datos · cada consulta queda registrada</span>
      </div>
      <form action="/clientes" className="mt-6 flex flex-wrap gap-2">
        <label className="min-w-64 flex-1"><span className="sr-only">Buscar</span>
          <input name="q" defaultValue={sp.q ?? ''} placeholder="Buscar por nombre, correo, WhatsApp o últimos 4 dígitos"
            className="w-full rounded-2xl border border-line bg-surface px-4 py-3 text-[16px] outline-none focus:border-gold" /></label>
        <button className="rounded-full bg-ink px-5 py-3 text-surface">Buscar</button>
      </form>
      <div className="mt-3 flex flex-wrap gap-2">
        <Link href="/clientes" className={pill(!sp.cumple)}>Todas</Link>
        <Link href="/clientes?cumple=1" className={pill(!!sp.cumple)}>Cumpleaños de este mes</Link>
      </div>

      {rows.length === 0 ? (
        <p className="mt-8 rounded-2xl border border-dashed border-line p-8 text-center text-muted">
          {sp.q || sp.cumple ? 'No hay clientas con ese filtro.' : 'Todavía no hay clientas en este ambiente. Las clientas reales llegarán con el pase a producción (opción B).'}
        </p>
      ) : (
        <ul className="atelier-card mt-6 divide-y divide-line overflow-hidden">
          {rows.map((c) => (
            <li key={c.customer_ref}>
              <Link href={`/clientes/${c.customer_ref}`} className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-4 transition hover:bg-surface-2">
                <span className="font-display flex size-11 shrink-0 items-center justify-center rounded-full bg-night-2 text-lg text-champagne-light">{initials(c.name)}</span>
                <div className="min-w-0 flex-1">
                  <p className="font-medium text-ink">{c.name}</p>
                  <p className="text-sm text-muted">{c.phone}{c.email ? ` · ${c.email}` : ''}</p>
                </div>
                <span className="text-sm text-ink-2">{c.shoe_size ? `Talla ${c.shoe_size}` : c.sizes_bought.length ? `Compra ${c.sizes_bought.join(', ')}` : 'Talla —'}</span>
                {c.birthday_day && c.birthday_month && <span className="tabular text-sm text-ink-2">Cumple {c.birthday_day} {MONTHS[c.birthday_month - 1]}</span>}
                <span className="rounded-full bg-surface-2 px-2.5 py-1 text-xs text-ink-2">{SOURCE[c.source] ?? c.source}</span>
                <span className={`rounded-full px-2.5 py-1 text-xs font-semibold capitalize ${TIER[c.tier] ?? ''}`}>{c.tier} · {c.points.toLocaleString('es-MX')} pts</span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
