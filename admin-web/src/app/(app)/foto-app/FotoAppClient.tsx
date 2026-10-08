'use client';
import { useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { IconCamera, IconCheck } from '@/components/icons';
import { fecha, imageUrl } from '@/lib/format';
import { createClient } from '@/lib/supabase/browser';
import { setAppPhotoAction } from './actions';

type Entry = { path: string | null; product: string | null; by: string; at: string };
export type WelcomeAdmin = { current: Entry | null; history: Entry[]; catalog: { product_id: string; product: string; path: string }[] };

// Phone-shaped preview: the photo with the same dark veil and logo the app draws over it.
function Preview({ path }: { path: string | null }) {
  const src = imageUrl(path);
  return (
    <div className="relative mx-auto aspect-[9/19] w-56 overflow-hidden rounded-[2.2rem] border-[6px] border-ink bg-[#0D0D0D] shadow-lg">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {src && <img src={src} alt="" className="absolute inset-0 h-full w-full object-cover" />}
      <div className="absolute inset-0" style={{ background: 'linear-gradient(rgba(13,13,13,.5), rgba(13,13,13,.45) 35%, rgba(13,13,13,.75) 70%, rgba(13,13,13,.95))' }} />
      <div className="absolute inset-x-0 top-[38%] text-center">
        <p className="font-display text-2xl tracking-[0.2em] text-[#CD7F32]">FUXIA</p>
        <p className="mt-2 text-[8px] tracking-[0.4em] text-[#CD7F32]/60">UN PAR A LA VEZ</p>
      </div>
      <div className="absolute inset-x-5 bottom-8 rounded-full bg-[#CD7F32] py-2 text-center text-[9px] font-bold tracking-[0.2em] text-[#0D0D0D]">CREAR CUENTA</div>
      {!src && <p className="absolute inset-x-0 top-6 text-center text-[10px] text-white/60">Foto de la tienda (Destacado / más nuevo)</p>}
    </div>
  );
}

export function FotoAppClient({ data, canEdit }: { data: WelcomeAdmin; canEdit: boolean }) {
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const current = data.current?.path ?? null;

  const choose = (path: string | null, productId: string | null, label: string) => start(async () => {
    setError(null); setDone(null);
    const r = await setAppPhotoAction(path, productId);
    if (!r.ok) { setError(r.error); return; }
    setDone(label);
    router.refresh();
  });

  const upload = (files: FileList | null) => {
    const f = files?.[0];
    if (!f) return;
    start(async () => {
      setError(null); setDone(null);
      const ext = (f.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
      const path = `f360/app/${crypto.randomUUID()}.${ext}`;
      const { error: e } = await createClient().storage.from('product-images').upload(path, f, { contentType: f.type || 'image/jpeg' });
      if (fileRef.current) fileRef.current.value = '';
      if (e) { setError(`No se pudo subir “${f.name}”.`); return; }
      const r = await setAppPhotoAction(path, null);
      if (!r.ok) { setError(r.error); return; }
      setDone('Foto nueva');
      router.refresh();
    });
  };

  return (
    <div className="mt-8 grid gap-8 lg:grid-cols-[auto_1fr]">
      <section className="rounded-3xl border border-line bg-surface p-6" data-testid="current">
        <Preview path={current} />
        <p className="mt-4 text-center text-ink">{current ? (data.current?.product ?? 'Foto subida') : 'Foto de la tienda'}</p>
        {data.current && <p className="text-center text-sm text-muted">{data.current.by} · {fecha(data.current.at)}</p>}
        {canEdit && current && (
          <button type="button" disabled={pending} onClick={() => choose(null, null, 'Foto de la tienda')}
            className="mx-auto mt-3 block text-sm text-muted underline decoration-line underline-offset-4">Volver a la foto de la tienda</button>
        )}
      </section>

      <section>
        {canEdit && (
          <button type="button" disabled={pending} onClick={() => fileRef.current?.click()}
            className="flex items-center gap-2 rounded-2xl bg-ink px-5 py-3 text-surface disabled:opacity-60">
            <IconCamera className="size-5" />{pending ? 'Guardando…' : 'Subir una foto'}
          </button>
        )}
        <input ref={fileRef} type="file" accept="image/*" className="hidden" aria-label="Subir foto de la app" onChange={(e) => upload(e.target.files)} />
        <p className="mt-2 text-sm text-muted">Mejor vertical (como pantalla de celular). Lo importante va al centro: abajo quedan los botones.</p>
        {error && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-4 py-3 text-sm text-danger">{error}</p>}
        {done && !error && <p role="status" className="mt-3 flex items-center gap-2 rounded-xl bg-success-soft px-4 py-3 text-sm text-ink"><IconCheck className="size-4" />Listo: {done}. Las clientas la ven la próxima vez que abran la app.</p>}

        <h2 className="mt-8 font-display text-3xl text-ink">O elige una del catálogo</h2>
        <p className="mt-1 text-sm text-muted">Los modelos más nuevos primero.</p>
        <div className="mt-4 grid grid-cols-3 gap-3 sm:grid-cols-4 xl:grid-cols-6">
          {data.catalog.map((c) => (
            <button key={c.path} type="button" disabled={!canEdit || pending} onClick={() => choose(c.path, c.product_id, c.product)}
              className={`group relative aspect-[3/4] overflow-hidden rounded-2xl border ${c.path === current ? 'border-ink ring-2 ring-gold' : 'border-line hover:border-gold/50'} disabled:cursor-default`}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={imageUrl(c.path) ?? ''} alt={c.product} className="h-full w-full object-cover" loading="lazy" />
              <span className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-ink/80 to-transparent px-2 pb-1.5 pt-4 text-left text-xs text-surface">{c.product}</span>
              {c.path === current && <span className="absolute left-2 top-2 rounded-full bg-ink/80 px-2 py-0.5 text-[11px] text-surface">En la app</span>}
            </button>
          ))}
        </div>

        {data.history.length > 0 && (
          <details className="mt-8 text-sm text-ink-2">
            <summary className="cursor-pointer text-muted">Cambios anteriores</summary>
            <ul className="mt-2 space-y-1">
              {data.history.map((h, i) => <li key={i}>{fecha(h.at)} · {h.by} · {h.path ? (h.product ?? 'foto subida') : 'volvió a la foto de la tienda'}</li>)}
            </ul>
          </details>
        )}
      </section>
    </div>
  );
}
