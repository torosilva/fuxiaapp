'use client';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { IconBag, IconBell, IconBoxes, IconCamera, IconCheck, IconClock, IconGrowth, IconHome, IconLink, IconLogout, IconMore, IconMove, IconReceipt, IconScissors, IconShoe, IconUsers } from './icons';

// Same screens and permissions as before, grouped by what the person is doing (Mario 2026-10-06: "los botones no están agrupados").
const GROUPS = [
  { label: 'Hoy', items: [
    { href: '/', label: 'Inicio', icon: IconHome, live: true },
    { href: '/avisos', label: 'Avisos', icon: IconBell, live: true },
  ] },
  { label: 'Negocio en tiempo real', items: [
    { href: '/tablero', label: 'Centro de control', icon: IconGrowth, live: true, admin: true },
    { href: '/como-funciona', label: 'Mapa del negocio', icon: IconGrowth, live: true, admin: true },
    { href: '/pendientes', label: 'Pendientes de la semana', icon: IconCheck, live: true, admin: true },
  ] },
  { label: 'Vender', items: [
    { href: '/ventas', label: 'Ventas', icon: IconReceipt, live: true, admin: true },
    { href: '/apartados', label: 'Apartados Gold', icon: IconClock, live: true, admin: true },
    { href: '/pedidos', label: 'Pedidos', icon: IconBag, live: false },
    { href: '/produccion', label: 'Producción', icon: IconScissors, live: false },
  ] },
  { label: 'Inventario', items: [
    { href: '/inventario', label: 'Inventario', icon: IconBoxes, live: true },
    { href: '/transferencias', label: 'Transferencias', icon: IconMove, live: true },
    { href: '/productos', label: 'Productos', icon: IconShoe, live: true },
  ] },
  { label: 'Clientas', items: [
    { href: '/clientes', label: 'Clientes', icon: IconUsers, live: true, admin: true },
    { href: '/demanda', label: 'Demanda sin inventario', icon: IconGrowth, live: true, admin: true },
    { href: '/favoritos', label: 'Favoritos · intención', icon: IconGrowth, live: true, admin: true },
  ] },
  { label: 'Crecer', items: [
    { href: '/growth', label: 'Growth', icon: IconGrowth, live: true, admin: true },
  ] },
  { label: 'Dirección', items: [
    { href: '/estrategia', label: 'Strategy & Board 🔒', icon: IconGrowth, live: true, board: true },
  ] },
  { label: 'Configuración', items: [
    { href: '/tiendas', label: 'Tiendas', icon: IconBoxes, live: true, admin: true },
    { href: '/vendedoras', label: 'Vendedoras', icon: IconUsers, live: true, admin: true },
    { href: '/homologacion', label: 'Homologación', icon: IconLink, live: true, admin: true },
    { href: '/conteo', label: 'Conteo de apertura', icon: IconCheck, live: true, admin: true },
    { href: '/foto-app', label: 'Foto de la app', icon: IconCamera, live: true, admin: true },
  ] },
];
const NAV = GROUPS.flatMap((g) => g.items);
const BOTTOM = ['/', '/tablero', '/productos'].map((h) => NAV.find((n) => n.href === h)!);

const isActive = (path: string, href: string) => (href === '/' ? path === '/' : path.startsWith(href));

