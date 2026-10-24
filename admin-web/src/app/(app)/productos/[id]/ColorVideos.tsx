'use client';
import { useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { IconCamera, IconCheck, IconX } from '@/components/icons';
import type { Color, Product, ProductVideo } from '@/lib/f360';
import { imageUrl } from '@/lib/format';
import { createClient } from '@/lib/supabase/browser';
import { addVideoAction, removeVideoAction } from '../../actions';

// Short videos of the selected colour (Mario 2026-10-24: "hagamos que se puedan poner videos"). Max 2 per colour, ≤ 50 MB,
// mp4 / mov / webm. They are uploaded like the photos (same bucket, the colour's folder); the database checks type and size again.
const MAX_BYTES = 50 * 1024 * 1024;
const MAX_PER_COLOR = 2;
const TYPES: Record<string, string> = { mp4: 'video/mp4', m4v: 'video/mp4', mov: 'video/quicktime', webm: 'video/webm' };

export function ColorVideos({ product, color, videos, canEdit }: { product: Product; color: Color; videos: ProductVideo[]; canEdit: boolean }) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const room = MAX_PER_COLOR - videos.length;

  const upload = (file: File | undefined) => {
    if (!file) return;
    setError(null);
    const ext = (file.name.split('.').pop() || '').toLowerCase();
    const type = TYPES[ext] ?? (Object.values(TYPES).includes(file.type) ? file.type : null);
    if (!type) { setError('Ese archivo no es un video. Sube un mp4, mov o webm.'); return; }
    if (file.size > MAX_BYTES) { setError(`El video pesa ${Math.round(file.size / 1048576)} MB. El máximo es 50 MB: súbelo más corto.`); return; }
    start(async () => {
      const path = `f360/${product.code}/${color.code}/video-${crypto.randomUUID()}.${ext === 'm4v' ? 'mp4' : ext}`;
      const { error: e } = await createClient().storage.from('product-images').upload(path, file, { contentType: type });
      if (e) setError(`No se pudo subir “${file.name}”.`);
      else {
        const r = await addVideoAction(product.id, color.id, path);
        if (!r.ok) setError(r.error);
      }
      if (fileRef.current) fileRef.current.value = '';
      router.refresh();
    });
  };

  const remove = (id: string) => start(async () => {
    setError(null);
    const r = await removeVideoAction(product.id, id);
    if (!r.ok) setError(r.error);
    router.refresh();
  });

  if (!canEdit && !videos.length) return null;
  return (
    <section id="videos" className="mt-6 scroll-mt-6 rounded-3xl border border-line bg-surface p-5" data-testid="color-videos">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 className="text-lg text-ink">Videos de {color.name}</h3>
        <span className="text-xs text-muted">Hasta {MAX_PER_COLOR} por color · máx. 50 MB · en la tienda se ven sin sonido y en bucle</span>
      </div>
      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
        {videos.map((v) => (
          <div key={v.id} className="relative overflow-hidden rounded-2xl border border-line bg-ink">
            <video src={imageUrl(v.path) ?? ''} poster={imageUrl(color.media[0]?.path) ?? undefined} muted loop playsInline controls preload="metadata"
              className="aspect-[3/4] w-full object-cover" aria-label={`Video de ${product.name} ${color.name}`} />
            {canEdit && (
              <button type="button" aria-label="Quitar video" disabled={pending} onClick={() => remove(v.id)}
                className="absolute right-2 top-2 rounded-full bg-surface/90 p-1 text-ink"><IconX className="size-4" /></button>
            )}
          </div>
        ))}
        {canEdit && room > 0 && (
          <button type="button" disabled={pending} onClick={() => fileRef.current?.click()}
            className="flex aspect-[3/4] flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-line text-sm text-ink-2 hover:border-gold/50 disabled:opacity-50">
            <IconCamera className="size-6" />{pending ? 'Subiendo…' : 'Agregar video'}
          </button>
        )}
      </div>
      <input ref={fileRef} type="file" accept="video/mp4,video/quicktime,video/webm,.mp4,.mov,.m4v,.webm" className="hidden"
        aria-label={`Video de ${color.name}`} onChange={(e) => upload(e.target.files?.[0])} />
      {canEdit && <p className="mt-3 text-xs text-muted">Con iPhone, si el video no se ve en Android, grábalo en Ajustes → Cámara → Formatos → “Más compatible”.</p>}
      {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
      {!error && pending && <p className="mt-3 flex items-center gap-2 text-sm text-muted"><IconCheck className="size-4" />Guardando…</p>}
    </section>
  );
}
