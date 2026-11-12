import type { FlowStats } from '@/app/(app)/como-funciona/FlowMap';
import { liveToday, type LiveToday } from '@/lib/live-today';

// Mapa del negocio (was "Cómo funciona", renamed by Mario 2026-10-08). Same live numbers as Inicio (lib/live-today).
const n = (v: number) => v.toLocaleString('es-MX');
const mxn = (v: number) => `$${Math.round(v).toLocaleString('es-MX')}`;
const plural = (v: number, one: string, many: string) => `${n(v)} ${v === 1 ? one : many}`;
const join = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' · ') || null;

export function toFlowStats(t: LiveToday): FlowStats {
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


export async function flowStats(): Promise<FlowStats> {
  return toFlowStats(await liveToday());
}
