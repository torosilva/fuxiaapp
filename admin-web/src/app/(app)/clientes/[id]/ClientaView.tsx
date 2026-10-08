import Link from 'next/link';
import type { AdminCustomerDetail } from '@/lib/f360';
import { EditContact } from './EditContact';

// Ficha de clienta · Atelier (2026-10-06). Presentation only: everything comes from f360_admin_customer (page.tsx enforces
// access); nothing here is inferred beyond counting her own purchases.
const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
const CONSENT: Record<string, string> = { none: 'sin respuesta', requested: 'pedido', granted: 'sí', denied: 'no', withdrawn: 'lo retiró' };
const PURPOSE: Record<string, string> = { privacy_notice: 'Aviso de privacidad', marketing_whatsapp: 'Novedades por WhatsApp', marketing_email: 'Novedades por correo' };
const STATUS_VERB: Record<string, string> = { granted: 'Aceptó', denied: 'No aceptó', withdrawn: 'Retiró', requested: 'Se le pidió', none: 'Sin respuesta a' };
const TIER_LABEL: Record<string, string> = { gold: 'Gold', silver: 'Silver', bronze: 'Bronze' };
const TZ = 'America/Mexico_City';

const day = (iso: string) => new Date(iso).toLocaleDateString('es-MX', { timeZone: TZ, day: 'numeric', month: 'short' });
const dayYear = (iso: string) => new Date(iso).toLocaleDateString('es-MX', { timeZone: TZ, day: 'numeric', month: 'short', year: 'numeric' });
const monthYear = (iso: string) => new Date(iso).toLocaleDateString('es-MX', { timeZone: TZ, month: 'long', year: 'numeric' });
const daysAgo = (iso: string) => Math.floor((Date.now() - new Date(iso).getTime()) / 86400000);
const ago = (n: number) => (n <= 0 ? 'Hoy' : n === 1 ? 'Ayer' : `Hace ${n} días`);
const lower = (t: string) => t.charAt(0).toLowerCase() + t.slice(1);
const initials = (name: string) => name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('') || '·';

function daysToBirthday(d: number, m: number) {
  const today = new Date(new Date().toLocaleDateString('en-CA', { timeZone: TZ }) + 'T12:00:00');
  let next = new Date(today.getFullYear(), m - 1, d, 12);
  if (next < today) next = new Date(today.getFullYear() + 1, m - 1, d, 12);
  return Math.round((next.getTime() - today.getTime()) / 86400000);
}

