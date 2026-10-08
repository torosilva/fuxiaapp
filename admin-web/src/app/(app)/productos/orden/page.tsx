import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, getStoreOrder } from '@/lib/f360';
import { publisherAvailable } from '@/lib/env-guard';
import { STORE_KEY } from '@/lib/store';
import { StoreOrderPanel } from './StoreOrderPanel';

// "Orden en la tienda" (Mario 2026-10-06): which models the shop shows first. Destacados first (in the order chosen here),
// then the rest by units sold (last 60 days, every channel, plus the old store's own sales), then the newest.
export default async function OrdenTienda() {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/productos'); // D13: owner/operator only (enforced by f360_store_order)
  const order = await getStoreOrder();
  const storeName = STORE_KEY === 'woo_production' ? 'fuxiaballerinas.com' : 'la tienda de pruebas';
  return (
    <div>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <Link href="/productos" className="text-sm text-ink-2 hover:text-ink">← Productos</Link>
          <h1 className="font-display text-5xl text-ink">Orden en la tienda</h1>
          <p className="mt-2 max-w-2xl text-ink-2">
            Así aparecen los modelos en {storeName}: primero los <b>⭐ destacados</b> en el orden que elijas, luego los <b>más vendidos</b> (últimos 60 días,
            tiendas y en línea) y al final los más nuevos. Cuando cambies algo, pulsa <b>Aplicar a la tienda</b>.
          </p>
        </div>
      </div>
      <StoreOrderPanel order={order} canEdit={canWrite(me.role)} canApply={me.role === 'owner' && publisherAvailable()} storeName={storeName} />
    </div>
  );
}
