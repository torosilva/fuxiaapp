import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, listLocations, listReservations } from '@/lib/f360';
import { ReservationsClient } from './ReservationsClient';

// Apartados: pairs a customer reserved for 3 hours in a store (any customer since 2026-10-09; WhatsApp-verified on the web). They stay on hand; nobody else can take
// them until she buys them (sale with her card), cancels, or they expire. Nothing happens if she does not come.
export default async function Apartados({ searchParams }: { searchParams: Promise<{ tienda?: string }> }) {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const { tienda } = await searchParams;
  const [stores, rows] = await Promise.all([listLocations(), listReservations(tienda)]);
  const shops = stores.filter((l) => l.type === 'store' || l.type === 'bazaar');
  return (
    <div className="mx-auto max-w-5xl">
      <h1 className="font-display text-5xl text-ink">Apartados</h1>
      <p className="mt-2 text-ink-2">Pares que una clienta apartó por 3 horas (desde la tienda en línea, con su WhatsApp confirmado, o desde la app). Siguen en la tienda, pero no se le pueden vender a otra persona. Si viene, se vende con su tarjeta y el apartado se cierra solo; si no viene, se libera a las 3 horas sin consecuencias.</p>
      <nav className="mt-5 flex flex-wrap gap-2">
        <Link href="/apartados" className={`rounded-full px-4 py-2 text-sm ${!tienda ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>Todas las tiendas</Link>
        {shops.map((s) => <Link key={s.id} href={`/apartados?tienda=${s.id}`} className={`rounded-full px-4 py-2 text-sm ${tienda === s.id ? 'bg-ink text-surface' : 'bg-surface text-ink-2 ring-1 ring-line'}`}>{s.name}</Link>)}
      </nav>
      <ReservationsClient rows={rows} />
    </div>
  );
}
