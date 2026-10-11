import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { getMe, getSyncBadge } from '@/lib/f360';
import { financeState } from '@/lib/intel';
import { intelEnabled } from '@/lib/feature';
import { notFound } from 'next/navigation';
import { signOut } from '../login/actions';

// Cierre contable (I2) has its own route group so the contadora never passes through the main admin layout (which redirects
// her here). She gets a Shell with ONLY this entry; board members get their normal menu. Access is decided in the database
// (f360_close_prep_context); this layout only chooses the menu.
export const dynamic = 'force-dynamic';

export default async function ContabilidadLayout({ children }: { children: React.ReactNode }) {
  if (!intelEnabled()) notFound();   // D0: hidden in production until I5
  const fs = await financeState();
  if (fs.preparadora) {   // the contadora has no F360 role: never call getMe (it would sign her out)
    return (
      <Shell name={fs.nombre ?? 'Contabilidad'} role="viewer" env={process.env.NEXT_PUBLIC_F360_ENV} alerts={0} board={false} finance onlyFinance signOut={signOut}>
        {children}
      </Shell>
    );
  }
  const me = await getMe();
  const board = await boardNavVisible().catch(() => false);
  const alerts = await getSyncBadge().catch(() => 0);
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} finance={false} onlyFinance={false} signOut={signOut}>
      {children}
    </Shell>
  );
}
