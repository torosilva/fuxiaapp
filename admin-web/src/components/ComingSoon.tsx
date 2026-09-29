export function ComingSoon({ title, text }: { title: string; text: string }) {
  return (
    <div className="mx-auto max-w-xl py-16 text-center">
      <p className="text-xs uppercase tracking-[0.25em] text-gold">Próximamente</p>
      <h1 className="font-display mt-3 text-5xl text-ink">{title}</h1>
      <p className="mt-4 text-lg text-ink-2">{text}</p>
    </div>
  );
}