export function Shell({ name, role, env, alerts = 0, board = false, signOut, children }: { name: string; role: string; env?: string; alerts?: number; board?: boolean; signOut: () => Promise<void>; children: React.ReactNode }) {
  const path = usePathname();
  return (
    <div className="min-h-dvh lg:flex">
      {/* Sidebar (tablet landscape / desktop) */}
      <aside className={`sticky hidden w-64 ${env === 'staging' ? 'top-12 h-[calc(100dvh-3rem)]' : 'top-0 h-dvh'} shrink-0 flex-col overflow-y-auto bg-[#100E0B] px-4 py-7 text-[#CFC6B8] lg:flex`}>
        <Link href="/" className="mb-8 block px-3">
          <div className="font-display text-3xl leading-none text-[#F7E7C4]">Fuxia <span className="text-[#E8C98A]">360</span></div>
          <div className="mt-1 text-[10px] uppercase tracking-[0.28em] text-[#A79F92]">Fuxia Ballerinas</div>
          <div className="mt-1 text-[11px] text-[#8E877C]">by HiloLabs.ai</div>
        </Link>
        <nav className="flex flex-1 flex-col gap-5">
          {GROUPS.map((g) => ({ ...g, items: g.items.filter((n) => ('board' in n ? board : !('admin' in n) || role === 'owner' || role === 'operator')) })).filter((g) => g.items.length > 0).map((g) => (
            <div key={g.label} className="flex flex-col gap-0.5">
              <div className="px-3 pb-1.5 text-[10px] font-bold uppercase tracking-[0.26em] text-[#8E877C]">{g.label}</div>
              {g.items.map(({ href, label, icon: Icon, live }) => (
                <Link key={href} href={href} aria-current={isActive(path, href) ? 'page' : undefined}
                  className={`relative flex min-h-10 items-center gap-3 rounded-xl px-3 py-2 text-[14px] transition ${isActive(path, href) ? 'bg-[#E8C98A]/[.14] font-semibold text-[#F7E7C4]' : 'hover:bg-white/[.05] hover:text-[#F7E7C4]'}`}>
                  {isActive(path, href) && <span className="absolute inset-y-2 left-0 w-[3px] rounded-full bg-[#E8C98A] shadow-[0_0_10px_#E8C98A]" />}
                  <Icon className={`size-[18px] ${isActive(path, href) ? 'text-[#E8C98A]' : 'text-[#8E877C]'}`} />
                  <span className="flex-1">{label}</span>
                  {!live && <span className="text-[10px] uppercase tracking-wider text-[#8E877C]">Pronto</span>}
                  {href === '/avisos' && alerts > 0 && <span className="rounded-full bg-[#FF8A4C] px-2 py-0.5 text-[11px] font-bold text-[#1A0F06]" data-testid="alerts-badge">{alerts}</span>}
                </Link>
              ))}
            </div>
          ))}
        </nav>
        <div className="mt-6 border-t border-white/10 px-3 pt-4">
          <div className="text-sm font-medium text-[#F7E7C4]">{name}</div>
          <div className="text-xs text-[#A79F92]">{role === 'owner' ? 'Dueña' : role === 'operator' ? 'Operación' : role === 'seller' ? 'Vendedora' : 'Consulta'}{env === 'staging' ? ' · Ambiente de pruebas' : ''}</div>
          <form action={signOut}><button className="mt-3 flex items-center gap-2 text-sm text-[#A79F92] hover:text-[#F7E7C4]"><IconLogout className="size-4" />Salir</button></form>
        </div>
      </aside>

      <div className="min-w-0 flex-1 pb-24 lg:pb-0">
        {/* Mobile / portrait tablet header */}
        <header className="flex items-center justify-between px-5 pt-5 lg:hidden">
          <Link href="/" className="flex items-baseline gap-2"><span className="font-display text-2xl">Fuxia <span className="text-gold">360</span></span><span className="text-[11px] text-muted">by HiloLabs.ai</span></Link>
          <form action={signOut}><button aria-label="Salir" className="rounded-full p-2 text-muted"><IconLogout /></button></form>
        </header>
        <main className="mx-auto w-full max-w-6xl px-5 py-6 md:px-8 lg:py-10">{children}</main>
      </div>

      {/* Bottom bar (phone / portrait tablet) */}
      <nav className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-4 border-t border-line bg-surface/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden">
        {[...BOTTOM, { href: '/mas', label: 'Más', icon: IconMore, live: true }].map(({ href, label, icon: Icon }) => (
          <Link key={href} href={href} className={`flex flex-col items-center gap-1 py-3 text-xs ${isActive(path, href) ? 'text-gold-strong' : 'text-muted'}`}>
            <span className="relative"><Icon className="size-6" />{href === '/mas' && alerts > 0 && <span className="absolute -right-1.5 -top-1 size-2.5 rounded-full bg-danger" />}</span>{label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
