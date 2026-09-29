import { redirect } from 'next/navigation';
import { canRequestTransfer, getTransferLocations, listProducts } from '@/lib/f360';
import { MoveWizard } from './MoveWizard';

// Mover inventario: origen → destino → producto/color/talla/cantidad → resumen → solicitar / enviar (según rol).
// Only locations whose stock lives in Fuxia 360 are offered; "En camino" and legacy stores never appear.
export default async function Mover() {
  const [info, products] = await Promise.all([getTransferLocations(), listProducts()]);
  if (!canRequestTransfer(info.role)) redirect('/');
  return <MoveWizard info={info} products={products} />;
}
