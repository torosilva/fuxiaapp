'use client';
import Link from 'next/link';
import { useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { ColorDot } from '@/components/ProductImage';
import { IconCamera, IconCheck, IconPlus, IconX } from '@/components/icons';
import type { Color, Product } from '@/lib/f360';
import { imageUrl, SWATCHES } from '@/lib/format';
import { createClient } from '@/lib/supabase/browser';
import { addColorAction, addMediaAction, removeMediaAction, setPrimaryMediaAction } from '../../actions';

// Photos per color + add a color later (the model is never recreated).
export function ColorPhotos({ product, color, canEdit }: { product: Product; color: Color; canEdit: boolean }) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [adding, setAdding] = useState(false);
  const [newColor, setNewColor] = useState('');

  const upload = (files: FileList | null) => {
    if (!files?.length) return;
    setError(null);
    start(async () => {
      const supabase = createClient();
      const paths: string[] = [];
      for (const f of Array.from(files)) {
        const ext = (f.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
        const path = `f360/${product.code}/${color.code}/${crypto.randomUUID()}.${ext}`;
        const { error: e } = await supabase.storage.from('product-images').upload(path, f, { contentType: f.type || 'image/jpeg' });
        if (e) { setError(`No se pudo subir “${f.name}”.`); continue; }
        paths.push(path);
      }
      if (paths.length) {
        const r = await addMediaAction(product.id, color.id, paths);
        if (!r.ok) setError(r.error);
      }
      if (fileRef.current) fileRef.current.value = '';
      router.refresh();
    });
  };

  const run = (fn: () => Promise<{ ok: boolean; error?: string }>) => start(async () => {
    setError(null);
    const r = await fn();
    if (!r.ok) setError(r.error ?? 'No se pudo guardar.');
    router.refresh();
  });

  const addColor = (name: string, hex: string | null) => run(async () => {
    const r = await addColorAction(product.id, name, hex);
    if (r.ok) {
      setAdding(false); setNewColor('');
      const created = r.data.colors.find((c) => c.name.toLowerCase() === name.trim().toLowerCase());
      if (created) router.replace(`/productos/${product.id}?color=${created.id}#fotos`, { scroll: false });
    }
    return r;
  });

  return (
    <section id="fotos" className="mt-12 scroll-mt-6">
      <h2 className="font-display text-3xl text-ink">Colores y fotos</h2>
      <div className="mt-4 flex flex-wrap items-center gap-2">
        {product.colors.map((c) => (
          <Link key={c.id} href={`/productos/${product.id}?color=${c.id}#fotos`} scroll={false}
            className={`flex items-center gap-2 rounded-full border px-4 py-2.5 text-[15px] transition ${c.id === color.id ? 'border-ink bg-ink text-surface' : 'border-line bg-surface text-ink-2 hover:border-gold/50'}`}>
            <ColorDot hex={c.hex} className="size-4 ring-1 ring-white/60" />{c.name}
            <span className={`text-xs ${c.id === color.id ? 'text-surface/60' : 'text-muted'}`}>{c.media.length} {c.media.length === 1 ? 'foto' : 'fotos'}</span>
          </Link>
        ))}
        {canEdit && !adding && (
          <button type="button" onClick={() => setAdding(true)} className="flex items-center gap-1.5 rounded-full border border-dashed border-line px-4 py-2.5 text-[15px] text-ink-2 hover:border-gold/50">
            <IconPlus className="size-4" />Agregar color
          </button>
        )}
      </div>

      {adding && (
        <div className="mt-4 rounded-3xl border border-line bg-surface p-5">
          <p className="text-ink-2">Nuevo color para {product.name}. Se crean sus tallas ({product.sizes.join(', ')}) automáticamente.</p>
          <div className="mt-3 flex flex-wrap gap-2">
            {SWATCHES.filter((s) => !product.colors.some((c) => c.name.toLowerCase() === s.name.toLowerCase())).map((s) => (
              <button key={s.name} type="button" disabled={pending} onClick={() => addColor(s.name, s.hex)}
                className="flex items-center gap-2 rounded-full border border-line bg-bg px-4 py-2.5 text-[15px] text-ink-2 hover:border-gold/50">
                <ColorDot hex={s.hex} />{s.name}
              </button>
            ))}
          </div>
          <div className="mt-3 flex gap-2">
            <input value={newColor} onChange={(e) => setNewColor(e.target.value)} placeholder="Otro color"
              className="flex-1 rounded-xl border border-line bg-bg px-4 py-3 outline-none focus:border-gold" />
            <button type="button" disabled={pending || !newColor.trim()} onClick={() => addColor(newColor, null)} className="rounded-xl bg-ink px-4 text-surface disabled:opacity-40">Agregar</button>
            <button type="button" onClick={() => setAdding(false)} className="rounded-xl px-3 text-muted">Cancelar</button>
          </div>
        </div>
      )}

      <div className="mt-5 rounded-3xl border border-line bg-surface p-5">
        <div className="flex items-center justify-between">
          <p className="flex items-center gap-2 text-lg text-ink"><ColorDot hex={color.hex} />{color.name}</p>
          {color.media.length === 0 && <span className="rounded-full bg-gold-soft px-3 py-1 text-xs text-ink-2">Faltan fotos</span>}
        </div>
        <div className="mt-4 grid grid-cols-3 gap-3 sm:grid-cols-4 lg:grid-cols-6">
          {color.media.map((m, i) => (
            <div key={m.id} className="group relative aspect-square overflow-hidden rounded-2xl border border-line">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={imageUrl(m.path) ?? ''} alt={`${product.name} ${color.name}`} className="h-full w-full object-cover" />
              {i === 0 && <span className="absolute left-2 top-2 rounded-full bg-ink/80 px-2 py-0.5 text-[11px] text-surface">Principal</span>}
              {canEdit && (
                <div className="absolute inset-x-0 bottom-0 flex justify-between gap-1 bg-gradient-to-t from-ink/70 to-transparent p-2 opacity-100 md:opacity-0 md:group-hover:opacity-100">
                  {i !== 0 ? <button type="button" disabled={pending} onClick={() => run(() => setPrimaryMediaAction(product.id, m.id))} className="rounded-full bg-surface/90 px-2 py-1 text-[11px] text-ink">Principal</button> : <span />}
                  <button type="button" aria-label="Quitar foto" disabled={pending} onClick={() => run(() => removeMediaAction(product.id, m.id))} className="rounded-full bg-surface/90 p-1 text-ink"><IconX className="size-4" /></button>
                </div>
              )}
            </div>
          ))}
          {canEdit && (
            <button type="button" disabled={pending} onClick={() => fileRef.current?.click()}
              className="flex aspect-square flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-line text-sm text-ink-2 hover:border-gold/50 disabled:opacity-50">
              <IconCamera className="size-6" />{pending ? 'Subiendo…' : 'Agregar fotos'}
            </button>
          )}
        </div>
        <input ref={fileRef} type="file" accept="image/*" multiple className="hidden" aria-label={`Fotos de ${color.name}`} onChange={(e) => upload(e.target.files)} />
        {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
        {!error && pending && <p className="mt-3 flex items-center gap-2 text-sm text-muted"><IconCheck className="size-4" />Guardando…</p>}
      </div>
    </section>
  );
}
