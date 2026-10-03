'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { IconBag, IconBell, IconBoxes, IconCheck, IconGrowth, IconHome, IconLink, IconLogout, IconMore, IconMove, IconReceipt, IconScissors, IconShoe, IconUsers } from './icons';

const NAV = [
  { href: '/', label: 'Inicio', icon: IconHome, live: true },
  { href: '/productos', label: 'Productos', icon: IconShoe, live: true },
  { href: '/inventario', label: 'Inventario', icon: IconBoxes, live: true },
  { href: '/transferencias', label: 'Transferencias', icon: IconMove, live: true },
  { href: '/ventas', label: 'Ventas', icon: IconReceipt, live: true, admin: true },
  { href: '/pedidos', label: 'Pedidos', icon: IconBag, live: false },
  { href: '/clientes', label: 'Clientes', icon: IconUsers, live: true },
  { href: '/growth', label: 'Growth', icon: IconGrowth, live: true },
  { href: '/homologacion', label: 'Homologación', icon: IconLink, live: true, admin: true },
  { href: '/conteo', label: 'Conteo de apertura', icon: IconCheck, live: true, admin: true },
  { href: '/tiendas', label: 'Tiendas', icon: IconBoxes, live: true, admin: true },
  { href: '/avisos', label: 'Avisos', icon: IconBell, live: true },
  { href: '/produccion', label: 'Producción', icon: IconScissors, live: false },
];

const isActive = (path: string, href: string) => (href === '/' ? path === '/' : path.startsWith(href));

export function Shell({ name, role, env, alerts = 0, signOut, children }: { name: string; role: string; env?: string; alerts?: number; signOut: () => Promise<void>; children: React.ReactNode }) {
  const path = usePathname();
  return (
    <div className="min-h-dvh lg:flex">
      {/* Sidebar (tablet landscape / desktop) */}
      <aside className={`sticky hidden w-64 ${env === 'staging' ? 'top-12 h-[calc(100dvh-3rem)]' : 'top-0 h-dvh'} shrink-0 flex-col border-r border-line bg-surface px-5 py-7 lg:flex`}>
        <Link href="/" className="mb-10 block">
          <div className="font-display text-3xl leading-none text-ink">Fuxia <span className="text-gold">360</span></div>
          <div className="mt-1 text-xs uppercase tracking-[0.2em] text-muted">Fuxia Ballerinas</div>
        </Link>
        <nav className="flex flex-1 flex-col gap-1">
          {NAV.filter((n) => !('admin' in n) || role === 'owner' || role === 'operator').map(({ href, label, icon: Icon, live }) => (
            <Link key={href} href={href}
              className={`flex items-center gap-3 rounded-xl px-3 py-3 text-[15px] transition ${isActive(path, href) ? 'bg-gold-soft font-medium text-ink' : 'text-ink-2 hover:bg-surface-2'}`}>
              <Icon className={`size-5 ${isActive(path, href) ? 'text-gold-strong' : 'text-muted'}`} />
              <span className="flex-1">{label}</span>
              {!live && <span className="text-[11px] text-muted">Pronto</span>}
              {href === '/avisos' && alerts > 0 && <span className="rounded-full bg-danger px-2 py-0.5 text-[11px] font-semibold text-surface" data-testid="alerts-badge">{alerts}</span>}
            </Link>
          ))}
        </nav>
        <div className="border-t border-line pt-4">
          <div className="text-sm font-medium text-ink">{name}</div>
          <div className="text-xs text-muted">{role === 'owner' ? 'Dueña' : role === 'operator' ? 'Operación' : role === 'seller' ? 'Vendedora' : 'Consulta'}{env === 'staging' ? ' · Ambiente de pruebas' : ''}</div>
          <form action={signOut}><button className="mt-3 flex items-center gap-2 text-sm text-muted hover:text-ink"><IconLogout className="size-4" />Salir</button></form>
        </div>
      </aside>

      <div className="min-w-0 flex-1 pb-24 lg:pb-0">
        {/* Mobile / portrait tablet header */}
        <header className="flex items-center justify-between px-5 pt-5 lg:hidden">
          <Link href="/" className="font-display text-2xl">Fuxia <span className="text-gold">360</span></Link>
          <form action={signOut}><button aria-label="Salir" className="rounded-full p-2 text-muted"><IconLogout /></button></form>
        </header>
        <main className="mx-auto w-full max-w-6xl px-5 py-6 md:px-8 lg:py-10">{children}</main>
      </div>

      {/* Bottom bar (phone / portrait tablet) */}
      <nav className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-4 border-t border-line bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden">
        {[...NAV.slice(0, 3), { href: '/mas', label: 'Más', icon: IconMore, live: true }].map(({ href, label, icon: Icon }) => (
          <Link key={href} href={href} className={`flex flex-col items-center gap-1 py-3 text-xs ${isActive(path, href) ? 'text-gold-strong' : 'text-muted'}`}>
            <span className="relative"><Icon className="size-6" />{href === '/mas' && alerts > 0 && <span className="absolute -right-1.5 -top-1 size-2.5 rounded-full bg-danger" />}</span>{label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
