'use client';
import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { DECISIONS } from '@/lib/sales-rec-labels';
import { correctCurrencyAction, decideAction, fetchEvidenceAction, setAnalyticsAction, type EvidenceDisplay } from './conciliacion-actions';

// Conciliación de Ventas — the three human actions. The database re-checks everything (who, what, reason, evidence).
const field = 'mt-1 w-full rounded-xl border border-line bg-bg px-3 py-2 text-base outline-none focus:border-gold';
const KIND: Record<string, string> = { approved: 'aprobado', rejected: 'rechazado', pending: 'pendiente', refunded: 'reembolso' };

export function EvidencePanel({ targetKey, orderId }: { targetKey: string; orderId: number }) {
  const [res, setRes] = useState<EvidenceDisplay | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  return (
    <div className="mt-2" data-testid="rec-evidence">
      <button type="button" disabled={pending} className="rounded-full bg-ink px-4 py-2 text-sm text-surface disabled:opacity-40"
        onClick={() => start(async () => {
          setErr(null);
          const r = await fetchEvidenceAction(targetKey, orderId);
          if (r.ok) { setRes(r.data); router.refresh(); } else setErr(r.error);
        })}>{pending ? 'Consultando WooCommerce…' : 'Consultar evidencia en WooCommerce'}</button>
      <p className="mt-1 text-xs text-muted">Solo lectura. Se guarda únicamente: estado, fecha de pago, número de transacción, método, totales, resultado y su huella.</p>
      {err && <p className="mt-2 text-sm text-danger">{err}</p>}
      {res && (
        <div className="mt-3 rounded-xl border border-line bg-bg p-3 text-sm">
          <p className="font-semibold text-ink">{res.evidence.result}</p>
          {!res.missing && <>
            <p className="mt-2 text-ink-2">🔒 Clienta: <span className="text-ink">{res.display.customer.name ?? '—'}</span>{res.display.customer.email ? ` · ${res.display.customer.email}` : ''}
              <span className="block text-xs text-muted">Se muestra ahora y no se guarda en Fuxia 360.</span></p>
            {res.display.payment_method_title && <p className="mt-1 text-ink-2">Método en la tienda: {res.display.payment_method_title}</p>}
            <p className="mt-2 text-xs font-semibold text-ink-2">Notas de la pasarela en WooCommerce (datos personales ocultos, no se guardan)</p>
            {res.display.gateway_notes.length ? (
              <ul className="mt-1 flex flex-col gap-1 text-xs">{res.display.gateway_notes.map((n, i) => (
                <li key={i} className="text-ink-2"><span className="text-muted">{new Date(n.at.endsWith('Z') ? n.at : `${n.at}Z`).toLocaleString('es-MX', { timeZone: 'America/Mexico_City' })}</span> · <b>{KIND[n.kind] ?? n.kind}</b> · {n.text}</li>))}</ul>
            ) : <p className="mt-1 text-xs text-muted">WooCommerce no tiene notas de la pasarela para este pedido.</p>}
          </>}
          <p className="mt-2 text-[11px] text-muted">Consulta #{res.evidence.id} · huella {res.evidence.hash.slice(0, 16)}…</p>
        </div>
      )}
    </div>
  );
}

export function DecisionForm({ target, orderId, latestEvidence, hasDecision, candidates }: { target: string; orderId: number;
  latestEvidence: { id: number; at: string; label: string } | null; hasDecision: boolean; candidates: number[] }) {
  const [decision, setDecision] = useState('');
  const [comment, setComment] = useState('');
  const [dup, setDup] = useState(candidates[0] ? String(candidates[0]) : '');
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  const needsComment = hasDecision || ['duplicado', 'prueba', 'requiere_investigacion'].includes(decision);
  const needsEvidence = ['venta_confirmada', 'reembolso'].includes(decision);
  return (
    <div className="rounded-2xl border border-line p-4" data-testid="rec-decide">
      <h3 className="text-lg font-semibold text-ink">{hasDecision ? 'Corregir la clasificación' : 'Clasificar este pedido'}</h3>
      <p className="mt-1 text-xs text-muted">Tu decisión queda registrada con tu nombre y no cambia WooCommerce ni el estado del cobro.</p>
      <div className="mt-3 grid grid-cols-2 gap-2">
        {Object.entries(DECISIONS).map(([k, v]) => (
          <button key={k} type="button" onClick={() => setDecision(k)}
            className={`rounded-xl border px-3 py-2 text-left text-sm ${decision === k ? 'border-ink bg-ink text-surface' : 'border-line bg-bg text-ink'}`}>{v}</button>
        ))}
      </div>
      {decision === 'duplicado' && (
        <label className="mt-3 block text-sm text-muted">¿Duplicado de qué pedido?
          <input inputMode="numeric" className={field} value={dup} onChange={(e) => setDup(e.target.value.replace(/\D/g, ''))} placeholder="Número de pedido" />
          {candidates.length > 0 && <span className="text-xs">Candidatos: {candidates.map((c) => `#${c}`).join(', ')}</span>}</label>
      )}
      <label className="mt-3 block text-sm text-muted">Comentario{needsComment ? ' (obligatorio)' : ' (opcional)'}
        <textarea className={field} rows={2} value={comment} onChange={(e) => setComment(e.target.value)} maxLength={1000}
          placeholder={hasDecision ? 'Por qué cambias la decisión anterior' : 'Qué viste o a quién le preguntaste'} /></label>
      {needsEvidence && <p className={`mt-2 text-xs ${latestEvidence ? 'text-ink-2' : 'text-danger'}`}>
        {latestEvidence ? `Se adjunta la última consulta (#${latestEvidence.id}: ${latestEvidence.label}).` : 'Primero consulta la evidencia en WooCommerce.'}</p>}
      <button type="button" disabled={pending || !decision || (needsComment && comment.trim().length < 5) || (needsEvidence && !latestEvidence) || (decision === 'duplicado' && !dup)}
        className="mt-3 rounded-full bg-ink px-5 py-2 text-sm text-surface disabled:opacity-40"
        onClick={() => start(async () => {
          const r = await decideAction(target, orderId, decision, comment, latestEvidence?.id ?? null, decision === 'duplicado' ? Number(dup) : null);
          if (r.ok) {
            setMsg({ ok: true, text: r.data.conflict ? `Guardado, con conflicto: ${r.data.conflict}` : 'Guardado.' });
            setDecision(''); setComment(''); router.refresh();
          } else setMsg({ ok: false, text: r.error });
        })}>{pending ? 'Guardando…' : 'Guardar decisión'}</button>
      {msg && <p className={`mt-2 text-sm ${msg.ok ? 'text-ink-2' : 'text-danger'}`}>{msg.text}</p>}
    </div>
  );
}

