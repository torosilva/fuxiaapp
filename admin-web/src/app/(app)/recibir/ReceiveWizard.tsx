'use client';
import Link from 'next/link';
import { useMemo, useState, useTransition } from 'react';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconBack, IconCheck, IconMinus, IconPlus, IconSearch } from '@/components/icons';
import type { Color, InventoryEvent, Location, Product, ProductSummary } from '@/lib/f360';
import { pares } from '@/lib/format';
import { getProductAction, receiveInventoryAction } from '../actions';

type Step = 'product' | 'color' | 'quantities' | 'done';

export function ReceiveWizard({ products, locations, initialProduct, initialColorId }: {
  products: ProductSummary[]; locations: Location[]; initialProduct: Product | null; initialColorId: string | null;
}) {
  const initialColor = initialProduct?.colors.find((c) => c.id === initialColorId) ?? (initialProduct?.colors.length === 1 ? initialProduct.colors[0] : null);
  const [step, setStep] = useState<Step>(initialProduct ? (initialColor ? 'quantities' : 'color') : 'product');
  const [product, setProduct] = useState<Product | null>(initialProduct);
  const [color, setColor] = useState<Color | null>(initialColor);
  const [qty, setQty] = useState<Record<string, number>>({});
  const defaultLocation = locations.find((l) => l.is_authoritative) ?? locations[0];
  const [locationId, setLocationId] = useState<string>(defaultLocation?.id ?? '');
  const [note, setNote] = useState('');
  const [query, setQuery] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [idemKey, setIdemKey] = useState(() => crypto.randomUUID());   // one key per receipt: a double tap can't duplicate it
  const [result, setResult] = useState<{ event: InventoryEvent; after: Product } | null>(null);

  const total = useMemo(() => Object.values(qty).reduce((a, n) => a + n, 0), [qty]);
  const location = locations.find((l) => l.id === locationId);
  const filtered = products.filter((p) => !query.trim() || p.name.toLowerCase().includes(query.trim().toLowerCase()));

  const pickProduct = (id: string) => start(async () => {
    setError(null);
    const r = await getProductAction(id);
    if (!r.ok) return setError(r.error);
    setProduct(r.data);
    setQty({});
    if (r.data.colors.length === 1) { setColor(r.data.colors[0]); setStep('quantities'); } else { setColor(null); setStep('color'); }
  });

  const setSize = (variantId: string, n: number) => setQty((q) => ({ ...q, [variantId]: Math.max(0, Math.min(9999, Math.floor(n) || 0)) }));

  const confirm = () => start(async () => {
    setError(null);
    if (!product || !color) return;
    const r = await receiveInventoryAction({ idempotencyKey: idemKey, locationId, note, lines: color.variants.map((v) => ({ variantId: v.id, quantity: qty[v.id] ?? 0 })) });
    if (!r.ok) return setError(r.error);
    const after = await getProductAction(product.id);
    setResult({ event: r.data, after: after.ok ? after.data : product });
    setStep('done');
  });

  const restart = (keepProduct: boolean) => {
    setIdemKey(crypto.randomUUID());
    setQty({}); setNote(''); setResult(null); setError(null);
    if (keepProduct && product && result) {
      setProduct(result.after);
      setColor(null);
      setStep(result.after.colors.length === 1 ? 'quantities' : 'color');
      if (result.after.colors.length === 1) setColor(result.after.colors[0]);
    } else { setProduct(null); setColor(null); setStep('product'); }
  };

  const back = () => {
    setError(null);
    if (step === 'quantities') setStep(product && product.colors.length > 1 ? 'color' : 'product');
    else if (step === 'color') setStep('product');
  };

  return (
    <div className="mx-auto max-w-2xl">
      {step !== 'done' && (
        <div className="flex items-center justify-between">
          {step === 'product' ? <Link href="/" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Inicio</Link>
            : <button type="button" onClick={back} className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Atrás</button>}
          <span className="text-sm text-muted">Recibir mercancía</span>
        </div>
      )}

      {/* 1 · Producto */}
      {step === 'product' && (
        <div>
          <h1 className="font-display mt-4 text-5xl text-ink">¿Qué producto llegó?</h1>
          <div className="relative mt-6">
            <IconSearch className="absolute left-4 top-1/2 size-5 -translate-y-1/2 text-muted" />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Busca el producto" autoFocus
              className="w-full rounded-2xl border border-line bg-surface py-4 pl-12 pr-4 text-lg outline-none focus:border-gold" />
          </div>
          <div className="mt-5 grid gap-3">
            {filtered.map((p) => (
              <button key={p.id} type="button" disabled={pending} onClick={() => pickProduct(p.id)}
                className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-3 text-left transition hover:border-gold/50 disabled:opacity-60">
                <div className="size-20 shrink-0 overflow-hidden rounded-xl"><ProductImage path={p.image_path} name={p.name} /></div>
                <div className="min-w-0 flex-1">
                  <div className="font-display text-3xl leading-tight text-ink">{p.name}</div>
                  <div className="mt-1 flex items-center gap-2 text-sm text-muted">
                    <span className="flex -space-x-1">{p.colors.map((c) => <ColorDot key={c.name} hex={c.hex} className="size-3.5 ring-2 ring-surface" />)}</span>
                    {p.colors.map((c) => c.name).join(', ')}
                  </div>
                </div>
              </button>
            ))}
            {filtered.length === 0 && <p className="rounded-2xl border border-dashed border-line bg-surface p-6 text-center text-ink-2">No encontramos ese producto.</p>}
            <Link href="/productos/nuevo" className="rounded-2xl border border-dashed border-line p-5 text-center text-ink-2 hover:border-gold/50">¿Es nuevo? <span className="text-gold-strong underline">Crear producto</span></Link>
          </div>
        </div>
      )}

      {/* 2 · Color */}
      {step === 'color' && product && (
        <div>
          <p className="mt-6 text-xs uppercase tracking-[0.25em] text-muted">{product.name}</p>
          <h1 className="font-display mt-1 text-5xl text-ink">¿Qué color?</h1>
          <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
            {product.colors.map((c) => (
              <button key={c.id} type="button" onClick={() => { setColor(c); setQty({}); setStep('quantities'); }}
                className="overflow-hidden rounded-2xl border border-line bg-surface text-left transition hover:border-gold/50">
                <div className="aspect-[4/3]">{c.image_path || product.image_path ? <ProductImage path={c.image_path ?? product.image_path} name={product.name} /> : <div className="h-full w-full" style={{ background: c.hex ?? '#e6dfd4' }} />}</div>
                <div className="flex items-center gap-2 p-4 text-lg text-ink"><ColorDot hex={c.hex} />{c.name}</div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* 3 · Tallas, cantidades y destino */}
      {step === 'quantities' && product && color && (
        <div className="pb-8">
          <div className="mt-6 flex items-center gap-4">
            <div className="size-20 shrink-0 overflow-hidden rounded-2xl"><ProductImage path={color.image_path ?? product.image_path} name={product.name} /></div>
            <div>
              <h1 className="font-display break-words text-4xl uppercase leading-none tracking-wide text-ink sm:text-5xl">{product.name}</h1>
              <p className="mt-1 flex items-center gap-2 text-xl text-ink-2"><ColorDot hex={color.hex} />{color.name}</p>
            </div>
          </div>

          <div className="mt-8 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
            {color.variants.map((v) => {
              const n = qty[v.id] ?? 0;
              return (
                <div key={v.id} className="flex items-center justify-between px-5 py-3">
                  <span className="tabular w-16 text-2xl text-ink">{v.size}</span>
                  <div className="flex items-center gap-2">
                    <button type="button" aria-label={`Menos talla ${v.size}`} onClick={() => setSize(v.id, n - 1)} disabled={n === 0}
                      className="flex size-14 items-center justify-center rounded-2xl border border-line text-ink transition active:scale-95 disabled:opacity-30"><IconMinus className="size-6" /></button>
                    <input aria-label={`Cantidad talla ${v.size}`} inputMode="numeric" value={n === 0 ? '' : n} placeholder="0"
                      onChange={(e) => setSize(v.id, Number(e.target.value.replace(/\D/g, '')))}
                      className={`tabular w-16 bg-transparent text-center text-3xl outline-none ${n ? 'font-semibold text-ink' : 'text-muted'}`} />
                    <button type="button" aria-label={`Más talla ${v.size}`} onClick={() => setSize(v.id, n + 1)}
                      className="flex size-14 items-center justify-center rounded-2xl bg-ink text-surface transition active:scale-95"><IconPlus className="size-6" /></button>
                  </div>
                </div>
              );
            })}
            <div className="flex items-center justify-between bg-surface-2 px-5 py-4">
              <span className="text-lg text-ink-2">Total</span>
              <span className="tabular text-2xl font-semibold text-ink">{pares(total)}</span>
            </div>
          </div>

          <h2 className="font-display mt-8 text-3xl text-ink">Destino</h2>
          <div className="mt-3 grid gap-3 sm:grid-cols-2">
            {locations.map((l) => (
              <button key={l.id} type="button" onClick={() => setLocationId(l.id)} aria-pressed={l.id === locationId}
                className={`rounded-2xl border p-5 text-left transition ${l.id === locationId ? 'border-ink bg-ink text-surface' : 'border-line bg-surface text-ink hover:border-gold/50'}`}>
                <div className="text-xl">{l.name}</div>
                <div className={`mt-1 text-sm ${l.id === locationId ? 'text-surface/70' : 'text-muted'}`}>{pares(l.pairs)} ahora</div>
                {l.sales_sync_pending && <div className="mt-2 text-xs opacity-80">Ventas de tienda aún no descontadas</div>}
              </button>
            ))}
          </div>

          <textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Nota (opcional): p. ej. llegó de Colombia, caja 3"
            rows={2} className="mt-6 w-full rounded-2xl border border-line bg-surface px-4 py-3 text-base outline-none focus:border-gold" />

          {error && <p role="alert" className="mt-4 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}

          <button type="button" onClick={confirm} disabled={pending || total === 0 || !locationId}
            className="mt-6 w-full rounded-2xl bg-ink py-6 text-xl font-semibold uppercase tracking-wider text-surface shadow-sm transition hover:bg-ink-2 disabled:bg-surface-2 disabled:text-muted">
            {pending ? 'Guardando…' : total === 0 ? 'Escribe las cantidades' : `Recibir ${pares(total)}`}
          </button>
          {location && total > 0 && <p className="mt-3 text-center text-sm text-muted">Se agregarán a {location.name}</p>}
        </div>
      )}

      {/* 4 · Listo */}
      {step === 'done' && result && product && color && (() => {
        const after = result.after.colors.find((c) => c.id === color.id) ?? color;
        const loc = result.event.lines[0]?.to_location ?? location?.name;
        const receivedSizes = new Set(result.event.lines.map((l) => l.size));
        return (
          <div className="pt-4 text-center">
            <div className="mx-auto flex size-20 items-center justify-center rounded-full bg-success-soft text-success"><IconCheck className="size-10" /></div>
            <h1 className="font-display mt-6 text-5xl text-ink">Inventario recibido correctamente</h1>
            <p className="mt-3 text-lg text-ink-2">{result.event.actor_name} recibió {pares(result.event.total_pairs)} en {loc}</p>

            <div className="mt-8 rounded-3xl border border-line bg-surface p-5 text-left">
              <div className="flex items-center gap-3">
                <div className="size-14 shrink-0 overflow-hidden rounded-xl"><ProductImage path={after.image_path ?? product.image_path} name={product.name} /></div>
                <div><div className="font-display text-3xl leading-none text-ink">{product.name}</div><div className="mt-1 flex items-center gap-2 text-ink-2"><ColorDot hex={after.hex} />{after.name}</div></div>
              </div>
              <p className="mt-5 text-sm text-muted">Ahora en {loc}</p>
              <div className="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-6">
                {after.variants.map((v) => {
                  const onHand = after.balances.find((b) => b.size === v.size && b.location_id === locationId)?.on_hand ?? 0;
                  return (
                    <div key={v.id} className={`rounded-xl px-2 py-2.5 text-center ${receivedSizes.has(v.size) ? 'bg-gold-soft' : 'bg-surface-2'}`}>
                      <div className="text-xs text-muted">Talla {v.size}</div>
                      <div className="tabular text-xl font-semibold text-ink">{onHand}</div>
                    </div>
                  );
                })}
              </div>
            </div>

            <div className="mt-8 grid gap-3 sm:grid-cols-2">
              <Link href={`/productos/${product.id}?color=${color.id}`} className="rounded-2xl bg-ink py-4 text-lg text-surface">Ver inventario del producto</Link>
              <Link href="/inventario?vista=historial" className="rounded-2xl border border-line bg-surface py-4 text-lg text-ink">Ver historial</Link>
              <button type="button" onClick={() => restart(true)} className="rounded-2xl border border-line bg-surface py-4 text-lg text-ink">Recibir otro color de {product.name}</button>
              <button type="button" onClick={() => restart(false)} className="rounded-2xl border border-line bg-surface py-4 text-lg text-ink">Recibir otro producto</button>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
