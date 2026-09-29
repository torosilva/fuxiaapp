import { Shell } from '@/components/Shell';
import { getMe, getSyncBadge } from '@/lib/f360';
import { signOut } from '../login/actions';

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const me = await getMe(); // no Fuxia 360 role → signed out with a clear message
  const alerts = await getSyncBadge().catch(() => 0);
  return (
    <Shell name={me.display_name} role={me.role} env={process.env.NEXT_PUBLIC_F360_ENV} alerts={alerts} signOut={signOut}>
      {children}
    </Shell>
  );
}
