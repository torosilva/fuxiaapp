import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { IconBell, IconClock, IconDown, IconMove, IconScissors, IconTruck, IconUsers } from '@/components/icons';
import { canRequestTransfer, canWrite, getHome } from '@/lib/f360';
import { pares } from '@/lib/format';
import { liveToday, type LiveToday } from '@/lib/live-today';

// Inicio · Atelier (Mario 2026-10-08: "puede quedar mucho mejor, así como Cómo funciona"). Owners/operators get "Hoy en Fuxia"
// (same live numbers as the Mapa del negocio, lib/live-today) on the night/champagne brand card; everyone keeps actions,
// pares por ubicación and últimos movimientos.
function saludo() {
  const h = Number(new Date().toLocaleString('en-US', { timeZone: 'America/Mexico_City', hour: 'numeric', hour12: false }));
  return h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
}
const n = (v: number) => v.toLocaleString('es-MX');
const mxn = (v: number | null) => (v === null ? '—' : `$${Math.round(v).toLocaleString('es-MX')}`);

function HoyEnFuxia({ t }: { t: LiveToday }) {
  const stats: [string, string][] = [
    ['Tiendas', mxn(t.store)],
    ['En línea', mxn(t.online)],
    ['Pares vendidos', t.pairs === null ? '—' : n(t.pairs)],
  ];
  return (
    <section className="relative overflow-hidden rounded-[28px] p-7 text-champagne-light md:p-9"
      style={{ background: 'radial-gradient(520px 260px at 92% 0%, rgba(232,201,138,.26), transparent 60%), var(--night-2)' }}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="kicker text-champagne">Hoy en Fuxia</span>
        <span className="flex items-center gap-2 text-xs text-[#A79F92]">
          <span className="relative flex size-2"><span className="absolute inline-flex size-full animate-ping rounded-full bg-champagne opacity-60 motion-reduce:hidden" /><span className="relative inline-flex size-2 rounded-full bg-champagne" /></span>
          En vivo · {t.at}
        </span>
      </div>
      <div className="mt-5 flex flex-wrap items-end justify-between gap-6">
        <div>
          <div className="font-display tabular text-6xl leading-none md:text-7xl">{mxn(t.revenue)}</div>
          <div className="mt-2 text-sm text-[#CFC6B8]">vendidos hoy, tiendas y en línea</div>
        </div>
        <Link href="/como-funciona" className="rounded-full border border-champagne/40 px-5 py-2.5 text-sm text-champagne transition hover:bg-champagne/10">Ver el mapa del negocio →</Link>
      </div>
      <div className="mt-7 grid grid-cols-3 gap-3 border-t border-white/10 pt-5">
        {stats.map(([label, value]) => (
          <div key={label} className="flex flex-col">
            <b className="tabular text-2xl md:text-3xl">{value}</b>
            <span className="text-[11px] uppercase tracking-[0.14em] text-[#A79F92]">{label}</span>
          </div>
        ))}
      </div>
    </section>
  );
}

function Senales({ t }: { t: LiveToday }) {
  const items = [
    { href: '/bandeja', icon: IconUsers, kicker: 'Clientas por atender', value: t.openInbox, detail: t.openInbox === 0 ? 'Todo atendido' : 'en la bandeja de Hilo' },
    { href: '/apartados', icon: IconClock, kicker: 'Apartados Gold', value: t.reservations, detail: (t.reservationsSoon ?? 0) > 0 ? `${n(t.reservationsSoon!)} vencen en 48 h` : 'activos' },
    { href: '/sobre-pedido', icon: IconScissors, kicker: 'Sobre pedido', value: t.toMake, detail: 'pares por hacer' },
    { href: '/avisos', icon: IconBell, kicker: 'Avisos', value: t.avisos, detail: t.avisos === 0 ? 'Sin pendientes' : 'por revisar' },
  ];
  return (
    <section className="mt-5 grid gap-3.5 [grid-template-columns:repeat(auto-fit,minmax(200px,1fr))]">
      {items.map(({ href, icon: Icon, kicker, value, detail }) => (
        <Link key={href} href={href} className="atelier-card flex flex-col gap-2 rounded-[20px] p-5 transition hover:border-gold/50">
          <span className="flex items-center gap-2 text-gold-strong"><Icon className="size-4" /><span className="kicker">{kicker}</span></span>
          <span className="tabular text-3xl font-semibold text-ink">{value === null ? '—' : n(value)}</span>
          <span className="text-[13px] text-muted">{detail}</span>
        </Link>
      ))}
    </section>
  );
}

