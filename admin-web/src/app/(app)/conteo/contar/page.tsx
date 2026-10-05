import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getMe, getOpeningEasySheet, getOpeningState } from '@/lib/f360';
import { EasyCount } from './EasyCount';

// Conteo fácil (Mario 2026-10-05): search a model, tap a color, write the pairs per size; every change is saved by
// f360_opening_record (one count, logged). Freeze / reconcile / approve stay on /conteo.
export default async function Contar() {
  if (!canWrite((await getMe()).role)) redirect('/');
  const state = await getOpeningState();
  const c = state.count;
  if (!c || !['preliminar', 'congelado'].includes(c.status)) {
    return (
      <div className="mx-auto max-w-xl">
        <Link href="/conteo" className="text-sm text-muted">← Conteo de apertura</Link>
        <h1 className="font-display mt-2 text-5xl text-ink">Contar</h1>
        <p className="mt-4 rounded-2xl border border-line bg-surface p-5 text-ink-2">No hay un conteo abierto. Una dueña lo inicia en “Conteo de apertura”.</p>
      </div>
    );
  }
  const sheet = await getOpeningEasySheet(c.id);
  return <EasyCount sheet={sheet} />;
}
