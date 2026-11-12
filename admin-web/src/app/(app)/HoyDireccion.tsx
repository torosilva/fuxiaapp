import Link from 'next/link';
import { FlowMap } from './como-funciona/FlowMap';
import { toFlowStats } from '@/lib/flow-stats';
import { liveToday } from '@/lib/live-today';

// Fase 3 (Mario 2026-11-12): Dirección and Operación see the business of today first — 4 numbers, the live map and what to
// attend. Same numbers as the Mapa del negocio (lib/live-today); a failed source shows "—", never an invented figure.
const n = (v: number | null) => (v === null ? '—' : v.toLocaleString('es-MX'));
const mxn = (v: number | null) => (v === null ? '—' : `$${Math.round(v).toLocaleString('es-MX')}`);

export async function HoyDireccion() {
  const t = await liveToday();
  const kpis = [
    { label: 'Venta de hoy', value: mxn(t.revenue), href: '/ventas' },
    { label: 'Pares vendidos', value: n(t.pairs), href: '/ventas' },
    { label: 'Por enviar', value: n(t.toShip), href: '/ventas' },
    { label: 'Clientas por atender', value: n(t.openInbox), href: '/bandeja' },
  ];
  const attend = [
    { label: 'Avisos sin resolver', value: t.avisos, href: '/avisos' },
    { label: 'Clientas esperando respuesta en la Bandeja', value: t.openInbox, href: '/bandeja' },
    { label: 'Pares sobre pedido por fabricar', value: t.toMake, href: '/sobre-pedido' },
    { label: 'Apartados que vencen pronto', value: t.reservationsSoon, href: '/apartados' },
  ];
  return (
    <section className="mt-8" data-testid="hoy-direccion">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {kpis.map((k) => (
          <Link key={k.label} href={k.href} className="rounded-2xl border border-line bg-surface p-4 transition hover:border-gold/40">
            <div className="text-sm text-ink-2">{k.label}</div>
            <div className="tabular mt-1 text-3xl font-semibold tracking-tight text-ink">{k.value}</div>
          </Link>
        ))}
      </div>

      <div className="mt-8">
        <div className="flex items-baseline justify-between">
          <h2 className="font-display text-3xl text-ink">Mapa del negocio, en vivo</h2>
          <Link href="/como-funciona" className="text-sm text-gold-strong hover:underline">Abrir completo</Link>
        </div>
        <div className="mt-4"><FlowMap stats={toFlowStats(t)} /></div>
      </div>

      <div className="mt-8 rounded-3xl border border-line bg-surface">
        <h2 className="font-display px-5 pt-5 text-3xl text-ink">Qué atender hoy</h2>
        <ul className="mt-3 divide-y divide-line">
          {attend.map((a) => (
            <li key={a.label}>
              <Link href={a.href} className="flex items-center justify-between px-5 py-3.5 transition hover:bg-bg">
                <span className="text-ink">{a.label}</span>
                <span className={`tabular rounded-full px-3 py-1 text-sm ${(a.value ?? 0) > 0 ? 'bg-gold-soft text-ink' : 'text-muted'}`}>{n(a.value)} →</span>
              </Link>
            </li>
          ))}
          <li>
            <Link href="/pendientes" className="flex items-center justify-between px-5 py-3.5 transition hover:bg-bg">
              <span className="text-ink">Pendientes de la semana</span><span className="text-sm text-muted">→</span>
            </Link>
          </li>
        </ul>
      </div>
    </section>
  );
}
