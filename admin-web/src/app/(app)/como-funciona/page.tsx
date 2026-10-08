import { redirect } from 'next/navigation';
import { canWrite, getCrmAccess, getHome, getMe, getSyncBadge, listInbox, listMadeToOrder, listReservations, listSales, listStoreShipments } from '@/lib/f360';
import { FlowMap, type FlowStats } from './FlowMap';

// Live numbers come from the same light RPCs each module shows (Ventas "Hoy", Inicio, Bandeja, Sobre pedido, Apartados,
// Clientas, Avisos), so a number here always matches the screen it opens. Not f360_exec_dashboard: too heavy for a page that
// refreshes every minute. If one call fails, its node just shows no number; the map always renders.
const n = (v: number) => v.toLocaleString('es-MX');
const mxn = (v: number) => `$${Math.round(v).toLocaleString('es-MX')}`;
const plural = (v: number, one: string, many: string) => `${n(v)} ${v === 1 ? one : many}`;
const join = (...parts: (string | false | null | undefined)[]) => parts.filter(Boolean).join(' · ') || null;
const ok = <T,>(r: PromiseSettledResult<T>, name: string): T | null => {
  if (r.status === 'fulfilled') return r.value;
  console.error(`[como-funciona] ${name}: ${(r.reason as Error)?.message}`);
  return null;
};

async function liveStats(): Promise<FlowStats> {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
  const r = await Promise.allSettled([listSales({ from: today, to: today }), getHome(), listInbox(), getSyncBadge(), listMadeToOrder(),
    listReservations(), listStoreShipments(), getCrmAccess()]);
  const sales = ok(r[0], 'sales'), home = ok(r[1], 'home'), inbox = ok(r[2], 'inbox'), badge = ok(r[3], 'badge'), mto = ok(r[4], 'made_to_order'),
    resv = ok(r[5], 'reservations'), ship = ok(r[6], 'shipments'), crm = ok(r[7], 'crm');

  const byChannel = (c: 'store' | 'online') => (sales?.items ?? []).filter((s) => s.channel === c).reduce((t, s) => t + s.total, 0);
  const open = inbox?.filter((c) => c.status === 'nueva' || c.status === 'en_atencion').length ?? null;
  const toMake = mto?.filter((m) => m.status === 'pendiente' || m.status === 'en_proceso').reduce((t, m) => t + m.quantity, 0) ?? null;
  const toShip = ship?.filter((s) => s.status === 'por_enviar').length ?? 0;
  const active = resv?.filter((x) => x.status === 'activa') ?? null;
  const soon = active?.filter((x) => new Date(x.expires_at).getTime() - Date.now() < 48 * 3600_000).length ?? 0;

  return {
    at: new Date().toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Mexico_City' }),
    hub: sales ? `${mxn(sales.summary.revenue)} hoy` : null,
    avisos: badge,
    nodes: {
      online: sales ? join(`${mxn(byChannel('online'))} hoy`, toShip > 0 && `${n(toShip)} por enviar`) : null,
      tiendas: sales ? `${mxn(byChannel('store'))} hoy` : null,
      hilo: open === null ? null : open === 0 ? 'Todo atendido' : `${n(open)} por atender`,
      taller: toMake === null ? null : toMake > 0 ? `${plural(toMake, 'par', 'pares')} sobre pedido` : 'Nada sobre pedido',
      inventario: home ? join(plural(home.available_pairs, 'par', 'pares'), home.in_transit_pairs > 0 && `${n(home.in_transit_pairs)} en camino`) : null,
      clientas: crm ? plural(crm.customers, 'clienta', 'clientas') : null,
      apartados: active ? join(plural(active.length, 'apartado', 'apartados'), soon > 0 && `${n(soon)} vencen pronto`) : null,
      growth: sales ? `${plural(sales.summary.pairs, 'par vendido', 'pares vendidos')} hoy` : null,
    },
  };
}

export default async function ComoFunciona() {
  if (!canWrite((await getMe()).role)) redirect('/');
  const stats = await liveStats();
  return (
    <div>
      <p className="kicker text-gold-strong">Fuxia 360</p>
      <h1 className="font-display mt-1 text-5xl text-ink">Cómo funciona</h1>
      <p className="mt-2 max-w-2xl text-ink-2">Todo el negocio, conectado. Lo que entra por la izquierda llega a Fuxia 360, y Fuxia 360 mantiene al día lo de la derecha. Toca cualquier parte para abrirla.</p>
      <div className="mt-6"><FlowMap stats={stats} /></div>
    </div>
  );
}
