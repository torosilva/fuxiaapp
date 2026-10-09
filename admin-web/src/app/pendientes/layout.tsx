import { redirect } from 'next/navigation';
import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { weeklyMe } from '@/lib/weekly';
import { createClient } from '@/lib/supabase/server';
import { signOut } from '../login/actions';

// Pendientes de la semana. OUTSIDE the (app) group on purpose: the agency has NO Fuxia 360 role, so it can only ever reach this
// page (every other screen and RPC refuses it). Team members (owner/operator) see it inside the usual menu.
export const dynamic = 'force-dynamic';

export default async function PendientesLayout({ children }: { children: React.ReactNode }) {
  const me = await weeklyMe();
  if (!me.ok) redirect('/');
  if (me.team) {
    const supabase = await createClient();
    const { data } = await supabase.rpc('f360_me');
    const board = await boardNavVisible().catch(() => false);
    if (data) return <Shell name={data.display_name} role={data.role} env={process.env.NEXT_PUBLIC_F360_ENV} board={board} signOut={signOut}>{children}</Shell>;
  }
  return (
    <div className="min-h-dvh bg-bg">
      <header className="flex items-center justify-between border-b border-line px-5 py-4">
        <div><span className="font-display text-2xl text-ink">Fuxia 360</span> <span className="text-sm text-muted">· Pendientes de la semana</span></div>
        <form action={signOut}><button className="text-sm text-ink-2 hover:text-ink">Salir</button></form>
      </header>
      <main className="mx-auto max-w-4xl px-4 py-8">{children}</main>
    </div>
  );
}
