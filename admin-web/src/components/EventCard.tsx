import Link from 'next/link';
import type { InventoryEvent } from '@/lib/f360';
import { eventSentence, fecha, referenceLabel } from '@/lib/format';
import { ColorDot, ProductImage } from './ProductImage';
import { IconBag, IconDown, IconMove } from './icons';

// One immutable history entry, in human language.
export function EventCard({ e, compact = false }: { e: InventoryEvent; compact?: boolean }) {
  const groups = new Map<string, { name: string; image: string | null; color: string; hex: string | null; lines: { size: string; quantity: number }[] }>();
  for (const l of e.lines) {
    const k = `${l.product_id}|${l.color}`;
    if (!groups.has(k)) groups.set(k, { name: l.product_name, image: l.product_image, color: l.color, hex: l.color_hex, lines: [] });
    groups.get(k)!.lines.push({ size: l.size, quantity: l.quantity });
  }
  const Icon = e.type === 'TRANSFER' ? IconMove : e.type === 'SALE' ? IconBag : IconDown;
  const ref = referenceLabel(e.reference_type, e.reference_id);
  return (
    <Link href={`/inventario/movimiento/${e.id}`} className="block rounded-2xl border border-line bg-surface p-4 transition hover:border-gold/40 md:p-5">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full bg-gold-soft text-gold-strong"><Icon className="size-5" /></span>
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-medium text-ink">{eventSentence(e)}</p>
          <p className="mt-0.5 text-sm text-muted">{fecha(e.occurred_at)}{ref ? ` · ${ref}` : ''}</p>
          {!compact && [...groups.values()].map((g) => (
            <div key={g.name + g.color} className="mt-3 flex items-center gap-3">
              <div className="size-12 shrink-0 overflow-hidden rounded-lg"><ProductImage path={g.image} name={g.name} /></div>
              <div className="min-w-0">
                <div className="flex items-center gap-2 text-sm font-medium text-ink-2"><span className="truncate">{g.name}</span><ColorDot hex={g.hex} className="size-3" /><span className="text-muted">{g.color}</span></div>
                <div className="mt-1 flex flex-wrap gap-1.5">
                  {g.lines.map((l) => (
                    <span key={l.size} className="tabular rounded-md bg-surface-2 px-2 py-0.5 text-xs text-ink-2">Talla {l.size} · {l.quantity}</span>
                  ))}
                </div>
              </div>
            </div>
          ))}
          {!compact && e.note && !ref && <p className="mt-3 rounded-lg bg-surface-2 px-3 py-2 text-sm text-ink-2">“{e.note}”</p>}
        </div>
      </div>
    </Link>
  );
}
