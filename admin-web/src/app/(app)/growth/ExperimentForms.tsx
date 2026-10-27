'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { KPI, PARTY, type Experiment, type Party } from '@/lib/growth-p0-labels';
import { saveExperimentAction, transitionExperimentAction } from './experimentos-actions';

// Growth → Experimentos: one-screen draft form and the state buttons. The database re-checks everything.
const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-base outline-none focus:border-gold';
const lbl = 'text-xs font-semibold text-ink-2';

export function ExperimentDraft({ exp }: { exp?: Experiment }) {
  const [open, setOpen] = useState(!!exp);
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  if (!open) return <button type="button" className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface" onClick={() => setOpen(true)} data-testid="exp-new">Nuevo experimento</button>;
  const t = (x: Experiment['success_threshold']) => x ? `${x.op} ${x.value} · muestra ${x.min_sample}` : '';
  return (
    <form className="atelier-card mt-2 grid gap-3 rounded-[20px] p-5 md:grid-cols-2" data-testid="exp-form"
      onSubmit={(ev) => {
        ev.preventDefault();
        const f = new FormData(ev.currentTarget);
        const s = (k: string) => String(f.get(k) ?? '').trim();
        const thr = (k: string) => {
          const m = /^(>=|<=)\s*([\d.]+)\s*·?\s*muestra\s*(\d+)$/.exec(s(k));
          return s(k) ? (m ? { op: m[1], value: Number(m[2]), min_sample: Number(m[3]) } : 'mal') : null;
        };
        const success = thr('success'); const kill = thr('kill');
        if (success === 'mal' || kill === 'mal') { setErr('Escribe los umbrales así: ">= 5 · muestra 3" o "<= 800 · muestra 2".'); return; }
        const payload: Record<string, unknown> = {
          name: s('name'), hypothesis: s('hypothesis'), market: s('market'), primary_variable: s('primary_variable'), proposed_by: s('proposed_by'),
          responsible: s('responsible'), responsible_note: s('responsible_note') || null, primary_kpi: s('primary_kpi'), channel: s('channel') || null,
          audience: s('audience') || null, start_date: s('start_date') || null, end_date: s('end_date') || null,
          budget: s('budget') ? Number(s('budget')) : null, budget_currency: s('budget') ? s('budget_currency') : null,
          success_threshold: success, kill_threshold: kill,
          campaign_ids: s('campaign_ids') ? s('campaign_ids').split(/[\s,]+/).filter(Boolean) : [],
        };
        start(async () => {
          setErr(null);
          const r = await saveExperimentAction(exp?.id ?? null, payload);
          if (r.ok) { if (!exp) setOpen(false); router.refresh(); } else setErr(r.error);
        });
      }}>
      <label className="md:col-span-2"><span className={lbl}>Nombre</span><input name="name" required defaultValue={exp?.name} className={field} /></label>
      <label className="md:col-span-2"><span className={lbl}>Hipótesis (antes de gastar): “Si hacemos X para Y en Z, esperamos que W pase de A a B”</span>
        <textarea name="hypothesis" required minLength={20} rows={3} defaultValue={exp?.hypothesis} className={field} /></label>
      <label><span className={lbl}>Qué cambia (una sola variable)</span><input name="primary_variable" required defaultValue={exp?.primary_variable} className={field} placeholder="oferta, creativo, audiencia, objetivo…" /></label>
      <label><span className={lbl}>Mercado</span><select name="market" defaultValue={exp?.market ?? 'MX'} className={field}><option value="MX">México</option><option value="CO">Colombia</option><option value="ROW">Resto</option><option value="ALL">Todos</option></select></label>
      <label><span className={lbl}>Lo propone</span><PartySelect name="proposed_by" value={exp?.proposed_by} /></label>
      <label><span className={lbl}>Responsable de ejecutarlo</span><PartySelect name="responsible" value={exp?.responsible} /></label>
      <label><span className={lbl}>Nota del responsable (opcional)</span><input name="responsible_note" defaultValue={exp?.responsible_note ?? ''} className={field} /></label>
      <label><span className={lbl}>Canal / audiencia (opcional)</span><input name="channel" defaultValue={exp?.channel ?? ''} className={field} placeholder="Meta pagado, Instagram orgánico…" /></label>
      <input type="hidden" name="audience" defaultValue={exp?.audience ?? ''} />
      <label><span className={lbl}>Inicio</span><input type="date" name="start_date" defaultValue={exp?.start_date ?? ''} className={field} /></label>
      <label><span className={lbl}>Fecha de revisión (fin)</span><input type="date" name="end_date" defaultValue={exp?.end_date ?? ''} className={field} /></label>
      <label><span className={lbl}>Presupuesto (puede ser 0)</span><input name="budget" inputMode="decimal" defaultValue={exp?.budget ?? ''} className={field} /></label>
      <label><span className={lbl}>Moneda</span><select name="budget_currency" defaultValue={exp?.budget_currency ?? 'MXN'} className={field}><option>MXN</option><option>COP</option><option>USD</option></select></label>
      <label><span className={lbl}>Cómo se mide (siempre con ventas pagadas)</span>
        <select name="primary_kpi" defaultValue={exp?.primary_kpi ?? 'paid_orders'} className={field}>{Object.entries(KPI).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <label><span className={lbl}>Campañas de Meta (IDs, opcional; el costo por venta las necesita)</span><input name="campaign_ids" defaultValue={exp?.campaign_ids.join(', ')} className={field} /></label>
      <label><span className={lbl}>Meta de éxito, p. ej. “&gt;= 5 · muestra 3”</span><input name="success" defaultValue={t(exp?.success_threshold ?? null)} className={field} /></label>
      <label><span className={lbl}>Criterio para cancelar, p. ej. “&lt;= 0 · muestra 1”</span><input name="kill" defaultValue={t(exp?.kill_threshold ?? null)} className={field} /></label>
      <div className="flex items-center gap-3 md:col-span-2">
        <button disabled={pending} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar borrador'}</button>
        {!exp && <button type="button" className="text-sm text-muted underline" onClick={() => setOpen(false)}>Cancelar</button>}
        <span className="text-xs text-muted">Al aprobarse ya no se puede cambiar nada: hipótesis, responsable, presupuesto, metas y fechas quedan fijos.</span>
      </div>
      {err && <p className="text-sm text-danger md:col-span-2">{err}</p>}
    </form>
  );
}

function PartySelect({ name, value }: { name: string; value?: Party }) {
  return <select name={name} defaultValue={value ?? 'mario'} className={field}>{(Object.keys(PARTY) as Party[]).map((p) => <option key={p} value={p}>{PARTY[p]}</option>)}</select>;
}

const NEXT: Record<string, { to: string; label: string; owner?: boolean; needs?: 'learning' | 'reason' | 'decision' }[]> = {
  DRAFT: [{ to: 'APPROVED', label: 'Aprobar (fija todo)', owner: true }],
  APPROVED: [{ to: 'RUNNING', label: 'Empezar' }, { to: 'STOPPED', label: 'Detener', needs: 'reason' }],
  RUNNING: [{ to: 'WINNER', label: 'Cerrar: ganó', owner: true, needs: 'learning' }, { to: 'LOSER', label: 'Cerrar: perdió', owner: true, needs: 'learning' },
    { to: 'INCONCLUSIVE', label: 'Cerrar: sin conclusión', owner: true, needs: 'learning' }, { to: 'STOPPED', label: 'Detener', needs: 'reason' }],
  WINNER: [{ to: 'ARCHIVED', label: 'Archivar con decisión', owner: true, needs: 'decision' }], LOSER: [{ to: 'ARCHIVED', label: 'Archivar con decisión', owner: true, needs: 'decision' }],
  INCONCLUSIVE: [{ to: 'ARCHIVED', label: 'Archivar con decisión', owner: true, needs: 'decision' }], STOPPED: [{ to: 'ARCHIVED', label: 'Archivar con decisión', owner: true, needs: 'decision' }],
};

export function ExperimentActions({ exp, canApprove }: { exp: Experiment; canApprove: boolean }) {
  const [text, setText] = useState(''); const [decision, setDecision] = useState('');
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  const opts = (NEXT[exp.status] ?? []).filter((o) => !o.owner || canApprove);
  if (!opts.length) return null;
  const needsText = opts.some((o) => o.needs === 'learning' || o.needs === 'reason');
  const needsDecision = opts.some((o) => o.needs === 'decision');
  return (
    <div className="mt-3 flex flex-col gap-2" data-testid="exp-actions">
      {needsText && <textarea value={text} onChange={(e) => setText(e.target.value)} rows={2} className={field} placeholder="Qué aprendimos / por qué se detiene" />}
      {needsDecision && <select value={decision} onChange={(e) => setDecision(e.target.value)} className={field}>
        <option value="">Decisión…</option><option value="SCALE">Escalar</option><option value="ITERATE">Ajustar y repetir</option><option value="KILL">Matar</option><option value="NONE">Ninguna</option></select>}
      <div className="flex flex-wrap gap-2">{opts.map((o) => (
        <button key={o.to} type="button" disabled={pending} className="rounded-full border border-line bg-surface px-4 py-2 text-sm text-ink disabled:opacity-40"
          onClick={() => start(async () => {
            setErr(null);
            const r = await transitionExperimentAction(exp.id, o.to, o.needs === 'learning' ? text : o.needs === 'reason' ? text : '', decision, o.needs === 'reason' ? text : '');
            if (r.ok) { setText(''); router.refresh(); } else setErr(r.error);
          })}>{o.label}</button>))}</div>
      {err && <p className="text-sm text-danger">{err}</p>}
    </div>
  );
}
