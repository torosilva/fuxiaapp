'use client';
import { useMemo, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import type { GrowthPlan, ReportedFigure, ScenarioKind } from '@/lib/f360';
import { computeGrowth, type GrowthInputs, type Split } from '@/lib/growth-model';
import { fecha } from '@/lib/format';
import { addReportedFigureAction, saveGrowthPlanAction, saveScenarioAction, setReportedFigureStatusAction } from '../actions';

const SUGGESTED_NORTH_STAR = 15_000_000;   // Mario's stated 2027 goal — a TARGET, not a forecast
const KINDS: { kind: ScenarioKind; label: string }[] = [{ kind: 'conservador', label: 'Conservador' }, { kind: 'base', label: 'Base' }, { kind: 'agresivo', label: 'Agresivo' }];
const mxn = (n: number | null | undefined) => (n == null ? '—' : `$${Math.round(n).toLocaleString('es-MX')}`);
const num = (n: number | null | undefined, d = 0) => (n == null ? '—' : n.toLocaleString('es-MX', { maximumFractionDigits: d, minimumFractionDigits: d }));
const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-base outline-none focus:border-gold tabular';
const STATUS_LABEL: Record<ReportedFigure['status'], string> = { reportada_no_verificada: 'Reportada, no verificada', verificada: 'Verificada', descartada: 'Descartada' };

type Form = Record<string, string>;
const NUM_FIELDS: { key: keyof GrowthInputs; label: string; hint: string }[] = [
  { key: 'active_customers', label: 'Clientas activas en el año', hint: 'clientas que compran al menos una vez' },
  { key: 'orders_per_customer', label: 'Compras por clienta al año', hint: 'frecuencia, p. ej. 1.4' },
  { key: 'aov', label: 'Ticket promedio (AOV, MXN)', hint: 'valor promedio por pedido' },
];
const PCT_FIELDS: { key: keyof GrowthInputs; label: string }[] = [
  { key: 'ecommerce_pct', label: '% ecommerce' }, { key: 'retail_pct', label: '% tiendas físicas' },
  { key: 'shoes_pct', label: '% zapatos' }, { key: 'accessories_pct', label: '% accesorios' },
  { key: 'new_pct', label: '% nuevas clientas' }, { key: 'returning_pct', label: '% recurrentes' },
];

function toForm(i: GrowthInputs | undefined): Form {
  const f: Form = {};
  for (const { key } of [...NUM_FIELDS, ...PCT_FIELDS]) f[key] = i?.[key] == null ? '' : String(i[key]);
  f.regions = (i?.regions ?? []).map((r) => `${r.name}: ${r.pct}`).join('\n');
  return f;
}
function toInputs(f: Form): { inputs: GrowthInputs; error: string | null } {
  const inputs: GrowthInputs = {};
  for (const { key } of [...NUM_FIELDS, ...PCT_FIELDS]) {
    const raw = (f[key] ?? '').replace(/[$,\s]/g, '');
    if (raw === '') continue;
    const n = Number(raw);
    if (!Number.isFinite(n) || n < 0) return { inputs, error: `Revisa el valor de “${[...NUM_FIELDS, ...PCT_FIELDS].find((x) => x.key === key)!.label}”.` };
    (inputs as Record<string, number>)[key] = n;
  }
  const regions = (f.regions ?? '').split('\n').map((l) => l.trim()).filter(Boolean).map((l) => {
    const m = l.match(/^(.+?)\s*[:=]\s*([\d.]+)\s*%?$/); return m ? { name: m[1].trim(), pct: Number(m[2]) } : null;
  });
  if (regions.some((r) => !r)) return { inputs, error: 'Escribe cada región como “CDMX: 40”.' };
  // same rules as the database (f360.validate_growth_inputs), shown while typing
  for (const [a, b, label] of [['ecommerce_pct', 'retail_pct', 'Ecommerce + tiendas físicas'], ['shoes_pct', 'accessories_pct', 'Zapatos + accesorios'], ['new_pct', 'returning_pct', 'Nuevas + recurrentes']] as const) {
    if ((inputs[a] ?? 0) + (inputs[b] ?? 0) > 100) return { inputs, error: `${label} suman más de 100%.` };
    if ((inputs[a] ?? 0) > 100 || (inputs[b] ?? 0) > 100) return { inputs, error: 'Un porcentaje no puede pasar de 100.' };
  }
  if ((regions as { pct: number }[]).reduce((t, r) => t + r.pct, 0) > 100) return { inputs, error: 'Las regiones suman más de 100%.' };
  if (regions.length) inputs.regions = regions as { name: string; pct: number }[];
  return { inputs, error: null };
}

export function PlanEditor({ data }: { data: GrowthPlan }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [ns, setNs] = useState(String(data.plan?.north_star ?? SUGGESTED_NORTH_STAR));
  const [note, setNote] = useState(data.plan?.note ?? '');
  const [kind, setKind] = useState<ScenarioKind>('base');
  const [forms, setForms] = useState<Record<ScenarioKind, Form>>({
    conservador: toForm(data.scenarios.conservador?.inputs), base: toForm(data.scenarios.base?.inputs), agresivo: toForm(data.scenarios.agresivo?.inputs),
  });
  const northStar = data.plan?.north_star ?? null;
  const form = forms[kind];
  const parsed = useMemo(() => toInputs(form), [form]);
  const result = northStar ? computeGrowth(northStar, parsed.inputs) : null;
  const edit = data.can_edit;
  const run = (fn: () => Promise<{ ok: boolean; error?: string }>) => start(async () => { setError(null); const r = await fn(); if (!r.ok) setError(r.error ?? 'No se pudo guardar.'); router.refresh(); });

  return (
    <div className="mt-6 space-y-8">
      {/* North Star */}
      <section className="rounded-3xl border border-line bg-surface p-5 md:p-6" data-testid="north-star">
        <p className="text-sm uppercase tracking-[0.15em] text-muted">Objetivo anual {data.year} (North Star)</p>
        {northStar ? (
          <>
            <p className="font-display mt-1 text-5xl text-ink tabular">{mxn(northStar)} <span className="text-lg text-muted">MXN</span></p>
            <p className="mt-1 text-sm text-muted">Es un objetivo, no un pronóstico. {data.plan?.note}</p>
            <div className="mt-4 grid gap-3 sm:grid-cols-3">
              <div className="rounded-2xl bg-surface-2 p-4"><p className="text-xs text-muted">Objetivo mensual (parejo)</p><p className="text-xl text-ink tabular">{mxn(northStar / 12)}</p></div>
              <div className="rounded-2xl bg-surface-2 p-4" data-testid="actual"><p className="text-xs text-muted">Actual vs objetivo</p><p className="text-ink">Sin datos confiables todavía</p></div>
              <div className="rounded-2xl bg-surface-2 p-4"><p className="text-xs text-muted">Definido por</p><p className="text-ink">{data.plan?.updated_by_name}, {data.plan ? fecha(data.plan.updated_at) : ''}</p></div>
            </div>
          </>
        ) : <p className="mt-2 text-ink-2">Todavía no se ha definido el objetivo de {data.year}.</p>}
        {edit && (
          <div className="mt-5 grid gap-3 md:grid-cols-[220px_1fr_auto] md:items-end">
            <label className="text-sm text-ink-2">Objetivo anual (MXN)<input value={ns} onChange={(e) => setNs(e.target.value)} inputMode="numeric" className={field} aria-label="Objetivo anual" /></label>
            <label className="text-sm text-ink-2">Nota<input value={note} onChange={(e) => setNote(e.target.value)} placeholder="p. ej. meta 2027 definida por Mario" className={field} /></label>
            <button type="button" disabled={pending} onClick={() => run(() => saveGrowthPlanAction(data.year, Number(ns.replace(/[$,\s]/g, '')), note))}
              className="rounded-xl bg-ink px-5 py-3 text-surface disabled:opacity-60">{northStar ? 'Actualizar objetivo' : 'Guardar objetivo'}</button>
          </div>
        )}
      </section>

      {/* Scenarios */}
      {northStar && (
        <section>
          <h2 className="font-display text-3xl text-ink">Escenarios</h2>
          <p className="mt-1 text-sm text-muted">Clientas activas × compras por clienta × ticket promedio = revenue. Todos los valores son supuestos que escribes tú; nada se rellena solo.</p>
          <div className="mt-4 flex gap-2">
            {KINDS.map((k) => (
              <button key={k.kind} type="button" onClick={() => setKind(k.kind)} aria-pressed={kind === k.kind}
                className={`rounded-full px-5 py-2.5 ${kind === k.kind ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`}>
                {k.label}{data.scenarios[k.kind] ? '' : ' · vacío'}
              </button>
            ))}
          </div>
          <div className="mt-4 grid gap-6 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)]">
            <div className="rounded-3xl border border-line bg-surface p-5" data-testid="scenario-inputs">
              <p className="text-sm uppercase tracking-[0.15em] text-muted">Supuestos</p>
              {NUM_FIELDS.map((f) => (
                <label key={f.key} className="mt-3 block text-sm text-ink-2">{f.label}
                  <input value={form[f.key] ?? ''} disabled={!edit} placeholder={f.hint} inputMode="decimal" aria-label={f.label}
                    onChange={(e) => setForms({ ...forms, [kind]: { ...form, [f.key]: e.target.value } })} className={field} />
                </label>
              ))}
              <p className="mt-5 text-sm uppercase tracking-[0.15em] text-muted">Mezcla del objetivo (%)</p>
              <div className="mt-1 grid grid-cols-2 gap-3">
                {PCT_FIELDS.map((f) => (
                  <label key={f.key} className="block text-sm text-ink-2">{f.label}
                    <input value={form[f.key] ?? ''} disabled={!edit} inputMode="decimal" aria-label={f.label}
                      onChange={(e) => setForms({ ...forms, [kind]: { ...form, [f.key]: e.target.value } })} className={field} />
                  </label>
                ))}
              </div>
              <label className="mt-3 block text-sm text-ink-2">Ciudad / estado (una por línea, “CDMX: 40”)
                <textarea value={form.regions ?? ''} disabled={!edit} rows={3} aria-label="Regiones"
                  onChange={(e) => setForms({ ...forms, [kind]: { ...form, regions: e.target.value } })} className={field} />
              </label>
              {(parsed.error || error) && <p role="alert" className="mt-3 rounded-xl bg-danger-soft px-3 py-2 text-sm text-danger">{parsed.error ?? error}</p>}
              {edit && <button type="button" disabled={pending || !!parsed.error} onClick={() => run(() => saveScenarioAction(data.year, kind, parsed.inputs as Record<string, unknown>))}
                className="mt-4 w-full rounded-xl bg-ink py-3 text-surface disabled:opacity-60">{pending ? 'Guardando…' : `Guardar escenario ${KINDS.find((k) => k.kind === kind)!.label}`}</button>}
              {data.scenarios[kind] && <p className="mt-2 text-xs text-muted">Guardado por {data.scenarios[kind]!.updated_by_name}, {fecha(data.scenarios[kind]!.updated_at)}</p>}
            </div>

            {result && (
              <div className="space-y-4" data-testid="scenario-results">
                <div className={`rounded-3xl border p-5 ${result.reachesTarget == null ? 'border-line bg-surface' : result.reachesTarget ? 'border-success/30 bg-success-soft' : 'border-gold/40 bg-gold-soft/60'}`}>
                  <p className="text-sm uppercase tracking-[0.15em] text-muted">Con estos supuestos</p>
                  {result.modeledRevenue == null
                    ? <p className="mt-2 text-ink-2">Escribe clientas activas, compras por clienta y ticket promedio para calcular el revenue del escenario.</p>
                    : <>
                        <p className="font-display mt-1 text-4xl text-ink tabular">{mxn(result.modeledRevenue)}</p>
                        <p className="mt-1 text-ink-2">{result.reachesTarget ? `Supera el objetivo por ${mxn(-result.gap!)}` : `Faltan ${mxn(result.gap)} para el objetivo`}</p>
                      </>}
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <Metric label="Clientas necesarias" value={num(result.customersNeeded)} hint="con la frecuencia y el ticket del escenario" />
                  <Metric label="Pedidos necesarios" value={num(result.ordersNeeded)} hint="con el ticket del escenario" />
                  <Metric label="Ticket requerido" value={mxn(result.aovRequired)} hint="con las clientas y la frecuencia del escenario" />
                  <Metric label="Frecuencia requerida" value={num(result.frequencyRequired, 2)} hint="compras por clienta al año" />
                </div>
                <Breakdown title="Objetivo por canal" rows={result.channel} />
                <Breakdown title="Objetivo por categoría" rows={result.category} />
                <Breakdown title="Objetivo por tipo de clienta" rows={result.customerType} />
                <Breakdown title="Objetivo por ciudad / estado" rows={result.regions} />
              </div>
            )}
          </div>
        </section>
      )}

      <ReportedFigures data={data} />

      {data.changes.length > 0 && (
        <section>
          <h2 className="text-lg text-ink">Cambios recientes al plan</h2>
          <ul className="mt-2 space-y-1 text-sm text-ink-2">{data.changes.map((c, i) => <li key={i}>{c.by} cambió {c.what.replace('scenario:', 'escenario ').replace('north_star', 'el objetivo')} · {fecha(c.at)}</li>)}</ul>
        </section>
      )}
    </div>
  );
}

function Metric({ label, value, hint }: { label: string; value: string; hint: string }) {
  return <div className="rounded-2xl border border-line bg-surface p-4"><p className="text-xs text-muted">{label}</p><p className="text-2xl text-ink tabular">{value}</p><p className="text-xs text-muted">{hint}</p></div>;
}

function Breakdown({ title, rows }: { title: string; rows: Split[] }) {
  if (!rows.length || rows.every((r) => r.pct == null)) return <div className="rounded-2xl border border-dashed border-line p-4 text-sm text-muted">{title}: sin supuestos todavía</div>;
  return (
    <div className="rounded-2xl border border-line bg-surface p-4">
      <p className="text-sm text-ink">{title}</p>
      <ul className="mt-2 space-y-1 text-sm">{rows.map((r) => (
        <li key={r.label} className="flex justify-between gap-3 tabular"><span className={r.label === 'Sin asignar' ? 'text-muted' : 'text-ink-2'}>{r.label} {r.pct != null ? `(${num(r.pct, 1)}%)` : ''}</span><span className="text-ink">{r.amount == null ? '—' : mxn(r.amount)}</span></li>
      ))}</ul>
    </div>
  );
}

function ReportedFigures({ data }: { data: GrowthPlan }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [open, setOpen] = useState(false);
  const [f, setF] = useState({ period: '2025', value: '', scope: '', source: '', note: '' });
  const [error, setError] = useState<string | null>(null);
  const [verifying, setVerifying] = useState<{ id: string; status: string; note: string } | null>(null);
  return (
    <section data-testid="reported-figures">
      <h2 className="font-display text-3xl text-ink">Cifras reportadas</h2>
      <p className="mt-1 max-w-3xl text-sm text-muted">Cifras que alguien nos compartió (por ejemplo, revenue de años anteriores). No son datos medidos por Fuxia 360: se guardan con su fuente y alcance, y solo cuentan como hechos cuando se verifican.</p>
      <div className="mt-4 space-y-2">
        {data.reported_figures.length === 0 && <p className="rounded-2xl border border-dashed border-line bg-surface p-4 text-sm text-ink-2">Ninguna cifra registrada.</p>}
        {data.reported_figures.map((r) => (
          <div key={r.id} className="rounded-2xl border border-line bg-surface p-4">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <p className="text-ink">Revenue {r.period}: <span className="tabular">{mxn(r.value)}</span> MXN</p>
              <span className={`rounded-full px-2.5 py-0.5 text-xs ${r.status === 'verificada' ? 'bg-success-soft text-success' : r.status === 'descartada' ? 'bg-surface-2 text-muted' : 'bg-gold-soft text-ink-2'}`}>{STATUS_LABEL[r.status]}</span>
            </div>
            <p className="mt-1 text-sm text-ink-2">Alcance: {r.scope} · Fuente: {r.source}</p>
            {r.status_note && <p className="mt-1 text-xs text-muted">{r.status_by_name}: “{r.status_note}”</p>}
            {data.can_edit && r.status === 'reportada_no_verificada' && (verifying?.id === r.id ? (
              <div className="mt-2 flex flex-wrap gap-2">
                <input value={verifying.note} onChange={(e) => setVerifying({ ...verifying, note: e.target.value })} placeholder="¿Cómo se verificó / por qué se descarta?" className="flex-1 rounded-xl border border-line bg-bg px-3 py-2" />
                <button type="button" disabled={pending} onClick={() => start(async () => { const x = await setReportedFigureStatusAction(r.id, verifying.status, verifying.note); if (!x.ok) setError(x.error); else setVerifying(null); router.refresh(); })} className="rounded-xl bg-ink px-4 py-2 text-surface">Guardar</button>
              </div>
            ) : (
              <div className="mt-2 flex gap-3 text-sm">
                <button type="button" onClick={() => setVerifying({ id: r.id, status: 'verificada', note: '' })} className="text-gold-strong hover:underline">Marcar verificada</button>
                <button type="button" onClick={() => setVerifying({ id: r.id, status: 'descartada', note: '' })} className="text-muted hover:underline">Descartar</button>
              </div>
            ))}
          </div>
        ))}
      </div>
      {data.can_edit && (open ? (
        <div className="mt-3 grid gap-3 rounded-2xl border border-line bg-surface p-4 md:grid-cols-2">
          <label className="text-sm text-ink-2">Año<input value={f.period} onChange={(e) => setF({ ...f, period: e.target.value })} className={field} /></label>
          <label className="text-sm text-ink-2">Revenue (MXN)<input value={f.value} onChange={(e) => setF({ ...f, value: e.target.value })} inputMode="numeric" className={field} /></label>
          <label className="text-sm text-ink-2">Qué incluye (canales, con/sin IVA, neto de devoluciones…)<input value={f.scope} onChange={(e) => setF({ ...f, scope: e.target.value })} className={field} /></label>
          <label className="text-sm text-ink-2">Fuente (quién / qué documento)<input value={f.source} onChange={(e) => setF({ ...f, source: e.target.value })} className={field} /></label>
          {error && <p role="alert" className="text-sm text-danger md:col-span-2">{error}</p>}
          <div className="flex gap-3 md:col-span-2">
            <button type="button" disabled={pending} onClick={() => start(async () => {
              setError(null);
              const x = await addReportedFigureAction({ ...f, value: Number(f.value.replace(/[$,\s]/g, '')) });
              if (!x.ok) { setError(x.error); return; }
              setOpen(false); router.refresh();
            })} className="rounded-xl bg-ink px-4 py-2.5 text-surface">Registrar como “no verificada”</button>
            <button type="button" onClick={() => setOpen(false)} className="px-3 text-muted">Cancelar</button>
          </div>
        </div>
      ) : <button type="button" onClick={() => setOpen(true)} className="mt-3 text-sm text-gold-strong hover:underline">+ Registrar una cifra reportada</button>)}
    </section>
  );
}
