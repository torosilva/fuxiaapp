import Link from 'next/link';
import { redirect } from 'next/navigation';
import { weeklyBoard } from '@/lib/weekly';
import { AgencyPhone, CardForm, MetricsForm } from './Forms';

// Pendientes de la semana (Q4: 200 pares en línea, oct–dic). One card per person; each edits only their own (the database
// decides whose card it is by the caller's WhatsApp). Online pairs are counted from sales, never typed.
const COLOR: Record<string, string> = { AGENCIA: '#1565a8', CAROLINA: '#c2185b', MARIO: '#6a4c93' };

export default async function Pendientes({ searchParams }: { searchParams: Promise<{ semana?: string }> }) {
  const sp = await searchParams;
  const b = await weeklyBoard(sp.semana);
  if (!b) redirect('/');
  const pct = Math.min(100, (b.goal.online_pairs / b.goal.target) * 100);
  const planPct = Math.min(100, (b.goal.plan_to_date / b.goal.target) * 100);
  const diff = b.goal.online_pairs - b.goal.plan_to_date;
  const left = b.goal.target - b.goal.online_pairs;
  return (
    <div className="flex flex-col gap-6">
      <div>
        <p className="kicker text-gold-strong">Q4 2026 · meta 200 pares en línea</p>
        <h1 className="font-display mt-1 text-5xl text-ink">Pendientes de la semana</h1>
      </div>

      <section className="atelier-card p-6">
        <div className="flex items-baseline gap-2"><b className="tabular text-5xl text-ink">{b.goal.online_pairs}</b><span className="text-muted">de {b.goal.target} pares en línea</span></div>
        <div className="relative mt-4 h-2.5 overflow-hidden rounded-full bg-line">
          <div className="h-full rounded-full bg-gold" style={{ width: `${pct}%` }} />
          <div className="absolute inset-y-[-3px] w-0.5 bg-ink/50" style={{ left: `${planPct}%` }} title="plan a hoy" />
        </div>
        <div className="mt-2 flex justify-between text-xs text-muted"><span>{Math.round(pct)}%</span><span>plan a hoy: {b.goal.plan_to_date}</span></div>
        <p className={`mt-3 text-sm font-semibold ${b.goal.plan_to_date === 0 ? 'text-muted' : diff >= 0 ? 'text-success' : 'text-danger'}`}>
          {b.goal.plan_to_date === 0 ? 'Aún no arranca el conteo de Q4.'
            : diff >= 0 ? `▲ ${diff} pares arriba del plan.`
            : `▼ ${-diff} abajo. Faltan ${left} pares en ${Math.max(1, b.goal.weeks_left)} semanas = ${Math.ceil(left / Math.max(1, b.goal.weeks_left))}/semana.`}
        </p>
        <p className="mt-1 text-xs text-muted">Se cuentan solos con las ventas en línea de Fuxia 360 (tienda en línea + ventas por WhatsApp).</p>
      </section>

      <nav className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {b.weeks.map((w) => (
          <Link key={w.id} href={`/pendientes?semana=${w.id}`}
            className={`shrink-0 rounded-xl px-3 py-2 text-xs font-semibold ${w.id === b.week.id ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>
            {w.label}{w.filled ? ' ✓' : ''}{w.current ? ' ·' : ''}
          </Link>
        ))}
      </nav>

      <section className="rounded-2xl bg-gold-soft px-5 py-4">
        <p className="kicker text-gold-strong">{b.week.label} · {b.week.title}</p>
        <p className="mt-1 text-ink">{b.week.focus}</p>
        <p className="mt-2 text-sm text-ink-2">
          Meta de la semana: <b>{b.week.target_pairs}</b> pares · reales: <b>{b.week.online.total}</b>
          <span className="text-muted"> (sitio {b.week.online.site} · WhatsApp/DM {b.week.online.dm})</span>
        </p>
      </section>

      {b.cards.map((c) => (
        <section key={c.person_key} className="atelier-card p-5" style={{ borderTop: `3px solid ${COLOR[c.person_key]}` }}>
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-semibold text-ink">{c.name}{c.mine && <span className="ml-2 rounded-full bg-gold-soft px-2 py-0.5 text-xs text-gold-strong">tu tarjeta</span>}</h2>
            {c.updated_at && <span className="text-xs text-muted">Actualizó {c.updated_by} · {new Date(c.updated_at).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}</span>}
          </div>
          <p className="text-sm text-muted">{c.role_line}</p>
          {c.person_key === 'AGENCIA' && <p className="mt-2 text-sm text-ink-2">Pares que el sitio cerró solo esta semana: <b className="tabular">{b.week.online.site}</b> <span className="text-muted">(se cuentan solos)</span></p>}
          {c.person_key === 'CAROLINA' && <p className="mt-2 text-sm text-ink-2">Pares por WhatsApp / DM esta semana: <b className="tabular">{b.week.online.dm}</b> <span className="text-muted">(se cuentan solos)</span></p>}
          <CardForm week={b.week.id} card={c} />
        </section>
      ))}

      <section className="atelier-card p-5">
        <h2 className="text-lg font-semibold text-ink">Los 5 números de la semana</h2>
        <p className="text-sm text-muted">Si estos no se mueven, lo demás fue actividad, no resultado. Los llenan Carolina o Mario.</p>
        <MetricsForm week={b.week.id} metrics={b.metrics} canEdit={b.me.can_edit_metrics} />
      </section>

      {b.me.team && <AgencyPhone />}

      <details className="text-sm text-ink-2">
        <summary className="cursor-pointer font-semibold text-gold-strong">Cómo se usa (2 min)</summary>
        <p className="mt-2"><b>Viernes:</b> cada quien llena su tarjeta de la semana que termina — compromiso, qué hizo, números.</p>
        <p className="mt-1"><b>Lunes 9:00, 20 minutos:</b> se lee en voz alta — 1) los 5 números, 2) cada tarjeta, 3) la decisión de la semana.</p>
        <p className="mt-1"><b>La regla dura:</b> si alguien marca «No» dos semanas seguidas en lo mismo, sube a decisión — se reasigna, se paga a alguien más o se elimina del plan.</p>
        <p className="mt-1"><b>Sin doble conteo:</b> si el sitio cerró solo, es de la agencia; si alguien tuvo que escribir, es de Carolina. Fuxia 360 ya los separa.</p>
      </details>
    </div>
  );
}
