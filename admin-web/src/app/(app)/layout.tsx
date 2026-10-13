import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { academyEnabled, academyMe } from '@/lib/academy';
import { redirect } from 'next/navigation';
import { getMe, getSyncBadge } from '@/lib/f360';
import { financeAccess } from '@/lib/intel';
import { intelEnabled } from '@/lib/feature';
import { weeklyMe } from '@/lib/weekly';
import { signOut } from '../login/actions';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  // The contadora (finance preparer WITHOUT an F360 role, 0700) only has Cierre contable: sent there server-side before anything
  // that needs a role. /cierre-contable lives in its own route group, so this layout never wraps it.
  if (intelEnabled() && (await financeAccess()) !== 'none') redirect('/cierre-contable');
  const weekly = await weeklyMe();
  if (weekly.ok && !weekly.team) redirect('/pendientes'); // the agency: only its weekly card, nothing else
  const me = await getMe(); // no Fuxia 360 role → signed out with a clear message
  const alerts = await getSyncBadge().catch(() => 0);
  const board = await boardNavVisible().catch(() => false); // menu hint only; /estrategia re-checks in the database
  // Academy (A1, staging only): menu hint only; every Academy RPC re-checks in the database.
  const am = academyEnabled() ? await academyMe().catch(() => null) : null;
  const academy = !!am?.ok && (am.sales !== 'none' || am.editor || am.approver);
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} academy={academy} signOut={signOut}>
      {children}
    </Shell>
  );
}
