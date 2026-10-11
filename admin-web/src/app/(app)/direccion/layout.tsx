import { notFound } from 'next/navigation';
import { boardAccessState, getBoardMe } from '@/lib/board';
import { BoardMfa } from '../estrategia/BoardMfa';
import { DireccionNav } from './DireccionNav';

// Dirección 🔒 (I2 · CEO Cockpit). Same rule as Strategy & Board: only the board members (Mario, Carolina) with the second
// factor; anyone else gets a plain 404. Every page re-checks through its own RPC (f360_intel_cockpit, f360_board_budgets…),
// so this layout is never the security.
export const dynamic = 'force-dynamic';

export default async function DireccionLayout({ children }: { children: React.ReactNode }) {
  const me = await getBoardMe();
  if (!me.ok) {
    if ((await boardAccessState()) === 'mfa_required') return <BoardMfa area="Dirección 🔒" next="/direccion" />;
    notFound();
  }
  return (
    <div className="flex min-w-0 flex-col gap-5">
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-line bg-surface px-4 py-3 text-sm text-ink-2">
        <span><span className="font-semibold text-ink">Dirección 🔒</span> · solo consejo · {me.me.display_name}</span>
        <span className="text-xs text-muted">Cada acceso queda registrado · verificación en dos pasos activa</span>
      </div>
      <DireccionNav />
      {children}
    </div>
  );
}