// Commercial currency correction: WooCommerce keeps its record; no FX conversion; the payment state never changes.
export function CurrencyForm({ target, orderId, wooCurrency, active }: { target: string; orderId: number; wooCurrency: string; active: { currency: string } | null }) {
  const [currency, setCurrency] = useState(active?.currency ?? (wooCurrency === 'COP' ? 'MXN' : 'COP'));
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  const run = (revert: boolean) => start(async () => {
    const r = await correctCurrencyAction(target, orderId, revert ? null : currency, reason, revert);
    if (r.ok) { setReason(''); setMsg(null); router.refresh(); } else setMsg(r.error);
  });
  return (
    <div className="rounded-2xl border border-line p-4" data-testid="rec-currency">
      <h3 className="text-lg font-semibold text-ink">Moneda del pedido</h3>
      <p className="mt-1 text-xs text-muted">WooCommerce registra {wooCurrency}. Una corrección comercial cambia solo cómo se reporta (país y moneda), sin convertir el importe ni cambiar el estado de pago. Queda registrada y se puede revertir.</p>
      <div className="mt-3 flex flex-wrap items-end gap-2">
        {!active && <label className="text-sm text-muted">Moneda correcta
          <select className={field} value={currency} onChange={(e) => setCurrency(e.target.value)}>
            {['MXN', 'COP', 'USD'].filter((c) => c !== wooCurrency).map((c) => <option key={c} value={c}>{c}</option>)}
          </select></label>}
      </div>
      <label className="mt-3 block text-sm text-muted">Motivo y evidencia (obligatorio)
        <input className={field} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} placeholder={active ? 'Por qué se revierte' : 'Quién lo confirmó y con qué evidencia'} /></label>
      <button type="button" disabled={pending || reason.trim().length < 10} className="mt-3 rounded-full border border-ink px-5 py-2 text-sm text-ink disabled:opacity-40"
        onClick={() => run(!!active)}>{pending ? 'Guardando…' : active ? `Revertir a ${wooCurrency}` : `Corregir a ${currency}`}</button>
      {msg && <p className="mt-2 text-sm text-danger">{msg}</p>}
    </div>
  );
}

export function AnalyticsForm({ target, orderId, excluded }: { target: string; orderId: number; excluded: boolean }) {
  const [reason, setReason] = useState('');
  const [msg, setMsg] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const router = useRouter();
  return (
    <div className="rounded-2xl border border-line p-4" data-testid="rec-analytics">
      <h3 className="text-lg font-semibold text-ink">Métricas de Growth</h3>
      <p className="mt-1 text-xs text-muted">Acción aparte de la clasificación. Hoy {excluded ? 'está EXCLUIDO' : 'está incluido'}. Queda registrada con tu nombre, fecha y motivo.
        El War Room conserva las cifras originales y muestra este ajuste por separado.</p>
      <label className="mt-3 block text-sm text-muted">Motivo (obligatorio)
        <input className={field} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} placeholder={excluded ? 'Por qué vuelve a contar' : 'Por qué no debe contar'} /></label>
      <button type="button" disabled={pending || reason.trim().length < 5} className="mt-3 rounded-full border border-ink px-5 py-2 text-sm text-ink disabled:opacity-40"
        onClick={() => start(async () => {
          const r = await setAnalyticsAction(target, orderId, !excluded, reason.trim());
          if (r.ok) { setReason(''); setMsg(null); router.refresh(); } else setMsg(r.error);
        })}>{pending ? 'Guardando…' : excluded ? 'Volver a incluir en métricas' : 'Excluir de métricas'}</button>
      {msg && <p className="mt-2 text-sm text-danger">{msg}</p>}
    </div>
  );
}