export default async function Inicio() {
  const home = await getHome();
  const write = canWrite(home.role);
  const t = write ? await liveToday() : null;
  return (
    <div>
      <p className="kicker text-gold-strong">{new Date().toLocaleDateString('es-MX', { timeZone: 'America/Mexico_City', weekday: 'long', day: 'numeric', month: 'long' })}</p>
      <h1 className="font-display mt-1 text-5xl text-ink md:text-6xl">{saludo()}, {home.display_name}</h1>

      {t && <div className="mt-8"><HoyEnFuxia t={t} /><Senales t={t} /></div>}

      <div className="mt-8 grid gap-4 md:grid-cols-2">
        {write ? (
          <Link href="/recibir" className="group flex items-center gap-5 rounded-3xl bg-ink p-6 text-surface shadow-sm transition hover:bg-ink-2 md:p-7">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-gold text-surface"><IconDown className="size-7" /></span>
            <span>
              <span className="block text-2xl font-medium">Recibir mercancía</span>
              <span className="mt-1 block text-surface/70">Llegaron productos a una ubicación</span>
            </span>
          </Link>
        ) : null}
        {canRequestTransfer(home.role) ? (
          <Link href="/mover" className="group flex items-center gap-5 rounded-3xl border border-line bg-surface p-6 shadow-sm transition hover:border-gold/50 md:p-7">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-gold-soft text-gold-strong"><IconMove className="size-7" /></span>
            <span>
              <span className="block text-2xl font-medium text-ink">Mover inventario</span>
              <span className="mt-1 block text-muted">{write ? 'Enviar pares de una ubicación a otra' : 'Pedir pares para tu tienda'}</span>
            </span>
          </Link>
        ) : null}
      </div>

      <section className="mt-12">
        <div className="flex flex-wrap items-baseline justify-between gap-3">
          <h2 className="font-display text-3xl text-ink">Inventario por ubicación</h2>
          <span className="text-sm text-muted">
            <b className="tabular text-ink">{n(home.available_pairs)}</b> {home.available_pairs === 1 ? 'par disponible' : 'pares disponibles'}
            {' · '}<Link href="/transferencias?vista=en-camino" className="text-gold-strong hover:underline" data-testid="in-transit-pairs"><IconTruck className="mr-1 inline size-4" />{n(home.in_transit_pairs)} en camino</Link>
            {home.transfers.with_difference ? ` · ${home.transfers.with_difference} con diferencia` : ''}
          </span>
        </div>
        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3" data-testid="available-pairs">
          {home.locations.map((l) => (
            <Link key={l.id} href={`/inventario?ubicacion=${l.id}`} className="atelier-card rounded-[20px] p-5 transition hover:border-gold/40">
              <div className="kicker text-ink-2">{l.name}</div>
              <div className="tabular mt-2 text-4xl font-semibold tracking-tight text-ink">{n(l.pairs)}</div>
              <div className="text-sm text-muted">{l.pairs === 1 ? 'par' : 'pares'}</div>
              {(l.incoming ?? 0) > 0 && <div className="mt-2 text-sm text-gold-strong">+{l.incoming} en camino hacia aquí</div>}
              {l.sales_sync_pending && <div className="mt-3 rounded-lg bg-gold-soft px-2.5 py-1.5 text-xs text-ink-2">Ventas de tienda aún no descontadas</div>}
            </Link>
          ))}
        </div>
      </section>

      <section className="mt-12">
        <div className="flex items-baseline justify-between">
          <h2 className="font-display text-3xl text-ink">Últimos movimientos</h2>
          <Link href="/inventario?vista=historial" className="text-sm text-gold-strong hover:underline">Ver historial</Link>
        </div>
        <div className="mt-4 space-y-3">
          {home.recent.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-line bg-surface p-8 text-center text-ink-2">
              Aún no hay movimientos. {write && <>Empieza <Link className="text-gold-strong underline" href="/recibir">recibiendo mercancía</Link>.</>}
            </div>
          ) : home.recent.map((e) => <EventCard key={e.id} e={e} />)}
        </div>
      </section>
      <p className="mt-10 text-xs text-muted">{home.product_count} {home.product_count === 1 ? 'producto' : 'productos'} · {pares(home.available_pairs)} disponibles · {pares(home.in_transit_pairs)} en camino</p>
    </div>
  );
}
