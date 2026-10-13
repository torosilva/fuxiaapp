import Link from 'next/link';
import { notFound } from 'next/navigation';
import { academyFichas } from '@/lib/academy';
import { Ficha } from '../Card';

// Product cards of the published Sales courses — the frozen, Carolina-validated snapshot.
export default async function Fichas() {
  const r = await academyFichas();
  if (!r.ok) notFound();
  return (
    <>
      <Link href="/academy" className="text-xs text-muted">← Fuxia Academy</Link>
      <h1 className="font-display text-4xl text-ink">Fichas</h1>
      <p className="text-sm text-muted">Solo lo validado por Carolina. Lo que falta dice “pendiente”: no lo inventes, confírmalo.</p>
      {r.fichas.map((p) => <section key={p.code} className="rounded-3xl border border-line bg-surface p-5"><Ficha p={p} compact /></section>)}
    </>
  );
}
