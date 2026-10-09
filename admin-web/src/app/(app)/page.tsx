import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { IconDown, IconMove, IconTruck } from '@/components/icons';
import { canRequestTransfer, canWrite, getHome } from '@/lib/f360';
import { pares } from '@/lib/format';

function saludo() {
  const h = Number(new Date().toLocaleString('en-US', { timeZone: 'America/Mexico_City', hour: 'numeric', hour12: false }));
  return h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
}

export default async function Inicio() {
  const home = await getHome();
  const write = canWrite(home.role);
  return (
    <div>
      <p className="text-sm text-muted">{new Date().toLocaleDateString('es-MX', { timeZone: 'America/Mexico_City', weekday: 'long', day: 'numeric', month: 'long' })}</p>
      <h1 className="font-display mt-1 text-5xl text-ink md:text-6xl">{saludo()}, {home.display_name}</h1>

      <div className="mt-8 grid gap-4 md:grid-cols-2">
        {write ? (
          <Link href="/recibir" className="group flex items-center gap-5 rounded-3xl bg-ink p-6 text-surface shadow-sm transition hover:bg-ink-2 md:p-8">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-gold text-surface"><IconDown className="size-7" /></span>
            <span>
              <span className="block text-2xl font-medium">Recibir mercancía</span>
              <span className="mt-1 block text-surface/70">Llegaron productos a una ubicación</span>
            </span>
          </Link>
        ) : null}
        {canRequestTransfer(home.role) ? (
          <Link href="/mover" className="group flex items-center gap-5 rounded-3xl border border-line bg-surface p-6 shadow-sm transition hover:border-gold/50 md:p-8">
            <span className="flex size-14 shrink-0 items-center justify-center rounded-2xl bg-gold-soft text-gold-strong"><IconMove className="size-7" /></span>
            <span>
              <span className="block text-2xl font-medium text-ink">Mover inventario</span>
              <span className="mt-1 block text-muted">{write ? 'Enviar pares de una ubicación a otra' : 'Pedir pares para tu tienda'}</span>
            </span>
          </Link>
        ) : null}
      </div>

      <section className="mt-12 grid gap-4 sm:grid-cols-2">
        <div className="rounded-3xl border border-line bg-surface p-6" data-testid="available-pairs">
          <div className="text-ink-2">Disponible en ubicaciones</div>
          <div className="tabular mt-2 text-5xl font-semibold tracking-tight text-ink">{home.available_pairs}</div>
          <div className="text-sm text-muted">{home.available_pairs === 1 ? 'par' : 'pares'} en tiendas y bodegas</div>
        </div>
        <Link href="/transferencias?vista=en-camino" className="rounded-3xl border border-line bg-surface p-6 transition hover:border-gold/40" data-testid="in-transit-pairs">
          <div className="flex items-center gap-2 text-ink-2"><IconTruck className="size-5 text-gold-strong" />En camino</div>
          <div className="tabular mt-2 text-5xl font-semibold tracking-tight text-ink">{home.in_transit_pairs}</div>
          <div className="text-sm text-muted">no disponibles hasta que se reciban{home.transfers.with_difference ? ` · ${home.transfers.with_difference} con diferencia` : ''}</div>
        </Link>
      </section>

      <section className="mt-12">
        <h2 className="font-display text-3xl text-ink">Pares por ubicación</h2>
        <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {home.locations.map((l) => (
            <Link key={l.id} href={`/inventario?ubicacion=${l.id}`} className="rounded-2xl border border-line bg-surface p-5 transition hover:border-gold/40">
              <div className="text-ink-2">{l.name}</div>
              <div className="tabular mt-2 text-4xl font-semibold tracking-tight text-ink">{l.pairs}</div>
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
