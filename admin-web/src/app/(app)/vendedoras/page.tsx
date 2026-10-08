import { redirect } from 'next/navigation';
import { getMe, listLocations, rpc } from '@/lib/f360';
import type { Seller } from '../actions';
import { SellersPanel } from './SellersPanel';

// Vendedoras (owner only): who sells, at which store, with her PIN. Everything about a seller is managed here —
// the app reads her store from this assignment and opens it after her PIN.
export default async function Vendedoras() {
  const me = await getMe();
  if (me.role !== 'owner') redirect('/');
  const [sellers, locations] = await Promise.all([rpc<Seller[]>('f360_admin_sellers'), listLocations()]);
  const stores = locations.filter((l) => l.sellable && (l.type === 'store' || l.type === 'bazaar')).map((l) => ({ id: l.id, name: l.name }));
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="font-display text-5xl text-ink">Vendedoras</h1>
      <p className="mt-2 text-ink-2">Quién vende y en qué tienda. La vendedora entra a la app con su WhatsApp y su PIN, y la app abre su tienda sola.</p>
      <SellersPanel sellers={sellers} stores={stores} />
    </div>
  );
}
