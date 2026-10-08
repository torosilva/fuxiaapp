import Link from 'next/link';
import { IconBag, IconBell, IconBoxes, IconCheck, IconClock, IconGrowth, IconLink, IconMove, IconReceipt, IconScissors, IconUsers } from '@/components/icons';
import { canWrite, getMe } from '@/lib/f360';

const ITEMS = [
  { href: '/transferencias', label: 'Transferencias', icon: IconMove, live: true },
  { href: '/ventas', label: 'Ventas', icon: IconReceipt, live: true, admin: true },
  { href: '/homologacion', label: 'Homologación Woo', icon: IconLink, live: true, admin: true },
  { href: '/conteo', label: 'Conteo de apertura', icon: IconCheck, live: true, admin: true },
  { href: '/tiendas', label: 'Tiendas y ubicaciones', icon: IconBoxes, live: true, admin: true },
  { href: '/vendedoras', label: 'Vendedoras', icon: IconUsers, live: true, admin: true },
  { href: '/apartados', label: 'Apartados Gold', icon: IconClock, live: true, admin: true },
  { href: '/monedas', label: 'Monedas', icon: IconReceipt, live: true, admin: true },
  { href: '/bandeja', label: 'Bandeja de clientas', icon: IconUsers, live: true },
  { href: '/clientes', label: 'Clientes', icon: IconUsers, live: true, admin: true },
  { href: '/growth', label: 'Growth', icon: IconGrowth, live: true, admin: true },
  { href: '/pedidos', label: 'Pedidos', icon: IconBag, live: false },
  { href: '/produccion', label: 'Producción', icon: IconScissors, live: false },
];

export default async function Mas() {
  const me = await getMe();
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Más</h1>
      <div className="mt-6 grid gap-3">
        <Link href="/avisos" className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
          <IconBell className="size-6 text-gold-strong" /><span className="flex-1 text-lg text-ink">Avisos de sincronización</span>
        </Link>
        {ITEMS.filter((i) => !('admin' in i) || canWrite(me.role)).map(({ href, label, icon: Icon, live }) => (
          <Link key={href} href={href} className="flex items-center gap-4 rounded-2xl border border-line bg-surface p-5">
            <Icon className="size-6 text-muted" /><span className="flex-1 text-lg text-ink">{label}</span>{!live && <span className="text-sm text-muted">Próximamente</span>}
          </Link>
        ))}
      </div>
    </div>
  );
}
