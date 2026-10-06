import { redirect } from 'next/navigation';
import { canWrite, getMe, listLegacyChannelsAvailable, listLocations } from '@/lib/f360';
import { LocationRow } from './LocationRow';
import { NewLocation } from './NewLocation';

// Stores, bazaars and warehouses (Fuxia 360 locations). Owners create them; a store that already runs on the legacy
// system is created LINKED to it and keeps its legacy inventory until its cut (C3) moves it to Fuxia 360.
// Altas (NewLocation), Cambios and Bajas (LocationRow): owner only.

export default async function Tiendas() {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const owner = me.role === 'owner';
  const [locations, legacy] = await Promise.all([listLocations(), owner ? listLegacyChannelsAvailable() : Promise.resolve([])]);
  return (
    <div className="mx-auto max-w-4xl">
      <h1 className="font-display text-5xl text-ink">Tiendas y ubicaciones</h1>
      <p className="mt-2 text-ink-2">Dónde hay pares: bodegas, tiendas y bazares. Cada ubicación lleva su propio inventario por modelo → color → talla.</p>
      <div className="mt-6 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface" data-testid="locations">
        {locations.map((l) => <LocationRow key={l.id} l={l} owner={owner} />)}
      </div>
      {owner ? <NewLocation legacy={legacy} /> : <p className="mt-8 text-sm text-muted">Solo una dueña da de alta ubicaciones.</p>}
    </div>
  );
}
