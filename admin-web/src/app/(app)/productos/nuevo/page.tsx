import Link from 'next/link';
import { redirect } from 'next/navigation';
import { IconBack } from '@/components/icons';
import { canWrite, getMe } from '@/lib/f360';
import { NewProductForm } from './NewProductForm';

export default async function NuevoProducto() {
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/productos');
  return (
    <div className="mx-auto max-w-2xl">
      <Link href="/productos" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Productos</Link>
      <h1 className="font-display mt-4 text-5xl text-ink">Nuevo producto</h1>
      <p className="mt-2 text-ink-2">Solo lo esencial: nombre, colores y tallas. Lo demás lo completas después.</p>
      <NewProductForm />
    </div>
  );
}
