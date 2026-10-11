import { imageUrl } from '@/lib/format';
import type { Block, ProductCard } from '@/lib/academy';

// One lesson card. Product facts come ONLY from the validated snapshot (ProductCard); a missing field says "pendiente".
const P = '⏳ pendiente de validación';
export function SourceTag({ s }: { s: string }) {
  return <span className="mt-3 inline-block rounded-full bg-surface-2 px-2 py-0.5 text-[11px] text-muted">{s}</span>;
}
export function Ficha({ p, compact = false, onlySize = false }: { p: ProductCard; compact?: boolean; onlySize?: boolean }) {
  if (!p) return <p className="rounded-xl bg-danger-soft px-3 py-2 text-sm text-danger">Ficha no validada: no se muestra.</p>;
  const k = p.knowledge;
  const tag = `Ficha validada v${k.version} · ${k.validated_at?.slice(0, 10)}`;
  const img = imageUrl(p.photo);
  return (
    <div className="flex flex-col gap-3">
      {img && !onlySize && <img src={img} alt={p.name} loading="eager" decoding="async" className={`w-full rounded-2xl bg-surface-2 object-cover ${compact ? 'aspect-[4/3]' : 'aspect-square'}`} />}
      <h3 className="font-display text-2xl text-ink">{p.name}</h3>
      {!onlySize && <p className="text-sm text-ink-2">Colores: {p.colors?.map((c) => c.name).join(', ') || '—'} · Tallas {p.sizes?.join(', ')}</p>}
      <dl className="grid grid-cols-[auto,1fr] gap-x-3 gap-y-1.5 text-sm">
        <dt className="text-muted">Talla</dt><dd className="text-ink">{k.fit?.label ?? P}{k.fit?.note ? ` — “${k.fit.note.trim()}”` : ''}</dd>
        <dt className="text-muted">Entre dos tallas</dt><dd className="text-ink">{k.fit?.between_sizes ?? P}</dd>
        {!onlySize && <>
          <dt className="text-muted">Horma</dt><dd className="text-ink">{k.last ?? P}</dd>
          <dt className="text-muted">Ancho</dt><dd className="text-ink">{k.width ?? P}</dd>
          <dt className="text-muted">Punta</dt><dd className="text-ink">{k.toe ?? P}</dd>
          <dt className="text-muted">Materiales</dt><dd className="text-ink">{[k.materials?.upper && `exterior ${k.materials.upper}`, k.materials?.lining && `forro ${k.materials.lining}`, k.materials?.sole && `suela ${k.materials.sole}`].filter(Boolean).join(' · ') || P}</dd>
          <dt className="text-muted">Comodidad</dt><dd className="text-ink">{k.comfort ?? P}</dd>
          <dt className="text-muted">Cuidados</dt><dd className="text-ink">{k.care ?? P}</dd>
        </>}
      </dl>
      <SourceTag s={tag} />
    </div>
  );
}
export function CardView({ b, products }: { b: Block; products: Record<string, ProductCard> }) {
  if (b.type === 'ficha' || b.type === 'ficha_talla') return <Ficha p={products[b.code ?? ''] ?? null} onlySize={b.type === 'ficha_talla'} />;
  if (b.type === 'video' && b.src) return <video src={b.src} poster={b.poster} controls playsInline preload="metadata" className="aspect-[9/16] w-full rounded-2xl bg-ink object-cover" />;
  if (b.type === 'pendiente') return <p className="rounded-xl bg-gold-soft px-3 py-3 text-sm text-ink-2">⏳ {b.text}</p>;
  return (
    <div>
      <p className="text-lg leading-relaxed text-ink">{b.text}</p>
      {b.source && <SourceTag s={b.source} />}
    </div>
  );
}
