import { Shell } from '@/components/Shell';
import { boardNavVisible } from '@/lib/board';
import { getMe, getSyncBadge } from '@/lib/f360';
import { signOut } from '../login/actions';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe(); // no Fuxia 360 role → signed out with a clear message
  const alerts = await getSyncBadge().catch(() => 0);
  const board = await boardNavVisible().catch(() => false); // menu hint only; /estrategia re-checks in the database
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} board={board} signOut={signOut}>
      {children}
    </Shell>
  );
}
