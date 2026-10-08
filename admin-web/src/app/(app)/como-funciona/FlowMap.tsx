'use client';
import Link from 'next/link';
import { useEffect, useRef, useState } from 'react';

// "Cómo funciona" (Mario 2026-10-08): the zoom-out of the video (tools/video/historia, "Todo el negocio, conectado") as a live
// map. Gold dots travel along the real data paths; every node opens its module. Two layouts: wide (side by side) and phone
// (stacked). Coordinates are in each layout's viewBox; the HTML nodes sit on top at the same positions, in percent.

type Pt = { x: number; y: number };
type Node = { id: string; href: string; title: string; sub: string; side: 'in' | 'out'; wide: Pt; phone: Pt };

const NODES: Node[] = [
  { id: 'online', href: '/sobre-pedido', title: 'Tienda en línea', sub: 'Cada pedido pagado descuenta su par', side: 'in', wide: { x: 150, y: 110 }, phone: { x: 105, y: 80 } },
  { id: 'tiendas', href: '/ventas', title: 'Tiendas', sub: 'Ventas de las vendedoras, con puntos', side: 'in', wide: { x: 150, y: 260 }, phone: { x: 295, y: 80 } },
  { id: 'hilo', href: '/bandeja', title: 'Hilo', sub: 'Lo que piden las clientas por chat', side: 'in', wide: { x: 150, y: 410 }, phone: { x: 105, y: 210 } },
  { id: 'taller', href: '/recibir', title: 'Taller', sub: 'Lo que llega entra a Bodega', side: 'in', wide: { x: 150, y: 560 }, phone: { x: 295, y: 210 } },
  { id: 'inventario', href: '/inventario', title: 'Inventario', sub: 'Qué hay y dónde, por talla', side: 'out', wide: { x: 1050, y: 110 }, phone: { x: 105, y: 740 } },
  { id: 'clientas', href: '/clientes', title: 'Clientas', sub: 'Ficha, compras, dirección y monedas', side: 'out', wide: { x: 1050, y: 260 }, phone: { x: 295, y: 740 } },
  { id: 'apartados', href: '/apartados', title: 'Apartados', sub: 'Pares guardados para clientas Gold', side: 'out', wide: { x: 1050, y: 410 }, phone: { x: 105, y: 870 } },
  { id: 'growth', href: '/growth', title: 'Crecer', sub: 'Demanda, favoritos y ventas', side: 'out', wide: { x: 1050, y: 560 }, phone: { x: 295, y: 870 } },
];

const LAYOUTS = {
  wide: { w: 1200, h: 680, hub: { x: 600, y: 335 }, r: 78, card: 240, avisos: { x: 600, y: 600 } },
  phone: { w: 400, h: 960, hub: { x: 200, y: 475 }, r: 66, card: 172, avisos: { x: 200, y: 618 } },
};
type Layout = keyof typeof LAYOUTS;

function edge(n: Node, l: Layout): string {
  const L = LAYOUTS[l], p = n[l], half = L.card / 2, { hub, r } = L;
  if (l === 'wide') {
    return n.side === 'in'
      ? `M${p.x + half} ${p.y} C ${p.x + half + 130} ${p.y}, ${hub.x - r - 100} ${hub.y}, ${hub.x - r} ${hub.y}`
      : `M${hub.x + r} ${hub.y} C ${hub.x + r + 100} ${hub.y}, ${p.x - half - 130} ${p.y}, ${p.x - half} ${p.y}`;
  }
  // phone: sources above the hub, results below it
  return n.side === 'in'
    ? `M${p.x} ${p.y + 46} C ${p.x} ${p.y + 160}, ${hub.x} ${hub.y - r - 120}, ${hub.x} ${hub.y - r}`
    : `M${hub.x + (p.x < hub.x ? -0.6 : 0.6) * r} ${hub.y + 0.8 * r} C ${p.x} ${hub.y + r + 70}, ${p.x} ${p.y - 120}, ${p.x} ${p.y - 46}`;
}

// Inventario → Tienda en línea: the store shows Fuxia 360's stock (pushed every minute).
const STOCK_ARC = { wide: 'M1050 66 C 1050 -6, 150 -6, 150 66', phone: 'M19 740 C -4 560, -4 260, 19 80' };
const avisosEdge = (l: Layout) => { const { hub, r, avisos } = LAYOUTS[l]; return `M${hub.x} ${hub.y + r} L${avisos.x} ${avisos.y - 20}`; };

const pct = (v: number, of: number) => `${(v / of) * 100}%`;

function Dots({ d, dur, color, count = 2, r = 3.6 }: { d: string; dur: number; color: string; count?: number; r?: number }) {
  return <>{Array.from({ length: count }, (_, i) => (
    <circle key={i} r={r} fill={color} opacity="0">
      <animateMotion path={d} dur={`${dur}s`} begin={`${1.4 + (i * dur) / count}s`} repeatCount="indefinite" />
      <animate attributeName="opacity" values="0;1;1;0" keyTimes="0;0.15;0.85;1" dur={`${dur}s`} begin={`${1.4 + (i * dur) / count}s`} repeatCount="indefinite" />
    </circle>
  ))}</>;
}

