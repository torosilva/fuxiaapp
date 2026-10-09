import { redirect } from 'next/navigation';
import { canWrite, getMe } from '@/lib/f360';
import { liveToday } from '@/lib/live-today';
import { FlowMap, type FlowStats } from './FlowMap';

// Mapa del negocio (was "Cómo funciona", renamed by Mario 2026-10-08). Same live numbers as Inicio (lib/live-today).
const n = (v: number) => v.toLocaleString('es-MX');
const mxn = (v: number) => `$${Math.round(v).toLocaleString('es-MX')}`;
const plural = (v: number, one: string, many: string) => `${n(v)} ${v === 1 ? one : many}`;
const join = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' · ') || null;

async function liveStats(): Promise<FlowStats> {
  const t = await liveToday();
  const home = t.home;
  return {
    at: t.at,
    hub: t.revenue === null ? null : `${mxn(t.revenue)} hoy`,
    avisos: t.avisos,
    nodes: {
      online: t.online === null ? null : join(`${mxn(t.online)} hoy`, (t.toShip ?? 0) > 0 && `${n(t.toShip!)} por enviar`),
      tiendas: t.store === null ? null : `${mxn(t.store)} hoy`,
      hilo: t.openInbox === null ? null : t.openInbox === 0 ? 'Todo atendido' : `${n(t.openInbox)} por atender`,
      taller: t.toMake === null ? null : t.toMake > 0 ? `${plural(t.toMake, 'par', 'pares')} sobre pedido` : 'Nada sobre pedido',
      inventario: home ? join(plural(home.available_pairs, 'par', 'pares'), home.in_transit_pairs > 0 && `${n(home.in_transit_pairs)} en camino`) : null,
      clientas: t.customers === null ? null : plural(t.customers, 'clienta', 'clientas'),
      apartados: t.reservations === null ? null : join(plural(t.reservations, 'apartado', 'apartados'), (t.reservationsSoon ?? 0) > 0 && `${n(t.reservationsSoon!)} vencen pronto`),
      growth: t.pairs === null ? null : `${plural(t.pairs, 'par vendido', 'pares vendidos')} hoy`,
    },
  };
}

export default async function MapaDelNegocio() {
  if (!canWrite((await getMe()).role)) redirect('/');
  const stats = await liveStats();
  return (
    <div>
      <p className="kicker text-gold-strong">Fuxia 360</p>
      <h1 className="font-display mt-1 text-5xl text-ink">Mapa del negocio</h1>
      <p className="mt-2 max-w-2xl text-ink-2">Todo el negocio, conectado. Lo que entra por la izquierda llega a Fuxia 360, y Fuxia 360 mantiene al día lo de la derecha. Toca cualquier parte para abrirla.</p>
      <div className="mt-6"><FlowMap stats={stats} /></div>
    </div>
  );
}
