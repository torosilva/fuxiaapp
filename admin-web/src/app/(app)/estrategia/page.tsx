import Link from 'next/link';
import { notFound } from 'next/navigation';
import { MONTHS, STATUS_LABEL, getBoardAccessLog, getBoardMe, getBoardMetrics, getBoardPeriods, getBoardPlans } from '@/lib/board';

// SB0 foundation view: who is in, the fiscal calendar and its closes, the Plan 2027 target (DRAFT, from Growth B4), the metric
// vocabulary with today's availability and the access log. It is NOT the CEO Cockpit (SB1): no KPI is computed here.
const money = (n: number | null, c = 'MXN') => (n === null ? '—' : `${new Intl.NumberFormat('es-MX', { maximumFractionDigits: 0 }).format(n)} ${c}`);
const when = (s: string) => new Date(s).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', dateStyle: 'short', timeStyle: 'short' });
const chip = (s: string) => `rounded-full px-2.5 py-0.5 text-xs font-semibold ${
  s === 'CLOSED' || s === 'AVAILABLE' || s === 'allowed' ? 'bg-emerald-100 text-emerald-900'
  : s === 'UNDER_REVIEW' || s === 'PARTIAL' || s === 'write' ? 'bg-amber-100 text-amber-900'
  : s === 'denied' || s === 'MISSING' ? 'bg-rose-100 text-rose-900' : 'bg-stone-100 text-stone-700'}`;

