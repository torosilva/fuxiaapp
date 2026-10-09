import Link from 'next/link';
import { EventCard } from '@/components/EventCard';
import { canRequestTransfer, canWrite, getHome } from '@/lib/f360';
import { liveToday } from '@/lib/live-today';

// Inicio · minimal (Mario 2026-10-08: "ya se repite bastante… algo más minimalista"). One quiet line for today, only what needs
// attention, the two actions, the latest movements. The full picture lives in the Mapa del negocio and in Inventario.
function saludo() {
  const h = Number(new Date().toLocaleString('en-US', { timeZone: 'America/Mexico_City', hour: 'numeric', hour12: false }));
  return h < 12 ? 'Buenos días' : h < 19 ? 'Buenas tardes' : 'Buenas noches';
}
const n = (v: number) => v.toLocaleString('es-MX');
const mxn = (v: number | null) => (v === null ? '—' : `$${Math.round(v).toLocaleString('es-MX')}`);
const plural = (v: number, one: string, many: string) => `${n(v)} ${v === 1 ? one : many}`;

export default async function Inicio() {
  const home = await getHome();
  const write = canWrite(home.role);
  const t = write ? await liveToday() : null;
  const pending = t ? [
    (t.openInbox ?? 0) > 0 && { href: '/bandeja', text: `${plural(t.openInbox!, 'clienta', 'clientas')} por atender` },
    (t.toShip ?? 0) > 0 && { href: '/sobre-pedido', text: `${plural(t.toShip!, 'pedido', 'pedidos')} en línea por enviar` },
    (t.reservationsSoon ?? 0) > 0 && { href: '/apartados', text: `${plural(t.reservationsSoon!, 'apartado vence', 'apartados vencen')} en 48 h` },
    (t.toMake ?? 0) > 0 && { href: '/sobre-pedido', text: `${plural(t.toMake!, 'par', 'pares')} sobre pedido` },
    (t.avisos ?? 0) > 0 && { href: '/avisos', text: `${plural(t.avisos!, 'aviso', 'avisos')} por revisar` },
  ].filter(Boolean) as { href: string; text: string }[] : [];
  const btn = 'rounded-full px-5 py-2.5 text-sm transition';

  return (
    <div className="mx-auto max-w-3xl">
      <p className="kicker text-gold-strong">{new Date().toLocaleDateString('es-MX', { timeZone: 'America/Mexico_City', weekday: 'long', day: 'numeric', month: 'long' })}</p>
      <h1 className="font-display mt-1 text-5xl text-ink md:text-6xl">{saludo()}, {home.display_name}</h1>

      {t && (
        <p className="mt-5 text-lg text-ink-2">
          Hoy llevamos <b className="tabular font-semibold text-ink">{mxn(t.revenue)}</b>
          {t.pairs !== null && <> en {plural(t.pairs, 'par', 'pares')}</>}
          <span className="text-muted"> · tiendas {mxn(t.store)} · en línea {mxn(t.online)}</span>
          <Link href="/como-funciona" className="ml-2 whitespace-nowrap text-sm text-gold-strong hover:underline">Mapa del negocio →</Link>
        </p>
      )}

      <div className="mt-6 flex flex-wrap gap-2">
        {write && <Link href="/recibir" className={`${btn} bg-ink text-surface hover:bg-ink-2`}>Recibir mercancía</Link>}
        {canRequestTransfer(home.role) && <Link href="/mover" className={`${btn} border border-line bg-surface text-ink hover:border-gold/50`}>{write ? 'Mover inventario' : 'Pedir pares'}</Link>}
        <Link href="/inventario" className={`${btn} border border-line bg-surface text-ink-2 hover:border-gold/50`} data-testid="available-pairs">
          {plural(home.available_pairs, 'par disponible', 'pares disponibles')}
        </Link>
        <Link href="/transferencias?vista=en-camino" className={`${btn} border border-line bg-surface text-ink-2 hover:border-gold/50`} data-testid="in-transit-pairs">
          {n(home.in_transit_pairs)} en camino{home.transfers.with_difference ? ` · ${home.transfers.with_difference} con diferencia` : ''}
        </Link>
      </div>

      {t && (
        <section className="mt-12">
          <h2 className="kicker text-muted">Para atender</h2>
          {pending.length === 0 ? (
            <p className="mt-3 text-ink-2">Todo en orden.</p>
          ) : (
            <ul className="mt-3 divide-y divide-line border-y border-line">
              {pending.map((p) => (
                <li key={p.text}>
                  <Link href={p.href} className="flex items-center justify-between py-3.5 text-ink transition hover:text-gold-strong">
                    <span>{p.text}</span><span className="text-muted">→</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      <section className="mt-12">
        <div className="flex items-baseline justify-between">
          <h2 className="kicker text-muted">Últimos movimientos</h2>
          <Link href="/inventario?vista=historial" className="text-sm text-gold-strong hover:underline">Ver historial</Link>
        </div>
        <div className="mt-3 space-y-3">
          {home.recent.length === 0 ? (
            <p className="text-ink-2">Aún no hay movimientos. {write && <>Empieza <Link className="text-gold-strong underline" href="/recibir">recibiendo mercancía</Link>.</>}</p>
          ) : home.recent.slice(0, 5).map((e) => <EventCard key={e.id} e={e} />)}
        </div>
      </section>
    </div>
  );
}
