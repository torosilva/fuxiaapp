'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';

const TABS = [
  { href: '/direccion', label: 'Tablero' },
  { href: '/direccion/presupuesto', label: 'Presupuesto y metas' },
  { href: '/direccion/tipo-de-cambio', label: 'Tipo de cambio' },
  { href: '/cierre-contable', label: 'Cierre contable' },
];

export function DireccionNav() {
  const path = usePathname();
  return (
    <nav className="flex flex-wrap gap-2 text-sm">
      {TABS.map((t) => {
        const on = t.href === '/direccion' ? path === t.href : path.startsWith(t.href);
        return <Link key={t.href} href={t.href} aria-current={on ? 'page' : undefined}
          className={`rounded-full px-3 py-1.5 ${on ? 'bg-ink text-surface' : 'border border-line text-ink-2 hover:border-gold/40'}`}>{t.label}</Link>;
      })}
    </nav>
  );
}
