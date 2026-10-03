'use client';
import { useMemo, useState } from 'react';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import type { Product } from '@/lib/f360';
import { imageUrl, precio } from '@/lib/format';

// Storefront preview: ONE model; color selector swaps photos and size availability; each color × size is one
// future Woo variation whose online stock = balance at the online fulfillment location (Bodega CDMX in V1).
export function StorefrontPreview({ product, initialColorId }: { product: Product; initialColorId: string | null }) {
  const firstWithStock = product.colors.find((c) => c.balances.some((b) => b.location_id === product.online_location?.id));
  const [colorId, setColorId] = useState(initialColorId ?? firstWithStock?.id ?? product.colors[0]?.id);
  const color = product.colors.find((c) => c.id === colorId) ?? product.colors[0];
  const [size, setSize] = useState<string | null>(null);
  const [photo, setPhoto] = useState(0);

  const online = (colorKey: string, s: string) =>
    product.colors.find((c) => c.id === colorKey)?.balances.find((b) => b.size === s && b.location_id === product.online_location?.id)?.on_hand ?? 0;
  const variant = color?.variants.find((v) => v.size === size) ?? null;
  const stock = variant && color ? online(color.id, variant.size) : 0;
  const photos = color?.media ?? [];
  const totalVariations = product.colors.length * product.sizes.length;
  const sobrePedido = product.make_to_order !== false;   // a size at 0 can still be bought, shipped in 5–7 business days

  const matrix = useMemo(() => product.colors.map((c) => ({
    color: c, rows: c.variants.map((v) => ({ sku: v.sku, size: v.size, stock: online(c.id, v.size) })),
  // eslint-disable-next-line react-hooks/exhaustive-deps
  })), [product]);

  if (!color) return <p className="mt-8 text-ink-2">Agrega al menos un color para ver la vista previa.</p>;

  return (
    <div>
      <div className="mt-6 grid gap-8 rounded-3xl border border-line bg-white p-5 md:grid-cols-2 md:p-8">
        {/* Gallery for the selected color */}
        <div>
          <div className="aspect-[4/5] overflow-hidden rounded-2xl bg-surface-2" data-testid="preview-main-photo" data-path={photos[photo]?.path ?? ''}>
            <ProductImage path={photos[photo]?.path ?? color.image_path} name={product.name} />
          </div>
          {photos.length > 1 && (
            <div className="mt-3 flex gap-2 overflow-x-auto">
              {photos.map((m, i) => (
                <button key={m.id} type="button" onClick={() => setPhoto(i)} aria-label={`Foto ${i + 1}`}
                  className={`size-16 shrink-0 overflow-hidden rounded-xl border-2 ${i === photo ? 'border-ink' : 'border-transparent'}`}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={imageUrl(m.path) ?? ''} alt="" className="h-full w-full object-cover" />
                </button>
              ))}
            </div>
          )}
          {photos.length === 0 && <p className="mt-3 text-sm text-muted">Este color todavía no tiene fotos.</p>}
        </div>

        {/* Product info as a customer would see it */}
        <div>
          <h1 className="font-display text-5xl uppercase tracking-wide text-ink">{product.name}</h1>
          <p className="mt-1 text-lg text-ink-2" data-testid="preview-selected-color">{color.name}</p>
          <p className="tabular mt-4 text-2xl text-ink">
            {product.sale_price != null ? <><span className="font-semibold">{precio(product.sale_price)}</span> <span className="text-lg text-muted line-through">{precio(product.regular_price)}</span></>
              : product.regular_price != null ? <span className="font-semibold">{precio(product.regular_price)}</span> : <span className="text-base text-muted">Sin precio todavía</span>}
          </p>
          {product.short_description && <p className="mt-4 text-ink-2">{product.short_description}</p>}

          <p className="mt-6 text-sm uppercase tracking-[0.2em] text-muted">Color</p>
          <div className="mt-2 flex flex-wrap gap-2">
            {product.colors.map((c) => {
              const any = c.variants.some((v) => online(c.id, v.size) > 0);
              return (
                <button key={c.id} type="button" aria-pressed={c.id === color.id} aria-label={`Color ${c.name}`}
                  onClick={() => { setColorId(c.id); setSize(null); setPhoto(0); }}
                  className={`flex items-center gap-2 rounded-full border px-4 py-2.5 transition ${c.id === color.id ? 'border-ink ring-1 ring-ink' : 'border-line hover:border-ink/40'} ${any ? 'text-ink' : 'text-muted'}`}>
                  <ColorDot hex={c.hex} className="size-5" />{c.name}
                </button>
              );
            })}
          </div>

          <p className="mt-6 text-sm uppercase tracking-[0.2em] text-muted">Talla <span className="normal-case tracking-normal">(colombiana)</span></p>
          <div className="mt-2 grid grid-cols-6 gap-2">
            {color.variants.map((v) => {
              const n = online(color.id, v.size);
              return (
                <button key={v.id} type="button" disabled={n === 0 && !sobrePedido} aria-pressed={size === v.size} aria-label={`Talla ${v.size}${n === 0 ? (sobrePedido ? ' se entrega en 5 a 7 días hábiles' : ' agotada') : ''}`}
                  onClick={() => setSize(v.size)}
                  className={`tabular rounded-xl border py-3 text-lg ${size === v.size ? 'border-ink bg-ink text-surface' : n === 0 && !sobrePedido ? 'cursor-not-allowed border-line text-line line-through' : n === 0 ? 'border-dashed border-line text-ink-2 hover:border-ink' : 'border-line text-ink hover:border-ink'}`}>
                  {v.size}
                </button>
              );
            })}
          </div>

          <div className="mt-6 rounded-2xl bg-surface-2 p-4" data-testid="preview-variation">
            {variant ? (
              <>
                <p className="text-ink"><strong>{product.name} · {color.name} · {variant.size}</strong></p>
                {stock === 0 && sobrePedido
                  ? <p className="mt-1 text-ink-2">Esta talla y color se entrega en <b>5 a 7 días hábiles</b></p>
                  : <p className="tabular mt-1 text-ink-2">{stock} {stock === 1 ? 'disponible' : 'disponibles'} en línea</p>}
                <p className="mt-1 font-mono text-xs text-muted">{variant.sku}</p>
              </>
            ) : (
              <p className="text-ink-2">{sobrePedido || color.variants.some((v) => online(color.id, v.size) > 0) ? 'Elige una talla' : `Sin existencia en línea para ${color.name}`}</p>
            )}
          </div>
          <button type="button" disabled={!variant || (stock === 0 && !sobrePedido)} className="mt-4 w-full rounded-2xl bg-ink py-4 text-lg text-surface disabled:bg-surface-2 disabled:text-muted">Añadir al carrito (vista previa)</button>
        </div>
      </div>

      <details className="mt-8 rounded-2xl border border-line bg-surface p-5">
        <summary className="cursor-pointer text-ink-2">Variaciones que tendrá la tienda: {totalVariations} ({product.colors.length} {product.colors.length === 1 ? 'color' : 'colores'} × {product.sizes.length} tallas)</summary>
        <div className="mt-4 space-y-4">
          {matrix.map(({ color: c, rows }) => (
            <div key={c.id}>
              <p className="flex items-center gap-2 text-ink"><ColorDot hex={c.hex} className="size-3" />{c.name}</p>
              <div className="mt-2 grid gap-1 sm:grid-cols-2 lg:grid-cols-3">
                {rows.map((r) => (
                  <div key={r.size} className="tabular flex justify-between rounded-lg bg-surface-2 px-3 py-1.5 text-sm">
                    <span className="font-mono text-xs text-ink-2">{r.sku}</span><span className={r.stock ? 'font-semibold text-ink' : 'text-muted'}>{r.stock}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </details>
    </div>
  );
}
