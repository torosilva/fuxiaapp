import { imageUrl } from '@/lib/format';

// Product photography first. Without a photo: a quiet ballet-flat illustration + initial (no fake photo).
export function ProductImage({ path, name, className = '' }: { path: string | null | undefined; name: string; className?: string }) {
  const url = imageUrl(path);
  if (url) {
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt={name} className={`h-full w-full object-cover ${className}`} />;
  }
  return (
    <div className={`relative flex h-full w-full items-center justify-center bg-gradient-to-br from-surface-2 to-gold-soft ${className}`} aria-label={name}>
      <svg viewBox="0 0 120 60" className="w-3/5 text-gold/70" fill="none" stroke="currentColor" strokeWidth="1.4" aria-hidden>
        <path d="M8 42c0-7 5-11 12-11h18c9 0 15-9 21-14 2-2 6-2 8 0l6 5c3 3 7 5 12 5l14 1c4 0 7 3 7 7v8H8Z" />
        <path d="M8 42v6h98v-6" />
        <path d="M60 22c3 2 6 6 6 10" opacity=".6" />
      </svg>
      <span className="font-display absolute bottom-2 right-3 text-2xl text-gold/60">{name.slice(0, 1).toUpperCase()}</span>
    </div>
  );
}

export function ColorDot({ hex, className = 'size-4' }: { hex: string | null | undefined; className?: string }) {
  return <span className={`inline-block shrink-0 rounded-full border border-black/10 ${className}`} style={{ background: hex ?? 'linear-gradient(135deg,#e6dfd4,#c9bfae)' }} />;
}
