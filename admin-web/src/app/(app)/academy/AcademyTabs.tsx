'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

// Academy's own bottom bar on the phone (the general Fuxia 360 bar is hidden inside /academy).
const TABS = [{ href: '/academy', label: 'Inicio' }, { href: '/academy/fichas', label: 'Fichas' }, { href: '/', label: 'Fuxia 360' }];
export function AcademyTabs() {
  const path = usePathname();
  const active = (h: string) => (h === '/academy' ? path === '/academy' || path.startsWith('/academy/clase') : h !== '/' && path.startsWith(h));
  return (
    <nav className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-3 border-t border-line bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden" data-testid="academy-tabs">
      {TABS.map((t) => (
        <Link key={t.href} href={t.href} className={`py-4 text-center text-sm ${active(t.href) ? 'font-semibold text-gold-strong' : 'text-muted'}`}>{t.label}</Link>
      ))}
    </nav>
  );
}
