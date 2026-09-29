'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { Category, Product } from '@/lib/f360';
import { precio } from '@/lib/format';
import { updateProductAction } from '../../actions';

const field = 'mt-2 w-full rounded-xl border border-line bg-bg px-4 py-3 text-base outline-none focus:border-gold';

// "Información para la tienda": price, category, description. Progressive disclosure: sale price and
// short description stay hidden until asked for; when complete, it collapses to a summary.
export function ProductInfoForm({ product, categories, canEdit }: { product: Product; categories: Category[]; canEdit: boolean }) {
  const router = useRouter();
  const complete = product.regular_price != null && !!product.category_key && !!product.description;
  const [editing, setEditing] = useState(!complete && canEdit);
  const [price, setPrice] = useState(product.regular_price?.toString() ?? '');
  const [showSale, setShowSale] = useState(product.sale_price != null);
  const [sale, setSale] = useState(product.sale_price?.toString() ?? '');
  const [category, setCategory] = useState(product.category_key ?? '');
  const [description, setDescription] = useState(product.description ?? '');
  const [showShort, setShowShort] = useState(!!product.short_description);
  const [short, setShort] = useState(product.short_description ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const num = (s: string) => (s.trim() === '' ? null : Number(s.replace(/[^\d.]/g, '')));

  const save = () => start(async () => {
    setError(null);
    const r = await updateProductAction(product.id, {
      regular_price: num(price), sale_price: showSale ? num(sale) : null, category_key: category || null,
      description: description || null, short_description: showShort ? short || null : null,
    });
    if (!r.ok) { setError(r.error); return; }
    setEditing(false);
    router.refresh();
  });

  if (!editing) {
    return (
      <section id="info" className="mt-12 scroll-mt-6">
        <div className="flex items-baseline justify-between">
          <h2 className="font-display text-3xl text-ink">Información para la tienda</h2>
          {canEdit && <button type="button" onClick={() => setEditing(true)} className="text-sm text-gold-strong hover:underline">Editar</button>}
        </div>
        <div className="mt-4 grid gap-4 rounded-3xl border border-line bg-surface p-5 md:grid-cols-[200px_1fr]">
          <div>
            <p className="text-sm text-muted">Precio</p>
            {product.sale_price != null ? (
              <p className="tabular text-2xl text-ink"><span className="font-semibold">{precio(product.sale_price)}</span> <span className="text-base text-muted line-through">{precio(product.regular_price)}</span></p>
            ) : <p className="tabular text-2xl font-semibold text-ink">{precio(product.regular_price) || '—'}</p>}
            <p className="mt-3 text-sm text-muted">Categoría</p>
            <p className="text-ink">{product.category ?? '—'}</p>
          </div>
          <div>
            <p className="text-sm text-muted">Descripción</p>
            <p className="whitespace-pre-line text-ink-2">{product.description || '—'}</p>
            {product.short_description && <><p className="mt-3 text-sm text-muted">Descripción corta</p><p className="text-ink-2">{product.short_description}</p></>}
          </div>
        </div>
      </section>
    );
  }

  return (
    <section id="info" className="mt-12 scroll-mt-6">
      <h2 className="font-display text-3xl text-ink">Información para la tienda</h2>
      <div className="mt-4 space-y-5 rounded-3xl border border-line bg-surface p-5 md:p-7">
        <div className="grid gap-5 md:grid-cols-2">
          <label className="block text-ink-2">Precio (MXN)
            <input inputMode="decimal" value={price} onChange={(e) => setPrice(e.target.value)} placeholder="Ej. 2800" className={`${field} tabular text-xl`} />
          </label>
          {showSale ? (
            <label className="block text-ink-2">Precio de oferta
              <div className="flex gap-2">
                <input inputMode="decimal" value={sale} onChange={(e) => setSale(e.target.value)} placeholder="Ej. 2400" className={`${field} tabular text-xl`} />
                <button type="button" onClick={() => { setShowSale(false); setSale(''); }} className="mt-2 px-2 text-sm text-muted">Quitar</button>
              </div>
            </label>
          ) : (
            <button type="button" onClick={() => setShowSale(true)} className="self-end pb-3 text-left text-sm text-gold-strong hover:underline">+ Agregar precio de oferta</button>
          )}
        </div>

        <div>
          <p className="text-ink-2">Categoría</p>
          <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
            {categories.map((c) => (
              <button key={c.key} type="button" onClick={() => setCategory(c.key)} aria-pressed={category === c.key}
                className={`rounded-xl border px-3 py-3 text-[15px] transition ${category === c.key ? 'border-ink bg-ink text-surface' : 'border-line bg-bg text-ink-2 hover:border-gold/50'}`}>{c.name}</button>
            ))}
          </div>
        </div>

        <label className="block text-ink-2">Descripción
          <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={4}
            placeholder="Cómo es, de qué está hecho, cómo se siente." className={field} />
        </label>
        {showShort ? (
          <label className="block text-ink-2">Descripción corta <span className="text-sm text-muted">(aparece junto al precio)</span>
            <textarea value={short} onChange={(e) => setShort(e.target.value)} rows={2} className={field} />
          </label>
        ) : (
          <button type="button" onClick={() => setShowShort(true)} className="text-sm text-gold-strong hover:underline">+ Agregar descripción corta</button>
        )}

        {error && <p role="alert" className="rounded-xl bg-danger-soft px-4 py-3 text-danger">{error}</p>}
        <div className="flex gap-3">
          <button type="button" onClick={save} disabled={pending} className="rounded-2xl bg-ink px-6 py-3.5 text-surface disabled:opacity-60">{pending ? 'Guardando…' : 'Guardar'}</button>
          {complete && <button type="button" onClick={() => setEditing(false)} className="rounded-2xl px-4 text-muted">Cancelar</button>}
        </div>
      </div>
    </section>
  );
}
