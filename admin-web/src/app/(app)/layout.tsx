import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { redirect } from 'next/navigation';
import { getMe, getSyncBadge } from '@/lib/f360';
import { financeAccess } from '@/lib/intel';
import { weeklyMe } from '@/lib/weekly';
import { signOut } from '../login/actions';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const weekly = await weeklyMe();
  if (weekly.ok && !weekly.team) redirect('/pendientes'); // the agency: only its weekly card, nothing else
  const me = await getMe(); // no Fuxia 360 role → signed out with a clear message
  // The contadora (viewer + finance preparer, I2) only has Cierre contable: every other admin page sends her there, server-side.
  // /cierre-contable lives in its own route group, so this layout never wraps it.
  if ((await financeAccess(me.role)) !== 'none') redirect('/cierre-contable');
  const alerts = await getSyncBadge().catch(() => 0);
  const board = await boardNavVisible().catch(() => false); // menu hint only; /estrategia re-checks in the database
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} signOut={signOut}>
      {children}
    </Shell>
  );
}