export default async function Estrategia({ searchParams }: { searchParams: Promise<{ anio?: string }> }) {
  const sp = await searchParams;
  const year = [2026, 2027].includes(Number(sp.anio)) ? Number(sp.anio) : undefined;
  const [me, periods, plans, metrics, log] = await Promise.all([getBoardMe(), getBoardPeriods(year), getBoardPlans(), getBoardMetrics(), getBoardAccessLog(30)]);
  if (!me.ok || !periods.ok || !plans.ok || !metrics.ok || !log.ok) notFound();
  const count = (a: string) => metrics.metrics.filter((m) => m.availability === a).length;
  return (
    <div className="flex flex-col gap-8">
      <header className="flex flex-col gap-2">
        <h1 className="font-display text-5xl text-ink">Strategy &amp; Board</h1>
        <p className="max-w-3xl text-ink-2">Base de dirección (SB0): acceso, calendario fiscal, cierre de mes, plan y registro de accesos. Nada aquí es un dato inventado: lo que falta se dice <b>DATA INCOMPLETE</b>.</p>
        <nav className="flex flex-wrap gap-2 text-sm"><Link href="/estrategia/participacion" className="rounded-full border border-line px-3 py-1 text-ink-2 hover:border-gold/40">Participación · earn-in →</Link></nav>
      </header>

      <section className="grid gap-4 md:grid-cols-2">
        <div className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Consejo</h2>
          <p className="mt-1 text-sm text-ink-2">Miembros: {me.members.map((m) => m.display_name).join(' y ')}. Tus áreas: {me.me.scopes.join(', ')}.</p>
          <ul className="mt-2 text-sm text-muted">
            <li>Año fiscal: {me.settings.fiscal_year} · {me.settings.timezone}</li>
            <li>Cierre: {me.settings.close_requires_second_member ? 'lo aprueba la otra persona del consejo' : 'cualquiera'}</li>
            <li>Decisiones: {me.settings.decision_requires_other_member ? 'las aprueba alguien distinto a quien propone' : 'cualquiera'}; con conflicto de interés, solo el miembro independiente</li>
            <li>MFA obligatorio: {me.settings.require_aal2 ? 'sí (verificación en dos pasos)' : 'no'}</li>
          </ul>
        </div>
        <div className="rounded-2xl border border-line bg-surface p-5">
          <h2 className="font-semibold text-ink">Plan · {plans.label}</h2>
          {plans.plans.length === 0 && <p className="mt-1 text-sm text-muted">Sin plan registrado.</p>}
          {plans.plans.map((p) => (
            <div key={p.id} className="mt-2 text-sm">
              <div className="text-ink-2">{p.name} · <span className={chip(p.status)}>{p.status}</span></div>
              {p.years.map((y) => (
                <div key={y.year} className="mt-1 flex flex-wrap items-baseline gap-2">
                  <span className="font-display text-3xl text-ink">{y.year}: {money(y.revenue_target, y.currency)}</span>
                  <span className="text-xs text-muted">meta DRAFT · fuente {y.source}{y.imported_value !== null && y.imported_value !== y.revenue_target ? ` · al importar: ${money(y.imported_value, y.currency)}` : ''}</span>
                </div>
              ))}
            </div>
          ))}
          <p className="mt-2 text-xs text-muted">La meta 2027 se edita en Growth (una sola fuente). No es pronóstico ni resultado real.</p>
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="font-semibold text-ink">Periodos fiscales {periods.fiscal_year}</h2>
          <nav className="flex gap-2 text-sm">{[2026, 2027].map((y) => <Link key={y} href={`/estrategia?anio=${y}`} className={`rounded-full px-3 py-1 ${y === periods.fiscal_year ? 'bg-ink text-surface' : 'border border-line text-ink-2'}`}>{y}</Link>)}</nav>
        </div>
        <p className="mt-1 text-xs text-muted">{periods.rule}</p>
        <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
          {periods.months.map((m) => (
            <Link key={m.id} href={`/estrategia/cierre/${m.id}`} className="rounded-xl border border-line p-3 text-sm hover:border-gold/40" data-testid={`period-${m.month}`}>
              <div className="capitalize text-ink">{MONTHS[m.month - 1]}</div>
              <span className={chip(m.status)}>{STATUS_LABEL[m.status]}{m.close_version > 0 ? ` · v${m.close_version}` : ''}</span>
              <div className="mt-1 text-xs text-muted">{m.entries} capturas{m.pending_approval ? ` · ${m.pending_approval} por aprobar` : ''}</div>
            </Link>
          ))}
        </div>
        <div className="mt-3 flex flex-wrap gap-2 text-xs text-ink-2">
          {periods.rollups.map((r) => <span key={`${r.kind}${r.no}`} className={chip(r.status)}>{r.kind === 'YEAR' ? `Año ${periods.fiscal_year}` : `T${r.no}`}: {r.months_closed}/{r.months_total} meses cerrados</span>)}
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-5">
        <h2 className="font-semibold text-ink">Catálogo de métricas · disponibles hoy {count('AVAILABLE')} · parciales {count('PARTIAL')} · faltan {count('MISSING')}</h2>
        <div className="mt-3 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-muted"><tr><th className="py-1 pr-3">Métrica</th><th className="pr-3">Estado</th><th className="pr-3">Fuente</th><th>Por qué</th></tr></thead>
            <tbody>{metrics.metrics.map((m) => (
              <tr key={m.metric_key} className="border-t border-line align-top"><td className="py-1.5 pr-3 text-ink">{m.label}</td><td className="pr-3"><span className={chip(m.availability)}>{m.availability}</span></td>
                <td className="pr-3 text-xs text-ink-2">{m.source_kind} · {m.source_ref}</td><td className="text-xs text-muted">{m.availability_reason}</td></tr>
            ))}</tbody>
          </table>
        </div>
      </section>

      <section className="rounded-2xl border border-line bg-surface p-5">
        <h2 className="font-semibold text-ink">Registro de accesos (30 días)</h2>
        <p className="mt-1 text-sm text-ink-2">Permitidos {log.summary.allowed} · escrituras {log.summary.writes} · negados {log.summary.denied}
          {log.summary.denied_non_members > 0 && <span className="ml-2 font-semibold text-rose-800">⚠ {log.summary.denied_non_members} intentos de personas fuera del consejo</span>}</p>
        <div className="mt-3 overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-xs uppercase text-muted"><tr><th className="py-1 pr-3">Cuándo</th><th className="pr-3">Quién</th><th className="pr-3">Qué</th><th className="pr-3">Resultado</th><th>Motivo</th></tr></thead>
            <tbody>{log.rows.slice(0, 40).map((r) => (
              <tr key={r.id} className="border-t border-line"><td className="py-1 pr-3 text-xs text-muted">{when(r.at)}</td><td className="pr-3">{r.who}{r.member ? '' : ' (no miembro)'}</td>
                <td className="pr-3 text-xs text-ink-2">{r.rpc} · {r.scope}</td><td className="pr-3"><span className={chip(r.outcome)}>{r.outcome}</span></td><td className="text-xs text-muted">{r.reason ?? ''}</td></tr>
            ))}</tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
