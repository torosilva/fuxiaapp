import Link from 'next/link';
import { IconBell, IconBoxes, IconCamera, IconCheck, IconClock, IconGrowth, IconLink, IconMove, IconReceipt, IconUsers } from '@/components/icons';
import { boardNavVisible } from '@/lib/board';
import { canWrite, getMe } from '@/lib/f360';

const ITEMS = [
  { href: '/como-funciona', label: 'Mapa del negocio', icon: IconGrowth, live: true, admin: true },
  { href: '/transferencias', label: 'Transferencias', icon: IconMove, live: true },
  { href: '/ventas', label: 'Ventas', icon: IconReceipt, live: true, admin: true },
  { href: '/homologacion', label: 'Homologación Woo', icon: IconLink, live: true, admin: true },
  { href: '/conteo', label: 'Conteo de apertura', icon: IconCheck, live: true, admin: true },
  { href: '/tiendas', label: 'Tiendas y ubicaciones', icon: IconBoxes, live: true, admin: true },
  { href: '/vendedoras', label: 'Vendedoras', icon: IconUsers, live: true, admin: true },
  { href: '/apartados', label: 'Apartados', icon: IconClock, live: true, admin: true },
  { href: '/monedas', label: 'Monedas', icon: IconReceipt, live: true, admin: true },
  { href: '/foto-app', label: 'Foto de la app', icon: IconCamera, live: true },
  { href: '/bandeja', label: 'Bandeja de clientas', icon: IconUsers, live: true },
  { href: '/clientes', label: 'Clientes', icon: IconUsers, live: true, admin: true },
  { href: '/growth', label: 'Growth (medición)', icon: IconGrowth, live: true, admin: true },
  { href: '/skills', label: 'Fuxia Skills', icon: IconCheck, live: true, admin: true },
  { href: '/pendientes', label: 'Pendientes de la semana', icon: IconCheck, live: true, admin: true },
  { href: '/usuarios', label: 'Usuarios', icon: IconUsers, live: true, admin: true },
];

export default async function Mas() {
  const [me, board] = await Promise.all([getMe(), boardNavVisible().catch(() => false)]);
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Más</h1>
      <div className="mt-6 grid gap-3">
        <Link href="/avisos" className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
          <IconBell className="size-6 text-gold-strong" /><span className="flex-1 text-lg text-ink">Avisos de sincronización</span>
        </Link>
        {board && [['/estrategia', 'Strategy & Board 🔒'], ['/direccion', 'Dirección 🔒'], ['/inteligencia', 'Inteligencia 🔒'], ['/cierre-contable', 'Cierre contable']].map(([href, label]) => (
          <Link key={href} href={href} className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
            <IconGrowth className="size-6 text-gold-strong" /><span className="flex-1 text-lg text-ink">{label}</span>
          </Link>
        ))}
        {ITEMS.filter((i) => !('admin' in i) || canWrite(me.role)).map(({ href, label, icon: Icon, live }) => (
          <Link key={href} href={href} className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
            <Icon className="size-6 text-muted" /><span className="flex-1 text-lg text-ink">{label}</span>{!live && <span className="text-sm text-muted">Próximamente</span>}
          </Link>
        ))}
      </div>
    </div>
  );
}
