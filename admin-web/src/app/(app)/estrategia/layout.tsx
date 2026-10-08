import { notFound } from 'next/navigation';
import { getBoardMe } from '@/lib/board';

// Strategy & Board 🔒 (SB0). Only the allowlisted board members (Carolina, Mario — by auth id, plus owner role) get past
// f360_board_me; everyone else gets a plain 404 (the module does not admit it exists). Every page below re-checks through
// its own f360_board_* RPCs, so hiding the menu is never the security.
export const dynamic = 'force-dynamic';

export default async function EstrategiaLayout({ children }: { children: React.ReactNode }) {
  const me = await getBoardMe();
  if (!me.ok) notFound();
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-2 rounded-2xl border border-line bg-surface px-5 py-3 text-sm text-ink-2">
        <span><span className="font-semibold text-ink">Strategy &amp; Board 🔒</span> · solo consejo · {me.me.display_name}</span>
        <span className="text-xs text-muted">Cada acceso queda registrado</span>
      </div>
      {children}
    </div>
  );
}
