'use client';
import { useState, useTransition } from 'react';
import type { AnalystResult, Answer, HistoryItem, Reco, Usage } from '@/lib/analyst';
import { askAction, setLimitsAction } from './actions';

const usd = (n: number) => `USD ${n.toLocaleString('es-MX', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fmt = (n: number) => n.toLocaleString('es-MX', { maximumFractionDigits: 2 });

function Source({ f }: { f: Answer['hechos'][number]['fuente'] }) {
  return (
    <span className="mt-1 flex flex-wrap gap-1 text-[11px] text-muted">
      <span className="rounded-full bg-surface-2 px-2 py-0.5">{f.fuente}</span>
      <span className="rounded-full bg-surface-2 px-2 py-0.5">{f.periodo}</span>
      {f.moneda && <span className="rounded-full bg-surface-2 px-2 py-0.5">{f.moneda}</span>}
      {f.actualizado && <span className="rounded-full bg-surface-2 px-2 py-0.5">actualizado {f.actualizado}</span>}
    </span>
  );
}

function RecoCard({ r, n, label }: { r: Reco; n?: number; label: string }) {
  return (
    <li className="rounded-2xl border border-line bg-surface p-4">
      <p className="text-[11px] font-semibold uppercase tracking-wide text-gold-strong">{label}{n ? ` ${n}` : ''} · opinión del analista</p>
      <p className="mt-1 font-semibold text-ink">{r.texto}</p>
      <dl className="mt-2 grid gap-1 text-sm text-ink-2 md:grid-cols-2">
        <div><dt className="text-xs text-muted">Evidencia</dt><dd>{r.evidencia}</dd></div>
        <div><dt className="text-xs text-muted">Impacto potencial</dt><dd>{r.impacto}</dd></div>
        <div><dt className="text-xs text-muted">Responsable sugerido</dt><dd>{r.responsable}</dd></div>
        <div><dt className="text-xs text-muted">Cómo medirlo</dt><dd>{r.medicion}</dd></div>
      </dl>
    </li>
  );
}

export function AnswerView({ a, unverified }: { a: Answer; unverified: AnalystResult['unverified'] }) {
  return (
    <div className="flex flex-col gap-4" data-testid="analyst-answer">
      <p className="text-lg text-ink">{a.resumen}</p>
      {unverified.length > 0 && (
        <p className="rounded-xl bg-danger-soft px-3 py-2 text-sm text-danger" data-testid="analyst-unverified">
          Ojo: {unverified.length} cifra(s) económicas presentadas como hecho o en el resumen no aparecen en los datos consultados ({unverified.map((u) => fmt(u.valor)).join(', ')}). No las uses sin revisar.
        </p>
      )}
      {a.validacion?.estado === 'incompleta' && (
        <p className="rounded-xl bg-danger-soft px-3 py-2 text-sm text-danger" data-testid="analyst-incomplete">
          Respuesta incompleta: {a.validacion.problemas.join('; ')}. Lo que no tiene fuente no cuenta como hecho verificado.
        </p>
      )}
      {a.formato === 'texto_libre' && <p className="text-xs text-muted">Respuesta sin estructura: nada de lo anterior cuenta como hecho verificado.</p>}
      {a.hechos.length > 0 && (
        <section><h3 className="text-sm font-semibold text-ink">Hechos</h3>
          <ul className="mt-2 flex flex-col gap-2">{a.hechos.map((h, i) => <li key={i} className="rounded-xl bg-surface-2 px-3 py-2 text-sm text-ink">{h.texto}<Source f={h.fuente} /></li>)}</ul>
        </section>
      )}
      {(a.sin_fuente?.length ?? 0) > 0 && (
        <section data-testid="analyst-sin-fuente"><h3 className="text-sm font-semibold text-danger">Sin fuente · no verificado</h3>
          <ul className="mt-2 flex flex-col gap-2">{a.sin_fuente!.map((h, i) => <li key={i} className="rounded-xl border border-danger/40 px-3 py-2 text-sm text-ink-2">{h.texto} <span className="text-xs text-muted">({h.motivo})</span></li>)}</ul>
        </section>
      )}
      {a.calculos.length > 0 && (
        <section><h3 className="text-sm font-semibold text-ink">Cálculos</h3>
          <ul className="mt-2 flex flex-col gap-2">{a.calculos.map((c, i) => (
            <li key={i} className="rounded-xl border border-line px-3 py-2 text-sm text-ink">{c.texto}<span className="mt-1 block font-mono text-[11px] text-muted">{c.formula}</span></li>))}</ul>
        </section>
      )}
      {(a.prioridades?.length ?? 0) > 0 && (
        <section><h3 className="text-sm font-semibold text-ink">Prioridades de la semana</h3>
          <ol className="mt-2 flex flex-col gap-2">{a.prioridades!.map((r, i) => <RecoCard key={i} r={r} n={i + 1} label="Prioridad" />)}</ol>
        </section>
      )}
      {a.recomendaciones.length > 0 && (
        <section><h3 className="text-sm font-semibold text-ink">Recomendaciones</h3>
          <ul className="mt-2 flex flex-col gap-2">{a.recomendaciones.map((r, i) => <RecoCard key={i} r={r} label="Recomendación" />)}</ul>
        </section>
      )}
      {a.faltantes.length > 0 && (
        <section><h3 className="text-sm font-semibold text-ink">Lo que falta para responder mejor</h3>
          <ul className="mt-2 list-disc pl-5 text-sm text-ink-2">{a.faltantes.map((f, i) => <li key={i}>{f.que} — <span className="text-muted">{f.quien}</span></li>)}</ul>
        </section>
      )}
    </div>
  );
}

export function Analyst({ preguntas, history, usage }: { preguntas: string[]; history: HistoryItem[]; usage: Usage | null }) {
  const [q, setQ] = useState('');
  const [res, setRes] = useState<AnalystResult | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const ask = (question: string, kind: 'pregunta' | 'prioridades') => start(async () => {
    setErr(null); setRes(null);
    const r = await askAction(question, kind);
    if (r.ok) setRes(r.data); else setErr(r.error);
  });
  const spent = usage?.month.costo_usd ?? 0; const budget = usage?.settings.monthly_budget_usd ?? 0;
  return (
    <div className="mt-6 flex flex-col gap-6">
      <div className="rounded-3xl border border-line bg-surface p-4 md:p-5">
        <button type="button" disabled={pending} onClick={() => ask('', 'prioridades')} data-testid="analyst-priorities"
          className="w-full rounded-2xl bg-ink px-4 py-3 text-left text-sm font-semibold text-surface disabled:opacity-50 md:w-auto">
          ★ Prioridades comerciales de esta semana
        </button>
        <form className="mt-4 flex flex-col gap-2" onSubmit={(e) => { e.preventDefault(); if (q.trim()) ask(q.trim(), 'pregunta'); }}>
          <label className="text-xs text-muted" htmlFor="analyst-q">Tu pregunta</label>
          <textarea id="analyst-q" value={q} onChange={(e) => setQ(e.target.value)} rows={3} maxLength={1500} data-testid="analyst-input"
            className="w-full rounded-2xl border border-line bg-bg px-3 py-2 text-sm text-ink" placeholder="Por ejemplo: ¿qué país creció más este mes?" />
          <button type="submit" disabled={pending || !q.trim()} className="self-start rounded-full bg-gold px-5 py-2 text-sm font-semibold text-ink disabled:opacity-50">
            {pending ? 'Consultando…' : 'Preguntar'}
          </button>
        </form>
        <div className="mt-4 flex flex-wrap gap-2" data-testid="analyst-suggestions">
          {preguntas.map((p) => (
            <button key={p} type="button" disabled={pending} onClick={() => { setQ(p); ask(p, 'pregunta'); }}
              className="rounded-full border border-line px-3 py-1.5 text-left text-xs text-ink-2 hover:bg-gold-soft disabled:opacity-50">{p}</button>
          ))}
        </div>
      </div>

      {err && <p className="rounded-2xl bg-danger-soft px-4 py-3 text-sm text-danger" data-testid="analyst-error">{err}</p>}
      {pending && <p className="text-sm text-muted">El analista está revisando los datos…</p>}
      {res && (
        <div className="rounded-3xl border border-line bg-surface p-4 md:p-6">
          <AnswerView a={res.answer} unverified={res.unverified} />
          <p className="mt-4 text-[11px] text-muted">
            Consultó: {res.tools.map((t) => `${t.tool}${t.disponibilidad && t.disponibilidad !== 'DISPONIBLE' ? ` (${t.disponibilidad.toLowerCase()})` : ''}`).join(', ') || 'ninguna fuente'} ·
            {' '}{res.usage.model} · {fmt(res.usage.input + res.usage.cacheRead)} tokens de entrada, {fmt(res.usage.output)} de salida · {usd(res.usage.cost_usd)}
          </p>
          {res.usage.warning && <p className="mt-1 text-xs text-danger">Ya se usó más del 80 % del presupuesto mensual de IA.</p>}
        </div>
      )}

      {usage && (
        <section className="rounded-3xl border border-line bg-surface p-4 md:p-5" data-testid="analyst-usage">
          <h2 className="text-lg font-semibold text-ink">Consumo de este mes</h2>
          <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-surface-2">
            <div className={`h-full ${spent >= 0.8 * budget ? 'bg-danger' : 'bg-gold'}`} style={{ width: `${Math.min(100, budget > 0 ? (spent / budget) * 100 : 0)}%` }} />
          </div>
          <p className="mt-2 text-sm text-ink-2">{usd(spent)} de {usd(budget)} · {usage.month.preguntas} preguntas · promedio {usd(usage.month.promedio_usd)} por pregunta</p>
          <p className="mt-1 text-xs text-muted">Modelo {usage.settings.model} · máximo {usage.settings.per_user_daily} preguntas por persona al día · precios: {usage.settings.prices_source}</p>
          {usage.can_change && <Limits usage={usage} />}
        </section>
      )}

      {history.length > 0 && (
        <section>
          <h2 className="text-lg font-semibold text-ink">Tus preguntas anteriores</h2>
          <ul className="mt-2 flex flex-col gap-2">
            {history.map((h) => (
              <li key={h.id} className="rounded-2xl border border-line bg-surface">
                <details className="px-4 py-3">
                  <summary className="cursor-pointer text-sm text-ink">{h.question} <span className="text-xs text-muted">· {new Date(h.at).toLocaleString('es-MX')} · {h.status}</span></summary>
                  {h.answer && <div className="mt-3"><AnswerView a={h.answer} unverified={h.unverified ?? []} /></div>}
                </details>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

function Limits({ usage }: { usage: Usage }) {
  const [budget, setBudget] = useState(String(usage.settings.monthly_budget_usd));
  const [daily, setDaily] = useState(String(usage.settings.per_user_daily));
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <form className="mt-4 grid gap-2 md:grid-cols-4" onSubmit={(e) => { e.preventDefault(); start(async () => {
      const r = await setLimitsAction({ monthly_budget_usd: Number(budget), per_user_daily: Number(daily) }, reason);
      setMsg(r.ok ? 'Guardado.' : r.error); if (r.ok) setReason('');
    }); }}>
      <label className="text-xs text-muted">Presupuesto mensual (USD)<input value={budget} onChange={(e) => setBudget(e.target.value)} inputMode="decimal" className="mt-1 w-full rounded-xl border border-line bg-bg px-2 py-1.5 text-sm text-ink" /></label>
      <label className="text-xs text-muted">Preguntas por persona al día<input value={daily} onChange={(e) => setDaily(e.target.value)} inputMode="numeric" className="mt-1 w-full rounded-xl border border-line bg-bg px-2 py-1.5 text-sm text-ink" /></label>
      <label className="text-xs text-muted md:col-span-2">Motivo del cambio<input value={reason} onChange={(e) => setReason(e.target.value)} className="mt-1 w-full rounded-xl border border-line bg-bg px-2 py-1.5 text-sm text-ink" /></label>
      <button type="submit" disabled={pending || reason.trim().length < 5} className="self-start rounded-full border border-line px-4 py-1.5 text-sm text-ink disabled:opacity-50">Cambiar límites</button>
      {msg && <p className="text-xs text-muted md:col-span-3">{msg}</p>}
    </form>
  );
}
