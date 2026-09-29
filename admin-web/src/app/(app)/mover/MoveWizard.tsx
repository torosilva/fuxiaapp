'use client';
import Link from 'next/link';
import { useMemo, useState, useTransition } from 'react';
import { ColorDot, ProductImage } from '@/components/ProductImage';
import { IconBack, IconCheck, IconMinus, IconPlus, IconSearch, IconTruck } from '@/components/icons';
import type { Color, Product, ProductSummary, Transfer, TransferLocations } from '@/lib/f360';
import { pares } from '@/lib/format';
import { getProductAction, requestTransferAction } from '../actions';

type Step = 'from' | 'to' | 'product' | 'color' | 'sizes' | 'summary' | 'done';
type CartLine = { variantId: string; productId: string; productName: string; image: string | null; color: string; hex: string | null; size: string; quantity: number; available: number };

export function MoveWizard({ info, products }: { info: TransferLocations; products: ProductSummary[] }) {
  const [step, setStep] = useState<Step>('from');
  const [fromId, setFromId] = useState('');
  const [toId, setToId] = useState('');
  const [product, setProduct] = useState<Product | null>(null);
  const [color, setColor] = useState<Color | null>(null);
  const [qty, setQty] = useState<Record<string, number>>({});
  const [cart, setCart] = useState<CartLine[]>([]);
  const [note, setNote] = useState('');
  const [query, setQuery] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const [idemKey, setIdemKey] = useState(() => crypto.randomUUID());   // one key per transfer: a double click can't duplicate it
  const [result, setResult] = useState<Transfer | null>(null);

  const locs = info.locations;
  const from = locs.find((l) => l.id === fromId);
  const to = locs.find((l) => l.id === toId);
  // A seller may move merchandise only when the origin or the destination is one of her locations (enforced again in the database).
  const destinations = locs.filter((l) => l.id !== fromId && (info.can_send || from?.mine || l.mine));
  const total = cart.reduce((a, l) => a + l.quantity, 0);
  const short = cart.filter((l) => l.quantity > l.available);
  const filtered = products.filter((p) => !query.trim() || p.name.toLowerCase().includes(query.trim().toLowerCase()));
  const sizeTotal = useMemo(() => Object.values(qty).reduce((a, n) => a + n, 0), [qty]);
  const available = (c: Color, size: string) => c.balances.find((b) => b.size === size && b.location_id === fromId)?.on_hand ?? 0;

  const pickProduct = (id: string) => start(async () => {
    setError(null);
    const r = await getProductAction(id);
    if (!r.ok) return setError(r.error);
    setProduct(r.data);
    if (r.data.colors.length === 1) openColor(r.data.colors[0]); else { setColor(null); setStep('color'); }
  });
  const openColor = (c: Color) => {
    setColor(c);
    setQty(Object.fromEntries(cart.filter((l) => c.variants.some((v) => v.id === l.variantId)).map((l) => [l.variantId, l.quantity])));
    setStep('sizes');
  };
  const setSize = (variantId: string, n: number) => setQty((q) => ({ ...q, [variantId]: Math.max(0, Math.min(999, Math.floor(n) || 0)) }));
  const addToCart = () => {
    if (!product || !color) return;
    const keep = cart.filter((l) => !color.variants.some((v) => v.id === l.variantId));
    const add = color.variants.filter((v) => (qty[v.id] ?? 0) > 0).map((v) => ({
      variantId: v.id, productId: product.id, productName: product.name, image: color.image_path ?? product.image_path, color: color.name, hex: color.hex,
      size: v.size, quantity: qty[v.id], available: available(color, v.size) }));
    setCart([...keep, ...add]);
    setQty({}); setProduct(null); setColor(null); setQuery('');
    setStep('summary');
  };
  const submit = (sendNow: boolean) => start(async () => {
    setError(null);
    const r = await requestTransferAction({ idempotencyKey: idemKey, fromId, toId, note, sendNow, lines: cart.map((l) => ({ variantId: l.variantId, quantity: l.quantity })) });
    if (!r.ok) return setError(r.error);
    setResult(r.data);
    setStep('done');
  });
  const restart = () => {
    setIdemKey(crypto.randomUUID()); setCart([]); setNote(''); setResult(null); setError(null); setFromId(''); setToId(''); setStep('from');
  };
  const back = () => {
    setError(null);
    const prev: Partial<Record<Step, Step>> = { to: 'from', product: cart.length ? 'summary' : 'to', color: 'product', sizes: product && product.colors.length > 1 ? 'color' : 'product', summary: 'to' };
    setStep(prev[step] ?? 'from');
  };

  const choice = (active: boolean) => `rounded-2xl border p-5 text-left transition ${active ? 'border-ink bg-ink text-surface' : 'border-line bg-surface text-ink hover:border-gold/50'}`;
  const route = from && to && (
    <p className="mt-2 flex flex-wrap items-center gap-2 text-lg text-ink-2"><span>{from.name}</span><IconTruck className="size-5 text-gold-strong" /><span>{to.name}</span></p>
  );

  return (
    <div className="mx-auto max-w-2xl">
      {step !== 'done' && (
        <div className="flex items-center justify-between">
          {step === 'from' ? <Link href="/" className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Inicio</Link>
            : <button type="button" onClick={back} className="inline-flex items-center gap-1 text-sm text-muted hover:text-ink"><IconBack className="size-4" />Atrás</button>}
          <span className="text-sm text-muted">Mover inventario</span>
        </div>
      )}

      {step === 'from' && (
        <div>
          <h1 className="font-display mt-4 text-5xl text-ink">¿De dónde sale?</h1>
          <div className="mt-6 grid gap-3 sm:grid-cols-2">
            {locs.map((l) => (
              <button key={l.id} type="button" onClick={() => { setFromId(l.id); if (toId === l.id) setToId(''); setCart([]); setStep('to'); }} className={choice(l.id === fromId)}>
                <div className="text-xl">{l.name}</div>
                <div className="mt-1 text-sm opacity-70">{pares(l.pairs)} disponibles</div>
              </button>
            ))}
          </div>
          {locs.length < 2 && <p className="mt-6 rounded-2xl border border-dashed border-line bg-surface p-6 text-center text-ink-2">Se necesitan al menos dos ubicaciones que ya lleven su inventario en Fuxia 360.</p>}
        </div>
      )}

      {step === 'to' && from && (
        <div>
          <p className="mt-6 text-xs uppercase tracking-[0.25em] text-muted">Sale de {from.name}</p>
          <h1 className="font-display mt-1 text-5xl text-ink">¿A dónde va?</h1>
          <div className="mt-6 grid gap-3 sm:grid-cols-2">
            {destinations.map((l) => (
              <button key={l.id} type="button" onClick={() => { setToId(l.id); setStep(cart.length ? 'summary' : 'product'); }} className={choice(l.id === toId)}>
                <div className="text-xl">{l.name}</div>
                <div className="mt-1 text-sm opacity-70">{pares(l.pairs)} ahora</div>
              </button>
            ))}
          </div>
          {destinations.length === 0 && <p className="mt-6 rounded-2xl border border-dashed border-line bg-surface p-6 text-center text-ink-2">No tienes una ubicación asignada para recibir desde aquí.</p>}
        </div>
      )}

      {step === 'product' && (
        <div>
          {route}
          <h1 className="font-display mt-4 text-5xl text-ink">¿Qué producto?</h1>
          <div className="relative mt-6">
            <IconSearch className="absolute left-4 top-1/2 size-5 -translate-y-1/2 text-muted" />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Busca el producto" autoFocus
              className="w-full rounded-2xl border border-line bg-surface py-4 pl-12 pr-4 text-lg outline-none focus:border-gold" />
          </div>
          <div className="mt-5 grid gap-3">
            {filtered.map((p) => (
              <button key={p.id} type="button" disabled={pending} onClick={() => pickProduct(p.id)}
                className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-3 text-left transition hover:border-gold/50 disabled:opacity-60">
                <div className="size-16 shrink-0 overflow-hidden rounded-xl"><ProductImage path={p.image_path} name={p.name} /></div>
                <div className="min-w-0 flex-1">
                  <div className="font-display text-3xl leading-tight text-ink">{p.name}</div>
                  <div className="mt-1 flex items-center gap-2 text-sm text-muted">
                    <span className="flex -space-x-1">{p.colors.map((c) => <ColorDot key={c.name} hex={c.hex} className="size-3.5 ring-2 ring-surface" />)}</span>
                    {p.colors.map((c) => c.name).join(', ')}
                  </div>
                </div>
              </button>
            ))}
          </div>
          {error && <p role="alert" className="mt-4 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
        </div>
      )}

      {step === 'color' && product && (
        <div>
          {route}
          <p className="mt-4 text-xs uppercase tracking-[0.25em] text-muted">{product.name}</p>
          <h1 className="font-display mt-1 text-5xl text-ink">¿Qué color?</h1>
          <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
            {product.colors.map((c) => {
              const here = c.variants.reduce((a, v) => a + available(c, v.size), 0);
              return (
                <button key={c.id} type="button" onClick={() => openColor(c)} className="overflow-hidden rounded-2xl border border-line bg-surface text-left transition hover:border-gold/50">
                  <div className="aspect-[4/3]">{c.image_path || product.image_path ? <ProductImage path={c.image_path ?? product.image_path} name={product.name} /> : <div className="h-full w-full" style={{ background: c.hex ?? '#e6dfd4' }} />}</div>
                  <div className="p-4"><div className="flex items-center gap-2 text-lg text-ink"><ColorDot hex={c.hex} />{c.name}</div><div className="text-sm text-muted">{pares(here)} en {from?.name}</div></div>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {step === 'sizes' && product && color && (
        <div className="pb-8">
          {route}
          <div className="mt-6 flex items-center gap-4">
            <div className="size-16 shrink-0 overflow-hidden rounded-2xl"><ProductImage path={color.image_path ?? product.image_path} name={product.name} /></div>
            <div>
              <h1 className="font-display text-4xl uppercase leading-none tracking-wide text-ink">{product.name}</h1>
              <p className="mt-1 flex items-center gap-2 text-xl text-ink-2"><ColorDot hex={color.hex} />{color.name}</p>
            </div>
          </div>
          <div className="mt-8 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
            {color.variants.map((v) => {
              const n = qty[v.id] ?? 0;
              const have = available(color, v.size);
              const cap = info.can_send ? have : 999;   // operation can only move what is there; a request is a wish (checked at send)
              return (
                <div key={v.id} className="flex items-center justify-between px-5 py-3">
                  <div><div className="tabular text-2xl text-ink">{v.size}</div><div className={`text-xs ${have === 0 ? 'text-danger' : 'text-muted'}`}>hay {have}</div></div>
                  <div className="flex items-center gap-2">
                    <button type="button" aria-label={`Menos talla ${v.size}`} onClick={() => setSize(v.id, n - 1)} disabled={n === 0}
                      className="flex size-14 items-center justify-center rounded-2xl border border-line text-ink transition active:scale-95 disabled:opacity-30"><IconMinus className="size-6" /></button>
                    <input aria-label={`Cantidad talla ${v.size}`} inputMode="numeric" value={n === 0 ? '' : n} placeholder="0"
                      onChange={(e) => setSize(v.id, Math.min(cap, Number(e.target.value.replace(/\D/g, ''))))}
                      className={`tabular w-16 bg-transparent text-center text-3xl outline-none ${n ? 'font-semibold text-ink' : 'text-muted'}`} />
                    <button type="button" aria-label={`Más talla ${v.size}`} onClick={() => setSize(v.id, n + 1)} disabled={n >= cap}
                      className="flex size-14 items-center justify-center rounded-2xl bg-ink text-surface transition active:scale-95 disabled:opacity-30"><IconPlus className="size-6" /></button>
                  </div>
                </div>
              );
            })}
            <div className="flex items-center justify-between bg-surface-2 px-5 py-4"><span className="text-lg text-ink-2">Total</span><span className="tabular text-2xl font-semibold text-ink">{pares(sizeTotal)}</span></div>
          </div>
          <button type="button" onClick={addToCart} disabled={sizeTotal === 0}
            className="mt-6 w-full rounded-2xl bg-ink py-5 text-xl font-semibold text-surface transition hover:bg-ink-2 disabled:bg-surface-2 disabled:text-muted">
            {sizeTotal === 0 ? 'Escribe las cantidades' : `Agregar ${pares(sizeTotal)}`}
          </button>
        </div>
      )}

      {step === 'summary' && from && to && (
        <div className="pb-8">
          <h1 className="font-display mt-4 text-5xl text-ink">Resumen</h1>
          {route}
          <div className="mt-6 divide-y divide-line overflow-hidden rounded-3xl border border-line bg-surface">
            {cart.map((l) => (
              <div key={l.variantId} className="flex items-center gap-3 px-4 py-3">
                <div className="size-12 shrink-0 overflow-hidden rounded-lg"><ProductImage path={l.image} name={l.productName} /></div>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-medium text-ink">{l.productName}</div>
                  <div className="flex items-center gap-2 text-sm text-muted"><ColorDot hex={l.hex} className="size-3" />{l.color} · Talla {l.size}{l.quantity > l.available ? <span className="text-danger">· hay {l.available}</span> : null}</div>
                </div>
                <span className="tabular text-xl font-semibold text-ink">{l.quantity}</span>
                <button type="button" aria-label={`Quitar ${l.productName} ${l.color} ${l.size}`} onClick={() => setCart(cart.filter((x) => x.variantId !== l.variantId))} className="px-2 text-muted hover:text-danger">✕</button>
              </div>
            ))}
            <div className="flex items-center justify-between bg-surface-2 px-5 py-4"><span className="text-lg text-ink-2">Total</span><span className="tabular text-2xl font-semibold text-ink">{pares(total)}</span></div>
          </div>
          <button type="button" onClick={() => setStep('product')} className="mt-3 w-full rounded-2xl border border-dashed border-line py-4 text-ink-2 hover:border-gold/50">+ Agregar otro producto</button>
          <textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Nota (opcional): p. ej. para la vitrina del sábado" rows={2}
            className="mt-6 w-full rounded-2xl border border-line bg-surface px-4 py-3 text-base outline-none focus:border-gold" />
          {error && <p role="alert" className="mt-4 rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}

          {info.can_send ? (
            <>
              <button type="button" onClick={() => submit(true)} disabled={pending || total === 0 || short.length > 0}
                className="mt-6 w-full rounded-2xl bg-ink py-6 text-xl font-semibold uppercase tracking-wider text-surface shadow-sm transition hover:bg-ink-2 disabled:bg-surface-2 disabled:text-muted">
                {pending ? 'Guardando…' : `Enviar ahora ${pares(total)}`}
              </button>
              <p className="mt-2 text-center text-sm text-muted">Salen de {from.name} y quedan <b>En camino</b>. {to.name} los suma cuando confirme que llegaron.</p>
              <button type="button" onClick={() => submit(false)} disabled={pending || total === 0}
                className="mt-4 w-full rounded-2xl border border-line bg-surface py-4 text-lg text-ink disabled:opacity-50">Solo solicitar (enviar después)</button>
            </>
          ) : (
            <>
              <button type="button" onClick={() => submit(false)} disabled={pending || total === 0}
                className="mt-6 w-full rounded-2xl bg-ink py-6 text-xl font-semibold uppercase tracking-wider text-surface shadow-sm transition hover:bg-ink-2 disabled:bg-surface-2 disabled:text-muted">
                {pending ? 'Guardando…' : `Solicitar ${pares(total)}`}
              </button>
              <p className="mt-2 text-center text-sm text-muted">Operación revisa la solicitud y la envía. Pedir no aparta los pares.</p>
            </>
          )}
          {info.can_send && short.length > 0 && <p className="mt-3 text-center text-sm text-danger">No hay suficientes pares en {from.name} para enviar ahora. Puedes solo solicitar.</p>}
        </div>
      )}

      {step === 'done' && result && (
        <div className="pt-4 text-center">
          <div className="mx-auto flex size-20 items-center justify-center rounded-full bg-success-soft text-success"><IconCheck className="size-10" /></div>
          <h1 className="font-display mt-6 text-5xl text-ink">{result.status === 'in_transit' ? 'Enviado: va en camino' : 'Solicitud registrada'}</h1>
          <p className="mt-3 text-lg text-ink-2">Transferencia {result.number} · {pares(result.totals.requested)} de {result.from.name} a {result.to.name}</p>
          <p className="mt-2 text-muted">{result.status === 'in_transit' ? `${result.to.name} los sumará cuando confirme la recepción.` : 'Todavía no se ha movido ningún par.'}</p>
          <div className="mt-8 grid gap-3 sm:grid-cols-2">
            <Link href={`/transferencias/${result.id}`} className="rounded-2xl bg-ink py-4 text-lg text-surface">Ver transferencia</Link>
            <button type="button" onClick={restart} className="rounded-2xl border border-line bg-surface py-4 text-lg text-ink">Mover otra</button>
          </div>
        </div>
      )}
    </div>
  );
}
