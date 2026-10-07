'use client';
import Link from 'next/link';
import { useEffect, useState, useSyncExternalStore } from 'react';
import type { ExecDashboard } from '@/lib/f360';
import './control.css';

// Centro de control: presentation of f360_exec_dashboard. Every number comes from the RPC; animation only reveals it
// (count-up, line draw, flows). Nothing here invents, extrapolates or mixes currencies.

const GOLD = 'var(--cc-gold)', VIOLET = 'var(--cc-violet)', MINT = 'var(--cc-mint)', SILVER = 'var(--cc-silver)', BRONZE = 'var(--cc-bronze)';
const mxn = (n: number) => `$${Math.round(n).toLocaleString('es-MX')}`;
const money = (n: number, cur: string) => (cur === 'MXN' ? mxn(n) : `${cur} ${Math.round(n).toLocaleString('es-MX')}`);
const int = (n: number) => Math.round(n).toLocaleString('es-MX');
const PERIOD_LABEL: Record<string, string> = { hoy: 'Hoy', semana: '7 días', mes: 'Este mes', anio: 'Este año' };
const PREV_LABEL: Record<string, string> = { hoy: 'vs mismo día de la semana pasada', semana: 'vs 7 días anteriores', mes: 'vs mismo avance del mes pasado', anio: 'vs mismo avance del año pasado' };

