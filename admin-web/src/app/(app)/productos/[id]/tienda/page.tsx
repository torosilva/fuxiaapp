import Link from 'next/link';
import { IconBack } from '@/components/icons';
import { getProduct } from '@/lib/f360';
import { StorefrontPreview } from './StorefrontPreview';

export default async function VistaTienda({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ color?: string }> }) {
  const [{ id }, sp] = await Promise.all([params, searchParams]);
  const product = await getProduct(id);
  return (
    <div>
      <Link href={`/productos/${product.id}`} className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />{product.name}</Link>
      <div className="mt-4 rounded-2xl bg-gold-soft px-5 py-3 text-sm text-ink-2">
        Vista previa: así se verá <strong>un solo producto</strong> en la tienda en línea. Todavía no está publicado.
        {product.online_location && <> El inventario en línea sale de <strong>{product.online_location.name}</strong>.</>}
      </div>
      <StorefrontPreview product={product} initialColorId={sp.color ?? null} />
    </div>
  );
}
