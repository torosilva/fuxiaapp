import { redirect } from 'next/navigation';
import { canWrite, getMe, getProduct, listLocations, listProducts } from '@/lib/f360';
import { ReceiveWizard } from './ReceiveWizard';

export default async function Recibir({ searchParams }: { searchParams: Promise<{ producto?: string; color?: string }> }) {
  const sp = await searchParams;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');
  const [products, locations, initialProduct] = await Promise.all([
    listProducts(), listLocations(), sp.producto ? getProduct(sp.producto) : Promise.resolve(null),
  ]);
  // Track C · C1: only locations whose stock is mastered by Fuxia 360 (never a legacy store before its cutover)
  return <ReceiveWizard products={products} locations={locations.filter((l) => (l.ledger_authority ?? 'f360') === 'f360')} initialProduct={initialProduct} initialColorId={sp.color ?? null} />;
}
