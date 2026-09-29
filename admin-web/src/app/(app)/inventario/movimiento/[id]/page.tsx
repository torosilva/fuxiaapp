import Link from 'next/link';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconBack } from '@/components/icons';
import { getEvent } from '@/lib/f360';
import { eventSentence, fecha, pares } from '@/lib/format';

const TYPE: Record<string, string> = { RECEIPT: 'Recepción', TRANSFER: 'Traspaso', SALE: 'Venta', RETURN: 'Devolución', ADJUSTMENT: 'Ajuste' };

export default async function Movimiento({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const e = await getEvent(id);
  const groups = new Map<string, { productId: string; name: string; image: string | null; color: string; hex: string | null; lines: { size: string; quantity: number }[] }>();
  for (const l of e.lines) {
    const k = `${l.product_id}|${l.color}`;
    if (!groups.has(k)) groups.set(k, { productId: l.product_id, name: l.product_name, image: l.product_image, color: l.color, hex: l.color_hex, lines: [] });
    groups.get(k)!.lines.push({ size: l.size, quantity: l.quantity });
  }
  return (
    <div className="mx-auto max-w-2xl">
      <Link href="/inventario?vista=historial" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Historial</Link>
      <p className="mt-6 text-xs uppercase tracking-[0.25em] text-gold">{TYPE[e.type] ?? e.type}</p>
      <h1 className="font-display mt-2 text-5xl leading-tight text-ink">{eventSentence(e)}</h1>
      <p className="mt-2 text-ink-2">{fecha(e.occurred_at)}</p>
      {e.note && <p className="mt-6 rounded-2xl bg-surface-2 px-5 py-4 text-ink-2">“{e.note}”</p>}

      {[...groups.values()].map((g) => (
        <div key={g.productId + g.color} className="mt-6 rounded-3xl border border-line bg-surface p-5">
          <Link href={`/productos/${g.productId}`} className="flex items-center gap-4">
            <div className="size-16 shrink-0 overflow-hidden rounded-2xl"><ProductImage path={g.image} name={g.name} /></div>
            <div><div className="font-display text-3xl leading-none text-ink">{g.name}</div><div className="mt-1 flex items-center gap-2 text-ink-2"><ColorDot hex={g.hex} />{g.color}</div></div>
          </Link>
          <div className="mt-4 divide-y divide-line">
            {g.lines.map((l) => (
              <div key={l.size} className="tabular flex justify-between py-2.5 text-lg"><span className="text-ink-2">Talla {l.size}</span><span className="font-semibold text-ink">{l.quantity}</span></div>
            ))}
            <div className="tabular flex justify-between py-2.5 text-lg"><span className="text-ink-2">Total</span><span className="font-semibold text-ink">{pares(g.lines.reduce((a, l) => a + l.quantity, 0))}</span></div>
          </div>
        </div>
      ))}
      <p className="mt-8 text-center text-sm text-muted">Este registro es permanente y no se puede modificar.</p>
    </div>
  );
}
