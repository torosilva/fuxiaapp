import { notFound } from 'next/navigation';
import { boardAccessState, getBoardMe } from '@/lib/board';
import { BoardMfa } from '../estrategia/BoardMfa';

// Inteligencia 🔒 — AI Business Analyst. Same gate as Strategy & Board: allowlisted board members with a second factor.
// The analyst itself reads every number through the board-gated metrics layer with the user's session, so hiding the page is
// never the security.
export const dynamic = 'force-dynamic';

export default async function InteligenciaLayout({ children }: { children: React.ReactNode }) {
  const me = await getBoardMe();
  if (!me.ok) {
    if ((await boardAccessState()) === 'mfa_required') return <BoardMfa />;
    notFound();
  }
  return <div className="flex flex-col gap-6">{children}</div>;
}