// 0 → 1 over `ms` with ease-out; restarts when `key` changes.
function useReveal(key: string, ms = 1600) {
  const [e, setE] = useState(0);
  useEffect(() => {
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    let raf = 0, t0 = 0;
    const step = (t: number) => {
      if (!t0) t0 = t;
      const p = reduced ? 1 : Math.min(1, (t - t0) / ms);
      setE(1 - Math.pow(1 - p, 3));
      if (p < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [key, ms]);
  return e;
}
function useTick(ms: number) {
  const [n, setN] = useState(0);
  useEffect(() => { const id = setInterval(() => setN((x) => x + 1), ms); return () => clearInterval(id); }, [ms]);
  return n;
}
function smooth(pts: [number, number][]) {
  if (!pts.length) return '';
  let d = `M${pts[0][0]} ${pts[0][1]}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] ?? pts[i], p1 = pts[i], p2 = pts[i + 1], p3 = pts[i + 2] ?? p2;
    d += ` C${(p1[0] + (p2[0] - p0[0]) / 6).toFixed(1)} ${(p1[1] + (p2[1] - p0[1]) / 6).toFixed(1)} ${(p2[0] - (p3[0] - p1[0]) / 6).toFixed(1)} ${(p2[1] - (p3[1] - p1[1]) / 6).toFixed(1)} ${p2[0].toFixed(1)} ${p2[1].toFixed(1)}`;
  }
  return d;
}
// Claro / Oscuro, remembered per browser (if storage is blocked it still switches, just not remembered).
const THEME_KEY = 'f360-cc-theme';
const themeListeners = new Set<() => void>();
let memTheme: 'light' | 'dark' = 'light';
function readTheme(): 'light' | 'dark' { try { const v = localStorage.getItem(THEME_KEY); return v === 'dark' || v === 'light' ? v : memTheme; } catch { return memTheme; } }
function subscribeTheme(fn: () => void) { themeListeners.add(fn); window.addEventListener('storage', fn); return () => { themeListeners.delete(fn); window.removeEventListener('storage', fn); }; }
function pickTheme(t: 'light' | 'dark') { memTheme = t; try { localStorage.setItem(THEME_KEY, t); } catch {} themeListeners.forEach((fn) => fn()); }
const delta = (cur: number, prev: number) => (prev > 0 ? Math.round(((cur - prev) / prev) * 100) : null);

function Eyebrow({ children }: { children: React.ReactNode }) {
  return <p className="font-mono text-[11px] uppercase tracking-[0.2em] text-[var(--cc-faint)]">{children}</p>;
}
function Title({ children }: { children: React.ReactNode }) {
  return <h2 className="font-display text-[30px] leading-tight text-[var(--cc-ink)]">{children}</h2>;
}
function Empty({ children }: { children: React.ReactNode }) {
  return <p className="rounded-2xl border border-dashed border-[var(--cc-line)] px-4 py-6 text-center text-sm text-[var(--cc-faint)]">{children}</p>;
}
function Ring({ r, pct, color, width, e }: { r: number; pct: number; color: string; width: number; e: number }) {
  const c = 2 * Math.PI * r;
  return (
    <>
      <circle cx="0" cy="0" r={r} fill="none" stroke="var(--cc-track)" strokeWidth={width} />
      <circle className="cc-ring" cx="0" cy="0" r={r} fill="none" stroke={color} strokeWidth={width} strokeLinecap="round" transform="rotate(-90)"
        strokeDasharray={c.toFixed(1)} strokeDashoffset={(c * (1 - Math.max(0, Math.min(1, pct / 100)) * e)).toFixed(1)} style={{ filter: `drop-shadow(0 0 6px ${color})` }} />
    </>
  );
}

export function ControlCenter({ data }: { data: ExecDashboard }) {
  const e = useReveal(`${data.period}-${data.presentation}`);
  const tick = useTick(3000);
  // Claro by default (Mario 2026-10-06); Oscuro is remembered per browser.
  const theme = useSyncExternalStore(subscribeTheme, readTheme, () => 'light' as const);
  const [clock, setClock] = useState('');
  useEffect(() => {
    const f = () => setClock(new Date().toLocaleTimeString('es-MX', { timeZone: 'America/Mexico_City', hour: '2-digit', minute: '2-digit', second: '2-digit' }));
    f(); const id = setInterval(f, 1000); return () => clearInterval(id);
  }, []);

  const k = data.kpis;
  const dSales = delta(k.sales, k.sales_prev), dPairs = delta(k.pairs, k.pairs_prev);
  const href = (p: Record<string, string>) => {
    const q = new URLSearchParams({ periodo: data.period, ...(data.presentation ? { vista: 'presentacion' } : {}), ...p });
    if (q.get('vista') === 'interna') q.delete('vista');
    return `/tablero?${q.toString()}`;
  };
  const pill = (on: boolean) => `inline-flex min-h-11 items-center rounded-full border px-4 text-sm font-semibold transition ${on
    ? 'border-[var(--cc-pill-bg)] bg-[var(--cc-pill-bg)] text-[var(--cc-pill-ink)] shadow-[var(--cc-pill-glow)]' : 'border-[var(--cc-line)] bg-[var(--cc-tint)] text-[var(--cc-ink)] hover:border-[var(--cc-line-strong)]'}`;

  // charts
  const daily = data.daily;
  const maxDay = Math.max(1, ...daily.map((d) => d.store + d.online));
  const X = (i: number, w: number) => (daily.length > 1 ? (i * w) / (daily.length - 1) : 0);
  const spark = smooth(daily.map((d, i) => [X(i, 600), 112 - ((d.store + d.online) / maxDay) * 100] as [number, number]));
  const stLine = smooth(daily.map((d, i) => [X(i, 1000), 285 - (d.store / maxDay) * 250] as [number, number]));
  const onLine = smooth(daily.map((d, i) => [X(i, 1000), 285 - (d.online / maxDay) * 250] as [number, number]));
  const mixTotal = data.mix.store + data.mix.online;
  const storePct = mixTotal > 0 ? Math.round((data.mix.store / mixTotal) * 100) : 0;

  // network: warehouse hub + selling places on an ellipse
  const hub = data.inventory.find((i) => i.type === 'warehouse');
  const places = data.by_location.slice(0, 6);
  const maxPlace = Math.max(1, ...places.map((p) => p.sales));
  const nodes = places.map((p, i) => {
    const a = -Math.PI / 2 + (i * 2 * Math.PI) / Math.max(places.length, 1) + 0.35;
    const x = 600 + Math.cos(a) * 430, y = 215 + Math.sin(a) * 150, r = 14 + Math.sqrt(p.sales / maxPlace) * 24;
    return { ...p, x, y, r, color: p.kind === 'online' ? VIOLET : p.historical ? SILVER : GOLD };
  });

  const heatMax = Math.max(1, ...data.heatmap.rows.flatMap((r) => Object.values(r.cells).map((c) => c.sold)));
  const pipe = data.pipeline;
  const pipeRows = [
    { label: 'Apartados activos', sub: `${int(pipe.reservations.count)} pares · ${int(pipe.reservations.expiring_48h)} vencen en 48 h`, value: mxn(pipe.reservations.value * e), w: pipe.reservations.count, color: GOLD },
    { label: 'Pedidos en línea por enviar desde tienda', sub: `${int(pipe.to_ship.orders)} pedidos`, value: `${int(pipe.to_ship.pairs * e)} pares`, w: pipe.to_ship.pairs, color: GOLD },
    { label: 'Sobre pedido en curso', sub: `${int(pipe.made_to_order.count)} pedidos · 10 días hábiles`, value: `${int(pipe.made_to_order.pairs * e)} pares`, w: pipe.made_to_order.pairs, color: GOLD },
    { label: 'Ligas de pago abiertas', sub: 'esperando pago o atención', value: int(pipe.pay_links.open * e), w: pipe.pay_links.open, color: VIOLET },
    { label: 'Puntos por liberar', sub: `${int(pipe.held_points.customers)} clientas por confirmar su WhatsApp`, value: `${int(pipe.held_points.points * e)} pts`, w: pipe.held_points.points / 100, color: VIOLET },
  ];
  const pipeMax = Math.max(1, ...pipeRows.map((p) => p.w));
  const tiers = data.crm.tiers, tierTotal = Math.max(1, tiers.gold + tiers.silver + tiers.bronze);
  const live = data.feed.length ? tick % data.feed.length : 0;

  return (
    <div data-theme={theme} className="cc-root overflow-hidden rounded-[28px] px-5 pb-16 text-[var(--cc-ink)] md:px-8" style={{
      background: 'radial-gradient(1200px 600px at 80% -10%, var(--cc-glow1), transparent 60%), radial-gradient(900px 500px at -10% 30%, var(--cc-glow2), transparent 60%), var(--cc-bg)' }}>
      {data.includes_test_data && (
        <div className="-mx-5 bg-[#7A4B12] px-4 py-2 text-center text-xs font-bold tracking-[0.14em] text-[#FFF1DC] md:-mx-8">
          STAGING · INCLUYE PEDIDOS DE PRUEBA — EN PRODUCCIÓN SE EXCLUYEN
        </div>
      )}

      <header className="cc-grid -mx-5 border-b border-[var(--cc-line)] px-5 pb-7 pt-9 md:-mx-8 md:px-8">
        <div className="mx-auto flex max-w-[1320px] flex-wrap items-end justify-between gap-6">
          <div className="flex flex-col gap-2">
            <p className="font-mono text-xs tracking-[0.28em] text-[var(--cc-gold-text)]">FUXIA 360 // OMNICHANNEL OS</p>
            <h1 className="font-display cc-glow text-6xl leading-[0.95] text-[var(--cc-ink-strong)]">Centro de control</h1>
            <p className="flex items-center gap-2 font-mono text-sm text-[var(--cc-muted)]">
              <span className="cc-live inline-block h-2 w-2 rounded-full bg-[#FF5A4E] shadow-[0_0_10px_#FF5A4E]" />
              EN VIVO · {clock || '—'} · CDMX
            </p>
          </div>
          <div className="flex flex-col items-start gap-2">
            <nav className="flex flex-wrap gap-2" aria-label="Periodo">
              {(['hoy', 'semana', 'mes', 'anio'] as const).map((p) => <Link key={p} href={href({ periodo: p })} className={pill(data.period === p)} aria-current={data.period === p ? 'page' : undefined}>{PERIOD_LABEL[p]}</Link>)}
            </nav>
            <div role="group" aria-label="Apariencia" className="flex flex-wrap gap-2">
              {(['light', 'dark'] as const).map((t) => (
                <button key={t} type="button" aria-pressed={theme === t} onClick={() => pickTheme(t)} className={pill(theme === t)}>{t === 'light' ? '☀︎ Claro' : '☾ Oscuro'}</button>
              ))}
            </div>
            <nav className="flex flex-wrap gap-2" aria-label="Vista">
              <Link href={href({ vista: 'interna' })} className={pill(!data.presentation)}>Vista interna</Link>
              <Link href={href({ vista: 'presentacion' })} className={pill(data.presentation)}>Vista presentación</Link>
            </nav>
          </div>
        </div>
      </header>

      <main className="mx-auto flex max-w-[1320px] flex-col gap-6 pt-8">
        {/* hero */}
        <section className="flex flex-wrap gap-6">
          <div className="cc-panel relative flex min-w-0 flex-[999_1_560px] flex-col gap-4 overflow-hidden p-7">
            <Eyebrow>Ventas netas de producto · {PERIOD_LABEL[data.period]} · MXN</Eyebrow>
            <p className="font-display cc-glow tabular text-[clamp(56px,8vw,88px)] leading-[0.92] tracking-tight text-[var(--cc-ink-strong)]">{mxn(k.sales * e)}</p>
            <div className="flex flex-wrap items-center gap-3 text-sm">
              {dSales !== null ? (
                <span className={`tabular rounded-full border px-3 py-1 font-bold ${dSales >= 0 ? 'border-[var(--cc-mint)]/30 bg-[var(--cc-mint)]/10 text-[var(--cc-mint)]' : 'border-[var(--cc-neg)]/30 bg-[var(--cc-neg)]/10 text-[var(--cc-neg)]'}`}>
                  {dSales >= 0 ? '▲' : '▼'} {Math.abs(dSales)}%
                </span>
              ) : <span className="rounded-full border border-[var(--cc-line)] px-3 py-1 text-[var(--cc-muted)]">sin periodo anterior para comparar</span>}
              <span className="text-[var(--cc-muted)]">{PREV_LABEL[data.period]}</span>
              {k.historical_included > 0 && <span className="rounded-full border border-[var(--cc-silver)]/30 px-3 py-1 text-[var(--cc-silver)]">incluye {mxn(k.historical_included)} de ventas pasadas cargadas</span>}
            </div>
            <svg viewBox="0 0 600 120" preserveAspectRatio="none" className="block h-[120px] w-full" aria-hidden="true">
              <defs><linearGradient id="ccspark" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={GOLD} stopOpacity=".45" /><stop offset="1" stopColor={GOLD} stopOpacity="0" /></linearGradient></defs>
              {spark && <path className="cc-fade" d={`${spark} L600 120 L0 120 Z`} fill="url(#ccspark)" />}
              {spark && <path key={data.period} className="cc-draw" d={spark} fill="none" stroke={GOLD} strokeWidth="2.5" />}
            </svg>
            <p className="font-mono text-[11px] text-[var(--cc-faint)]">ÚLTIMOS 30 DÍAS · TIENDAS + EN LÍNEA</p>
          </div>

          <div className="cc-panel flex min-w-0 flex-[1_1_300px] flex-col items-center gap-3 p-6">
            <div className="self-start"><Eyebrow>Mezcla del periodo</Eyebrow></div>
            <svg viewBox="-120 -120 240 240" className="h-[220px] w-[220px]" role="img" aria-label={`Tiendas ${storePct}%, en línea ${100 - storePct}%`}>
              <Ring r={96} pct={mixTotal ? storePct : 0} color={GOLD} width={12} e={e} />
              <Ring r={74} pct={mixTotal ? 100 - storePct : 0} color={VIOLET} width={12} e={e} />
              <Ring r={52} pct={k.store_identified_pct ?? 0} color={MINT} width={12} e={e} />
              <circle className="cc-spin" r="30" fill="none" stroke="var(--cc-gold)" strokeOpacity=".6" strokeWidth="1" strokeDasharray="3 6" />
            </svg>
            <div className="flex w-full flex-col gap-2 text-sm">
              {[[GOLD, 'Tiendas y bazares', mixTotal ? `${storePct}%` : '—'], [VIOLET, 'En línea', mixTotal ? `${100 - storePct}%` : '—'],
                [MINT, 'Ventas en tienda con clienta', k.store_identified_pct === null ? '—' : `${k.store_identified_pct}%`]].map(([c, l, v]) => (
                <div key={l} className="flex justify-between gap-3 border-t border-[var(--cc-line)] pt-2">
                  <span className="inline-flex items-center gap-2"><span className="h-2.5 w-2.5 rounded-full" style={{ background: c, boxShadow: `0 0 8px ${c}` }} />{l}</span>
                  <span className="tabular font-mono text-[var(--cc-gold-text)]">{v}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="cc-panel flex min-w-0 flex-[1_1_320px] flex-col gap-3 p-6">
            <div className="flex items-center justify-between"><Eyebrow>Últimas ventas</Eyebrow><span className="font-mono text-[11px] text-[var(--cc-neg)]">● LIVE</span></div>
            {data.feed.length === 0 ? <Empty>Todavía no hay ventas en este ambiente.</Empty> : data.feed.slice(0, 6).map((f, i) => (
              <div key={`${f.at}-${i}`} className={`flex items-center gap-3 rounded-2xl border px-3 py-2.5 transition ${i === live ? 'cc-feedin border-[var(--cc-line-strong)] bg-[var(--cc-feed-on)]' : 'border-[var(--cc-line)] bg-[var(--cc-tint)]'}`}>
                <span className="h-2.5 w-2.5 flex-none rounded-full" style={{ background: f.channel === 'store' ? GOLD : VIOLET, boxShadow: `0 0 10px ${f.channel === 'store' ? GOLD : VIOLET}` }} />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-sm font-semibold">{f.place} · {f.item ?? 'Producto'}</span>
                  <span className="font-mono text-[11px] text-[var(--cc-faint)]">{new Date(f.at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</span>
                </div>
                <span className="tabular font-mono text-sm text-[var(--cc-gold-text)]">{money(f.amount, f.currency)}</span>
              </div>
            ))}
          </div>
        </section>

        {/* KPIs */}
        <section className="grid grid-cols-[repeat(auto-fit,minmax(210px,1fr))] gap-4">
          {[
            { l: 'Pares vendidos', v: int(k.pairs * e), s: dPairs === null ? 'tiendas + bazares + en línea' : `${dPairs >= 0 ? '+' : ''}${dPairs}% ${PREV_LABEL[data.period]}`, w: 100, c: GOLD },
            { l: 'Ticket promedio', v: k.ticket === null ? '—' : mxn(k.ticket * e), s: `${int(k.orders)} ventas registradas en MXN`, w: 70, c: GOLD },
            { l: 'Clientas', v: int(data.crm.customers * e), s: `+${int(data.crm.new_in_period)} en el periodo`, w: 60, c: MINT },
            { l: 'Con permiso de novedades', v: int(data.crm.marketing_consent * e), s: 'WhatsApp o correo aceptado', w: data.crm.customers ? (data.crm.marketing_consent / data.crm.customers) * 100 : 0, c: VIOLET },
          ].map((x) => (
            <div key={x.l} className="cc-panel flex flex-col gap-2.5 p-5">
              <Eyebrow>{x.l}</Eyebrow>
              <p className="font-display tabular text-5xl leading-none text-[var(--cc-ink-strong)]">{x.v}</p>
              <div className="h-1.5 overflow-hidden rounded-full bg-[var(--cc-track)]"><div className="cc-ring h-full rounded-full" style={{ width: `${x.w * e}%`, background: x.c }} /></div>
              <p className="text-[13px] text-[var(--cc-muted)]">{x.s}</p>
            </div>
          ))}
        </section>

        {/* network */}
        <section className="cc-panel flex flex-col gap-4 overflow-hidden p-7">
          <div className="flex flex-wrap items-baseline justify-between gap-3">
            <Title>Red omnicanal</Title>
            <p className="text-sm text-[var(--cc-muted)]">Ventas del periodo por lugar · tamaño = lo vendido · gris = ventas pasadas cargadas</p>
          </div>
          {nodes.length === 0 ? <Empty>No hay ventas en este periodo.</Empty> : (
            <div className="overflow-x-auto">
              <svg viewBox="0 0 1200 440" className="block h-auto w-full min-w-[760px]" role="img" aria-label="Red de ventas por ubicación">
                <defs><radialGradient id="ccnode"><stop offset="0" stopColor={GOLD} stopOpacity=".9" /><stop offset="1" stopColor={GOLD} stopOpacity="0" /></radialGradient></defs>
                {nodes.map((n, i) => {
                  const d = `M600 215 Q${(600 + n.x) / 2} ${(215 + n.y) / 2 - 60} ${n.x} ${n.y}`;
                  return (
                    <g key={`e-${n.name}`}>
                      <path d={d} fill="none" stroke="var(--cc-line-strong)" strokeWidth="2" />
                      <path className="cc-flow" d={d} fill="none" stroke={n.color} strokeWidth="2.5" style={{ animationDuration: `${1.1 + i * 0.3}s`, animationDirection: i % 2 ? 'reverse' : 'normal' }} />
                    </g>
                  );
                })}
                <circle className="cc-pulse" cx="600" cy="215" r="30" fill="none" stroke={GOLD} strokeWidth="2" />
                <circle cx="600" cy="215" r="78" fill="url(#ccnode)" opacity=".35" />
                <circle cx="600" cy="215" r="30" fill="var(--cc-hub)" stroke={GOLD} strokeWidth="3" style={{ filter: 'drop-shadow(0 0 12px var(--cc-gold))' }} />
                <text x="600" y="267" textAnchor="middle" fontSize="17" fontWeight="700" fill="var(--cc-ink)">{hub?.name ?? 'Fuxia 360'}</text>
                {hub && <text x="600" y="287" textAnchor="middle" fontSize="13" fill="var(--cc-muted)" fontFamily="'JetBrains Mono', monospace">{int(hub.pairs)} pares en existencia</text>}
                {nodes.map((n, i) => (
                  <g key={`n-${n.name}`}>
                    <circle className="cc-pulse" cx={n.x} cy={n.y} r={n.r} fill="none" stroke={n.color} strokeWidth="2" style={{ animationDelay: `${i * 0.4}s` }} />
                    <circle cx={n.x} cy={n.y} r={n.r} fill={n.color} style={{ filter: `drop-shadow(0 0 12px ${n.color})` }} />
                    <text x={n.x} y={n.y + n.r + 24} textAnchor="middle" fontSize="16" fontWeight="700" fill="var(--cc-ink)">{n.name}</text>
                    <text x={n.x} y={n.y + n.r + 44} textAnchor="middle" fontSize="13" fill={GOLD} fontFamily="'JetBrains Mono', monospace">{mxn(n.sales * e)}</text>
                  </g>
                ))}
              </svg>
            </div>
          )}
          {data.other_currencies.length > 0 && (
            <p className="text-sm text-[var(--cc-muted)]">Otras monedas (aparte, nunca sumadas): {data.other_currencies.map((c) => `${money(c.sales, c.currency)} · ${c.orders} ventas`).join(' · ')}</p>
          )}
        </section>

        {/* pulse */}
        <section className="cc-panel flex flex-col gap-4 overflow-hidden p-7">
          <div className="flex flex-wrap items-baseline justify-between gap-3">
            <Title>Pulso de 30 días</Title>
            <div className="flex gap-4 text-[13px] text-[var(--cc-soft)]">
              <span className="inline-flex items-center gap-2"><span className="h-[3px] w-[18px] rounded" style={{ background: GOLD, boxShadow: `0 0 8px ${GOLD}` }} />Tiendas y bazares</span>
              <span className="inline-flex items-center gap-2"><span className="h-[3px] w-[18px] rounded" style={{ background: VIOLET, boxShadow: `0 0 8px ${VIOLET}` }} />En línea</span>
            </div>
          </div>
          <div className="overflow-x-auto">
            <svg viewBox="0 0 1000 300" preserveAspectRatio="none" className="block h-[300px] w-full min-w-[560px]" aria-hidden="true">
              <defs>
                <linearGradient id="ccst" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={GOLD} stopOpacity=".38" /><stop offset="1" stopColor={GOLD} stopOpacity="0" /></linearGradient>
                <linearGradient id="ccon" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={VIOLET} stopOpacity=".34" /><stop offset="1" stopColor={VIOLET} stopOpacity="0" /></linearGradient>
                <linearGradient id="ccscan" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stopColor="var(--cc-scan)" stopOpacity="0" /><stop offset=".5" stopColor="var(--cc-scan)" stopOpacity=".14" /><stop offset="1" stopColor="var(--cc-scan)" stopOpacity="0" /></linearGradient>
              </defs>
              {[60, 120, 180, 240].map((y) => <line key={y} x1="0" x2="1000" y1={y} y2={y} stroke="var(--cc-grid)" />)}
              <path className="cc-fade" d={`${stLine} L1000 300 L0 300 Z`} fill="url(#ccst)" />
              <path className="cc-fade" d={`${onLine} L1000 300 L0 300 Z`} fill="url(#ccon)" />
              <path className="cc-draw" d={stLine} fill="none" stroke={GOLD} strokeWidth="3" />
              <path className="cc-draw" d={onLine} fill="none" stroke={VIOLET} strokeWidth="3" />
              <rect className="cc-scan" x="-40" y="0" width="80" height="300" fill="url(#ccscan)" />
            </svg>
          </div>
          <div className="flex justify-between font-mono text-[11px] text-[var(--cc-faint)]">
            <span>{daily[0] && new Date(`${daily[0].d}T12:00:00`).toLocaleDateString('es-MX', { day: '2-digit', month: 'short' })}</span>
            <span>{daily.at(-1) && new Date(`${daily.at(-1)!.d}T12:00:00`).toLocaleDateString('es-MX', { day: '2-digit', month: 'short' })}</span>
          </div>
        </section>

        {/* heatmap + top models */}
        <section className="flex flex-wrap gap-6">
          <div className="cc-panel flex min-w-0 flex-[999_1_640px] flex-col gap-4 p-7">
            <div className="flex flex-wrap items-baseline justify-between gap-3">
              <Title>Mapa de calor de tallas</Title>
              <p className="text-sm text-[var(--cc-muted)]">Pares vendidos en 90 días · laten las tallas con 1 par o menos en existencia</p>
            </div>
            {data.heatmap.rows.length === 0 ? <Empty>Aún no hay ventas con modelo y talla identificados.</Empty> : (
              <div className="overflow-x-auto">
                <div className="flex min-w-[680px] flex-col gap-2">
                  <div className="grid gap-2" style={{ gridTemplateColumns: `180px repeat(${data.heatmap.sizes.length}, minmax(0,1fr))` }}>
                    <span />
                    {data.heatmap.sizes.map((s) => <span key={s} className="text-center font-mono text-xs text-[var(--cc-faint)]">{s}</span>)}
                  </div>
                  {data.heatmap.rows.map((r) => (
                    <div key={r.name} className="grid items-center gap-2" style={{ gridTemplateColumns: `180px repeat(${data.heatmap.sizes.length}, minmax(0,1fr))` }}>
                      <span className="truncate text-[15px] font-semibold">{r.name}</span>
                      {data.heatmap.sizes.map((s) => {
                        const c = r.cells[s] ?? { sold: 0, on_hand: 0 };
                        const hot = c.sold > 0 && c.on_hand <= 1;
                        const a = 0.06 + (c.sold / heatMax) * 0.86 * e;
                        return (
                          <div key={s} title={`${r.name} ${s}: ${c.sold} vendidos · ${c.on_hand} en existencia`}
                            className={`flex h-10 items-center justify-center rounded-[10px] font-mono text-xs font-bold text-[#0B0A08] transition-colors ${hot ? 'cc-hot' : ''}`}
                            style={{ backgroundColor: `rgba(${hot ? '255,138,76' : 'var(--cc-heat)'},${a.toFixed(2)})` }}>
                            {c.sold > 0 ? c.sold : ''}
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
          <div className="cc-panel flex min-w-0 flex-[1_1_320px] flex-col gap-3 p-7">
            <Title>Modelos más vendidos</Title>
            <Eyebrow>Últimos 90 días</Eyebrow>
            {data.top_models.length === 0 ? <Empty>Sin datos todavía.</Empty> : data.top_models.map((m, i) => (
              <div key={m.name} className="flex items-center gap-4 border-t border-[var(--cc-line)] pt-3">
                <span className="font-display w-7 text-3xl text-[var(--cc-rank)]">{i + 1}</span>
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate font-semibold">{m.name}</span>
                  <span className="text-[13px] text-[var(--cc-faint)]">{m.sizes?.length ? `tallas ${m.sizes.join(' · ')}` : ''}</span>
                </div>
                <span className="tabular font-semibold">{int(m.pairs)} pares</span>
              </div>
            ))}
          </div>
        </section>

        {/* pipeline */}
        <section className="cc-panel flex flex-col gap-5 p-7">
          <div className="flex flex-wrap items-baseline justify-between gap-3">
            <Title>Pipeline · lo que viene en camino</Title>
            <Link href="/demanda" className="text-sm text-[var(--cc-gold-text)] hover:underline">Demanda sin inventario →</Link>
            <span className="font-display cc-glow tabular text-4xl text-[var(--cc-ink-strong)]">{mxn(pipe.reservations.value * e)}</span>
          </div>
          {pipeRows.map((s, i) => (
            <div key={s.label} className="grid items-center gap-4 sm:grid-cols-[minmax(170px,280px)_minmax(0,1fr)_minmax(110px,150px)]">
              <div className="flex flex-col"><span className="text-[15px] font-semibold">{s.label}</span><span className="text-xs text-[var(--cc-faint)]">{s.sub}</span></div>
              <div className="relative h-3.5 overflow-hidden rounded-full bg-[var(--cc-track)]">
                <div className="cc-ring h-full rounded-full" style={{ width: `${(s.w / pipeMax) * 100 * e}%`, background: `linear-gradient(90deg, var(--cc-track), ${s.color})` }} />
                {s.w > 0 && [0, 1, 2].map((p) => <span key={p} className="cc-particle" style={{ animationDelay: `${i * 0.35 + p * 1.05}s`, animationDuration: `${2.6 + i * 0.3}s`, background: s.color, boxShadow: `0 0 12px ${s.color}` }} />)}
              </div>
              <span className="tabular text-right font-mono text-base text-[var(--cc-gold-text)]">{s.value}</span>
            </div>
          ))}
        </section>

        {/* CRM + birthdays */}
        <section className="flex flex-wrap gap-6">
          <div className="cc-panel flex min-w-0 flex-[999_1_560px] flex-wrap items-center gap-7 p-7">
            <svg viewBox="-130 -130 260 260" className="h-[230px] w-[230px] flex-none" role="img" aria-label="Clientas por nivel">
              <Ring r={110} pct={(tiers.gold / tierTotal) * 100} color={GOLD} width={16} e={e} />
              <Ring r={88} pct={(tiers.silver / tierTotal) * 100} color={SILVER} width={16} e={e} />
              <Ring r={66} pct={(tiers.bronze / tierTotal) * 100} color={BRONZE} width={16} e={e} />
              <text y="-2" textAnchor="middle" fontSize="44" fontWeight="600" fill="var(--cc-ink-strong)" className="font-display">{int(data.crm.customers * e)}</text>
              <text y="22" textAnchor="middle" fontSize="11" letterSpacing="2" fill="var(--cc-muted)">CLIENTAS</text>
            </svg>
            <div className="flex min-w-[240px] flex-1 flex-col gap-4">
              <Title>Clientas · CRM</Title>
              <div className="grid grid-cols-2 gap-4">
                {[['nuevas en el periodo', int(data.crm.new_in_period)], ['altas en tienda (periodo)', int(data.crm.by_source.store ?? 0)],
                  ['con permiso de novedades', int(data.crm.marketing_consent)], ['puntos por liberar', int(pipe.held_points.points)]].map(([l, v]) => (
                  <div key={l} className="flex flex-col"><span className="font-display tabular text-3xl text-[var(--cc-ink-strong)]">{v}</span><span className="text-xs text-[var(--cc-muted)]">{l}</span></div>
                ))}
              </div>
              <div className="flex flex-wrap gap-4 text-[13px] text-[var(--cc-soft)]">
                {[[GOLD, 'Gold', tiers.gold], [SILVER, 'Silver', tiers.silver], [BRONZE, 'Bronze', tiers.bronze]].map(([c, l, n]) => (
                  <span key={l as string} className="inline-flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-full" style={{ background: c as string }} />{l} · {int(n as number)}</span>
                ))}
              </div>
            </div>
          </div>
          <div className="cc-panel flex min-w-0 flex-[1_1_320px] flex-col gap-3 p-7">
            <Title>Cumpleaños del mes</Title>
            {data.crm.birthdays === null ? (
              <>
                <p className="font-display cc-glow tabular text-6xl text-[var(--cc-ink-strong)]">{int(data.crm.birthdays_month)}</p>
                <p className="text-sm leading-relaxed text-[var(--cc-soft)]">clientas cumplen años este mes. {data.presentation ? 'Nombres protegidos en la vista de presentación.' : 'Los nombres solo los ven Carolina y Mario.'}</p>
              </>
            ) : data.crm.birthdays.length === 0 ? <Empty>No hay cumpleaños registrados lo que queda del mes.</Empty> : data.crm.birthdays.map((b) => (
              <div key={`${b.name}-${b.day}`} className="flex justify-between gap-3 border-t border-[var(--cc-line)] pt-2.5 text-sm">
                <span>{b.name}{b.size ? <span className="text-[var(--cc-faint)]"> · talla {b.size}</span> : null}</span>
                <span className="tabular font-mono text-[var(--cc-gold-text)]">{b.day}</span>
              </div>
            ))}
          </div>
        </section>

        {/* inventory + trust */}
        <section className="flex flex-wrap gap-6">
          <div className="cc-panel flex min-w-0 flex-[1_1_480px] flex-col gap-3 p-7">
            <Title>Inventario a precio de venta</Title>
            {data.inventory.length === 0 ? <Empty>Sin existencias registradas.</Empty> : data.inventory.map((i) => (
              <div key={i.name} className="flex justify-between gap-3 border-t border-[var(--cc-line)] pt-2.5 text-sm">
                <span className="font-medium">{i.name}</span>
                <span className="tabular text-[var(--cc-muted)]">{int(i.pairs)} pares · <strong className="text-[var(--cc-ink)]">{mxn(i.value)}</strong></span>
              </div>
            ))}
            <p className="text-xs text-[var(--cc-faint)]">Valor a precio de lista en MXN. El costo se agregará cuando exista en el sistema.</p>
          </div>
          <div className="cc-panel flex min-w-0 flex-[1_1_480px] flex-col gap-3 p-7">
            <Title>Por qué estos números son confiables</Title>
            {[
              ...data.trust.sources.map((s) => ({ ok: s.freshness === 'VERIFIED', t: `Tienda en línea (${s.target})`, b: s.freshness === 'VERIFIED' ? `Sincronizada · última ${s.last_success_at ? new Date(s.last_success_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' }) : '—'}` : s.freshness === 'STALE' ? 'Sincronización atrasada: revisar' : 'Sin verificar' })),
              { ok: true, t: 'Un solo registro de ventas', b: 'Tiendas, bazares y WooCommerce conciliados pedido por pedido (Commerce Facts).' },
              { ok: true, t: 'Monedas nunca mezcladas', b: 'México en MXN; Colombia y otras monedas se reportan aparte.' },
              { ok: data.trust.unresolved_lines === 0, t: 'Identidad de producto', b: data.trust.unresolved_lines === 0 ? 'Cada par vendido está ligado a su SKU canónico.' : `${int(data.trust.unresolved_lines)} líneas antiguas sin homologar (no se adivinan).` },
              { ok: true, t: 'Ventas pasadas marcadas', b: `${int(data.trust.historical_loads)} cargas de resumen histórico, separadas de las ventas pieza por pieza.` },
            ].map((x) => (
              <div key={x.t} className="flex gap-3 border-t border-[var(--cc-line)] pt-3">
                <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true" className="mt-0.5 flex-none" fill="none" stroke={x.ok ? MINT : 'var(--cc-warn)'} strokeWidth="2.2">
                  {x.ok ? <path d="M20 6 9 17l-5-5" /> : <path d="M12 8v5M12 17h.01" />}
                </svg>
                <div className="flex flex-col gap-0.5"><span className="text-[15px] font-semibold">{x.t}</span><span className="text-[13px] leading-snug text-[var(--cc-muted)]">{x.b}</span></div>
              </div>
            ))}
          </div>
        </section>

        <p className="text-center font-mono text-[11px] text-[var(--cc-faint)]">
          Generado {new Date(data.generated_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })} · periodo {data.from} → {data.to} · comparado con {data.prev_from} → {data.prev_to}
        </p>
      </main>
    </div>
  );
}
