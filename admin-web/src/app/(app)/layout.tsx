import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { redirect } from 'next/navigation';
import { getMe, getSyncBadge } from '@/lib/f360';
import { weeklyMe } from '@/lib/weekly';
import { signOut } from '../login/actions';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const weekly = await weeklyMe();
  if (weekly.ok && !weekly.team) redirect('/pendientes'); // the agency: only its weekly card, nothing else
  const me = await getMe(); // no Fuxia 360 role → signed out with a clear message
  const alerts = await getSyncBadge().catch(() => 0);
  const board = await boardNavVisible().catch(() => false); // menu hint only; /estrategia re-checks in the database
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} signOut={signOut}>
      {children}
    </Shell>
  );
}
