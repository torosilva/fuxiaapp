import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { getMe, getSyncBadge } from '@/lib/f360';
import { financeAccess } from '@/lib/intel';
import { signOut } from '../login/actions';

// Cierre contable (I2) has its own route group so the contadora never passes through the main admin layout (which redirects
// her here). She gets a Shell with ONLY this entry; board members get their normal menu. Access is decided in the database
// (f360_close_prep_context); this layout only chooses the menu.
export const dynamic = 'force-dynamic';

export default async function ContabilidadLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe();
  const [finance, board] = await Promise.all([financeAccess(me.role), boardNavVisible().catch(() => false)]);
  const onlyFinance = finance !== 'none';
  const alerts = onlyFinance ? 0 : await getSyncBadge().catch(() => 0);
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} finance={onlyFinance} onlyFinance={onlyFinance} signOut={signOut}>
      {children}
    </Shell>
  );
}
