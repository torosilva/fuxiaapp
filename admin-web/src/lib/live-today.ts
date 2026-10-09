import { getCrmAccess, getHome, getSyncBadge, listInbox, listMadeToOrder, listReservations, listSales, listStoreShipments } from '@/lib/f360';

// "Hoy en Fuxia" — shared by Inicio and the Mapa del negocio. Live numbers come from the same light RPCs each module shows
// (Ventas "Hoy", Inicio, Bandeja, Sobre pedido, Apartados, Clientas, Avisos), so a number always matches the screen it opens.
// Not f360_exec_dashboard: too heavy for pages that refresh every minute. A failed call gives null (the screen shows "—").
const ok = <T,>(r: PromiseSettledResult<T>, name: string): T | null => {
  if (r.status === 'fulfilled') return r.value;
  console.error(`[live-today] ${name}: ${(r.reason as Error)?.message}`);
  return null;
};

export type LiveToday = {
  at: string;
  revenue: number | null; pairs: number | null; store: number | null; online: number | null;
  openInbox: number | null; toMake: number | null; toShip: number | null;
  reservations: number | null; reservationsSoon: number | null;
  avisos: number | null; customers: number | null;
  home: Awaited<ReturnType<typeof getHome>> | null;
};

export async function liveToday(): Promise<LiveToday> {
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
  const r = await Promise.allSettled([listSales({ from: today, to: today }), getHome(), listInbox(), getSyncBadge(), listMadeToOrder(),
    listReservations(), listStoreShipments(), getCrmAccess()]);
  const sales = ok(r[0], 'sales'), home = ok(r[1], 'home'), inbox = ok(r[2], 'inbox'), badge = ok(r[3], 'badge'), mto = ok(r[4], 'made_to_order'),
    resv = ok(r[5], 'reservations'), ship = ok(r[6], 'shipments'), crm = ok(r[7], 'crm');
  const byChannel = (c: 'store' | 'online') => (sales?.items ?? []).filter((s) => s.channel === c).reduce((t, s) => t + s.total, 0);
  const active = resv?.filter((x) => x.status === 'activa') ?? null;
  return {
    at: new Date().toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Mexico_City' }),
    revenue: sales ? sales.summary.revenue : null,
    pairs: sales ? sales.summary.pairs : null,
    store: sales ? byChannel('store') : null,
    online: sales ? byChannel('online') : null,
    openInbox: inbox ? inbox.filter((c) => c.status === 'nueva' || c.status === 'en_atencion').length : null,
    toMake: mto ? mto.filter((m) => m.status === 'pendiente' || m.status === 'en_proceso').reduce((t, m) => t + m.quantity, 0) : null,
    toShip: ship ? ship.filter((s) => s.status === 'por_enviar').length : null,
    reservations: active ? active.length : null,
    reservationsSoon: active ? active.filter((x) => new Date(x.expires_at).getTime() - Date.now() < 48 * 3600_000).length : null,
    avisos: typeof badge === 'number' ? badge : null,
    customers: crm ? crm.customers : null,
    home,
  };
}