function FlowLayout({ layout, active, setActive }: { layout: Layout; active: string | null; setActive: (id: string | null) => void }) {
  const L = LAYOUTS[layout];
  const svg = useRef<SVGSVGElement>(null);
  useEffect(() => {
    // Reduced motion: freeze the dots mid-path (still shows the direction of each flow).
    if (svg.current && window.matchMedia('(prefers-reduced-motion: reduce)').matches) { svg.current.setCurrentTime(2.6); svg.current.pauseAnimations(); }
  }, []);
  const dim = (id: string) => (active && active !== id ? 0.22 : 1);
  return (
    <div className="relative w-full" style={{ aspectRatio: `${L.w} / ${L.h}` }}>
      <svg ref={svg} viewBox={`0 0 ${L.w} ${L.h}`} className="absolute inset-0 size-full overflow-visible" aria-hidden="true">
        <defs>
          <radialGradient id={`glow-${layout}`}><stop offset="0" stopColor="#E8C98A" stopOpacity=".28" /><stop offset="1" stopColor="#E8C98A" stopOpacity="0" /></radialGradient>
        </defs>
        <circle cx={L.hub.x} cy={L.hub.y} r={L.r * 2.6} fill={`url(#glow-${layout})`} />
        <path d={STOCK_ARC[layout]} fill="none" stroke="#E8C98A" strokeWidth="1.6" strokeDasharray="5 7" opacity={active && !['inventario', 'online'].includes(active) ? 0.15 : 0.55} />
        <Dots d={STOCK_ARC[layout]} dur={6} color="#F7E7C4" count={3} r={3} />
        {NODES.map((n) => {
          const d = edge(n, layout);
          return (
            <g key={n.id} opacity={dim(n.id)} style={{ transition: 'opacity .3s' }}>
              <path d={d} fill="none" stroke="#E8C98A" strokeWidth={active === n.id ? 2.6 : 1.8} strokeOpacity=".7" />
              <Dots d={d} dur={n.side === 'in' ? 2.8 : 3.2} color="#E8C98A" r={active === n.id ? 4.6 : 3.6} />
            </g>
          );
        })}
        <path d={avisosEdge(layout)} fill="none" stroke="#FF8A4C" strokeWidth="1.6" strokeDasharray="3 6" opacity={active && active !== 'avisos' ? 0.15 : 0.6} />
        <Dots d={avisosEdge(layout)} dur={2.4} color="#FF8A4C" count={1} r={3} />
        <circle cx={L.hub.x} cy={L.hub.y} r={L.r + 10} fill="none" stroke="#E8C98A" strokeOpacity=".35" className="hub-ring" style={{ transformOrigin: `${L.hub.x}px ${L.hub.y}px` }} />
      </svg>

      {NODES.map((n) => (
        <Link key={n.id} href={n.href} onMouseEnter={() => setActive(n.id)} onMouseLeave={() => setActive(null)} onFocus={() => setActive(n.id)} onBlur={() => setActive(null)}
          className="flow-node absolute -translate-x-1/2 -translate-y-1/2 rounded-2xl border border-[#E8C98A]/30 bg-[#1B1712] px-3 py-2.5 text-center shadow-[0_18px_40px_-22px_rgba(0,0,0,.9)] transition hover:border-[#E8C98A] hover:bg-[#241E16] md:px-4 md:py-3.5"
          style={{ left: pct(n[layout].x, L.w), top: pct(n[layout].y, L.h), width: pct(L.card, L.w), opacity: dim(n.id) === 1 ? 1 : 0.55 }}>
          <span className="kicker block text-[10px] text-[#F7E7C4] md:text-[11px]">{n.title}</span>
          <span className="mt-1 block text-[11px] leading-snug text-[#B8AE9F] md:text-[12.5px]">{n.sub}</span>
        </Link>
      ))}

      <Link href="/tablero" onMouseEnter={() => setActive('hub')} onMouseLeave={() => setActive(null)}
        className="absolute flex -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-full bg-[#0B0907] text-center shadow-[0_0_0_10px_rgba(232,201,138,.10),0_24px_50px_rgba(0,0,0,.5)] ring-1 ring-[#E8C98A]/60 transition hover:ring-2 hover:ring-[#E8C98A]"
        style={{ left: pct(L.hub.x, L.w), top: pct(L.hub.y, L.h), width: pct(L.r * 2, L.w), aspectRatio: '1' }}>
        <span className="font-display text-[22px] leading-none text-[#F7E7C4] md:text-[30px]">Fuxia <span className="text-[#E8C98A]">360</span></span>
        <span className="mt-1 text-[9px] font-semibold uppercase tracking-[0.2em] text-[#8E877C] md:text-[10px]">Centro de control</span>
      </Link>

      <Link href="/avisos" onMouseEnter={() => setActive('avisos')} onMouseLeave={() => setActive(null)}
        className="absolute -translate-x-1/2 -translate-y-1/2 rounded-full border border-[#FF8A4C]/50 bg-[#1B1712] px-4 py-1.5 text-[11px] font-semibold uppercase tracking-[0.18em] text-[#FFB48A] transition hover:border-[#FF8A4C]"
        style={{ left: pct(LAYOUTS[layout].avisos.x, L.w), top: pct(LAYOUTS[layout].avisos.y, L.h) }}>
        Avisos
      </Link>

      {layout === 'wide' && (
        <span className="pointer-events-none absolute -translate-x-1/2 -translate-y-1/2 bg-[#100E0B] px-3 text-[10px] font-semibold uppercase tracking-[0.2em] text-[#8E877C]"
          style={{ left: '50%', top: pct(12, L.h) }}>
          Existencias a la tienda en línea, cada minuto
        </span>
      )}
    </div>
  );
}

export function FlowMap() {
  const [active, setActive] = useState<string | null>(null);
  return (
    <div className="overflow-hidden rounded-[28px] bg-[#100E0B] px-3 pb-6 pt-8 md:px-8 md:pb-10 md:pt-12">
      <div className="mx-auto hidden max-w-[1100px] md:block"><FlowLayout layout="wide" active={active} setActive={setActive} /></div>
      <div className="mx-auto max-w-[420px] md:hidden"><FlowLayout layout="phone" active={active} setActive={setActive} /></div>
    </div>
  );
}
