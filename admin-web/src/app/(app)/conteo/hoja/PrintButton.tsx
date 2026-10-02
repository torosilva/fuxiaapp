'use client';
export function PrintButton() {
  return <button type="button" onClick={() => window.print()} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface">Imprimir</button>;
}