export function ClientaView({ c }: { c: AdminCustomerDetail }) {
  const purchases = c.purchases;
  const pairs = purchases.reduce((n, p) => n + p.quantity, 0);
  const inStore = purchases.filter((p) => p.channel === 'tienda').reduce((n, p) => n + p.quantity, 0);
  const online = pairs - inStore;
  const last = purchases[0];
  const size = c.shoe_size ?? c.sizes_bought[0] ?? null;
  const birthday = c.birthday_day && c.birthday_month ? { label: `${c.birthday_day} de ${MONTHS[c.birthday_month - 1]}`, inDays: daysToBirthday(c.birthday_day, c.birthday_month) } : null;
  const whatsappOk = c.consents?.marketing_whatsapp === 'granted';
  const prefers = purchases.length >= 2 ? (inStore > online ? 'Prefiere tienda' : online > inStore ? 'Prefiere en línea' : null) : null;
  const wa = c.phone ? `https://wa.me/${c.phone.replace(/\D/g, '')}?text=${encodeURIComponent(`¡Hola, ${c.first_name || c.name}! Soy de Fuxia Ballerinas.`)}` : null;

  // Her size per model, from what she actually bought.
  const fit = Object.values(purchases.reduce<Record<string, { model: string; sizes: Record<string, number>; pairs: number }>>((acc, p) => {
    if (!p.product) return acc;
    const a = (acc[p.product] ??= { model: p.product, sizes: {}, pairs: 0 });
    a.pairs += p.quantity;
    if (p.size) a.sizes[p.size] = (a.sizes[p.size] ?? 0) + p.quantity;
    return acc;
  }, {})).sort((a, b) => b.pairs - a.pairs).slice(0, 6);

  // One story: purchases, consents and her sign-up, newest first.
  const timeline = [
    ...purchases.map((p) => ({ at: p.at, dot: p.channel === 'tienda' ? 'var(--success)' : 'var(--online)',
      title: p.channel === 'tienda' ? 'Compró en tienda' : 'Compró en línea',
      detail: [p.product ?? 'Producto', p.color, p.size ? `talla ${p.size}` : null, p.quantity > 1 ? `${p.quantity} pares` : null].filter(Boolean).join(' · ') })),
    ...(c.consent_history ?? []).filter((h) => h.purpose !== 'privacy_notice' || h.status !== 'granted').map((h) => ({ at: h.at, dot: 'var(--muted)',
      title: `${STATUS_VERB[h.status] ?? h.status} ${lower(PURPOSE[h.purpose] ?? h.purpose)}`, detail: h.source ? `desde ${h.source}` : '' })),
    { at: c.created_at, dot: 'var(--gold)', title: `Se registró${c.registered_location ? ` en ${c.registered_location}` : ''}`,
      detail: c.privacy_consent === 'granted' ? 'Con su WhatsApp · aceptó el aviso de privacidad' : 'Con su WhatsApp' },
  ].sort((a, b) => b.at.localeCompare(a.at));

  const signals = [
    birthday && { kicker: 'Cumpleaños', tone: 'text-gold-strong', title: birthday.inDays === 0 ? '¡Es hoy!' : birthday.inDays <= 30 ? `En ${birthday.inDays} días` : birthday.label,
      detail: birthday.inDays <= 30 ? `${birthday.label} · buen momento para escribirle` : 'Fecha registrada' },
    last && { kicker: 'Última compra', tone: 'text-success', title: ago(daysAgo(last.at)), detail: [last.product, last.color, last.size].filter(Boolean).join(' · ') + ` · ${last.channel}` },
    c.points_pending > 0 && { kicker: 'Puntos por liberar', tone: 'text-danger', title: `${c.points_pending.toLocaleString('es-MX')} puntos`,
      detail: c.identity_verified ? 'Pendientes de acreditar' : 'Se liberan cuando confirme su WhatsApp' },
    { kicker: 'Su talla', tone: 'text-ink-2', title: size ? `Talla ${size}` : 'Sin talla registrada', detail: c.sizes_bought.length ? `Ha comprado ${c.sizes_bought.join(', ')}` : 'Aún sin compras con talla' },
  ].filter(Boolean) as { kicker: string; tone: string; title: string; detail: string }[];

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap justify-between gap-3 text-sm text-muted">
        <Link href="/clientes" className="hover:text-ink">← Clientas</Link>
        <span>Solo Carolina y Mario ven estos datos · cada consulta queda registrada</span>
      </div>

      {/* Identity + Club Fuxia card */}
      <section className="grid gap-5 lg:grid-cols-12">
        <div className="atelier-card flex flex-wrap items-center gap-6 p-7 lg:col-span-8">
          <div className="font-display flex size-24 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-ink to-ink-2 text-4xl text-champagne-light shadow-[0_0_0_6px_var(--gold-soft)]">{initials(c.name)}</div>
          <div className="flex min-w-[240px] flex-1 flex-col gap-2.5">
            <div className="flex flex-wrap items-center gap-3">
              <h1 className="font-display text-5xl leading-none text-ink">{c.name}</h1>
              <span className={`tier-${c.tier} rounded-full px-3 py-1 text-xs font-bold tracking-[0.14em]`}>{(TIER_LABEL[c.tier] ?? c.tier).toUpperCase()}</span>
            </div>
            <p className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-ink-2">
              <span>Clienta desde {monthYear(c.created_at)}{c.registered_location ? ` · ${c.registered_location}` : ''}</span>
              <span>{c.identity_verified ? 'WhatsApp verificado ✓' : 'WhatsApp sin verificar'}</span>
              {birthday && <span>Cumple: {birthday.label}</span>}
            </p>
            <p className="text-sm text-muted">{c.phone}{c.email ? ` · ${c.email}` : ''}{c.postal_code ? ` · CP ${c.postal_code}` : ''}</p>
            <div className="flex flex-wrap gap-2 text-xs">
              {size && <span className="rounded-full bg-surface-2 px-3 py-1.5 text-ink-2">Talla {size}</span>}
              {prefers && <span className="rounded-full bg-surface-2 px-3 py-1.5 text-ink-2">{prefers}</span>}
              {whatsappOk && <span className="rounded-full bg-success-soft px-3 py-1.5 text-success">Acepta novedades por WhatsApp</span>}
              {c.has_card && <span className="rounded-full bg-gold-soft px-3 py-1.5 text-gold-strong">Tarjeta Club Fuxia en su celular</span>}
            </div>
              {wa && (
            <a href={wa} target="_blank" rel="noopener noreferrer" className="mt-1 flex min-h-12 self-start items-center justify-center rounded-full bg-ink px-6 text-sm font-semibold text-champagne-light transition hover:bg-ink-2">
              Escribir por WhatsApp
            </a>
          )}
          </div>
        </div>

        <div className="flex flex-col gap-3.5 self-start rounded-[28px] p-7 text-champagne-light lg:col-span-4"
          style={{ background: 'radial-gradient(400px 220px at 90% 0%, rgba(232,201,138,.25), transparent 60%), var(--night-2)' }}>
          <div className="kicker flex justify-between text-[#A79F92]"><span>Club Fuxia</span><span className="text-champagne">{TIER_LABEL[c.tier] ?? c.tier}</span></div>
          <div className="flex items-baseline gap-2.5">
            <span className="font-display tabular text-6xl leading-none">{c.points.toLocaleString('es-MX')}</span>
            <span className="text-sm text-[#CFC6B8]">puntos</span>
          </div>
          <p className="text-[13px] text-[#CFC6B8]">{c.points_pending > 0 ? `${c.points_pending.toLocaleString('es-MX')} por liberar` : 'Todo acreditado'}</p>
          <div className="mt-1 grid grid-cols-3 gap-2.5 border-t border-white/10 pt-4">
            {[[pairs, pairs === 1 ? 'par' : 'pares'], [inStore, 'en tienda'], [online, 'en línea']].map(([n, l]) => (
              <div key={l as string} className="flex flex-col"><b className="tabular text-2xl">{n}</b><span className="text-[11px] text-[#A79F92]">{l}</span></div>
            ))}
          </div>
        </div>
      </section>

      <EditContact c={c} />

      {/* Signals */}
      <section className="grid gap-3.5 [grid-template-columns:repeat(auto-fit,minmax(210px,1fr))]">
        {signals.map((s) => (
          <div key={s.kicker} className="atelier-card flex flex-col gap-2 rounded-[20px] p-5">
            <span className={`kicker ${s.tone}`}>{s.kicker}</span>
            <span className="text-[15px] font-semibold text-ink">{s.title}</span>
            <span className="text-[13px] leading-snug text-muted">{s.detail}</span>
          </div>
        ))}
      </section>

      <section className="grid gap-5 lg:grid-cols-12">
        {/* Timeline */}
        <div className="atelier-card flex flex-col gap-4 p-7 lg:col-span-7">
          <h2 className="font-display text-3xl text-ink">Su historia con Fuxia</h2>
          <ol className="flex flex-col">
            {timeline.map((e, i) => (
              <li key={i} className="grid grid-cols-[84px_24px_1fr] gap-3">
                <span className="pt-1 text-right text-xs text-muted">{daysAgo(e.at) < 300 ? day(e.at) : dayYear(e.at)}</span>
                <span className="flex flex-col items-center">
                  <span className="mt-1.5 size-3.5 rounded-full shadow-[0_0_0_4px_var(--surface)]" style={{ background: e.dot }} />
                  {i < timeline.length - 1 && <span className="min-h-8 w-0.5 flex-1 bg-stitch" />}
                </span>
                <span className="flex flex-col gap-1 pb-5">
                  <span className="text-sm font-semibold text-ink">{e.title}</span>
                  {e.detail && <span className="text-[13px] text-muted">{e.detail}</span>}
                </span>
              </li>
            ))}
          </ol>
        </div>

        <div className="flex flex-col gap-5 lg:col-span-5">
          <div className="atelier-card flex flex-col gap-2 p-7">
            <h2 className="font-display text-[28px] text-ink">Su talla, por modelo</h2>
            {fit.length === 0 ? <p className="text-sm text-muted">Aparecerá con su primera compra.</p> : fit.map((f) => {
              const top = Object.entries(f.sizes).sort((a, b) => b[1] - a[1])[0];
              return (
                <div key={f.model} className="flex items-center justify-between gap-3 border-t border-surface-2 py-2.5 text-sm">
                  <span className="text-ink">{f.model}</span>
                  <span className="flex items-center gap-2">
                    {top && <b className="rounded-full bg-gold-soft px-2.5 py-1 text-gold-strong">{top[0]}</b>}
                    <span className="text-xs text-muted">{f.pairs} {f.pairs === 1 ? 'par' : 'pares'}</span>
                  </span>
                </div>
              );
            })}
          </div>
          <div className="flex flex-col gap-2 rounded-[22px] bg-surface-2 p-6 text-[13px] text-ink-2">
            <b className="kicker text-muted">Privacidad</b>
            {Object.entries(c.consents ?? {}).map(([k, v]) => <span key={k}>{PURPOSE[k] ?? k}: <b className="text-ink">{CONSENT[v] ?? v}</b></span>)}
            <span className="text-muted">Cada vez que alguien abre esta ficha queda registrado.</span>
          </div>
        </div>
      </section>
    </div>
  );
}
