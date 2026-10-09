'use client';
import { useState, useTransition } from 'react';
import type { WeeklyBoard, WeeklyCard } from '@/lib/weekly';
import { saveCardAction, saveMetricsAction, setAgencyPhoneAction } from './actions';

const input = 'mt-1 block w-full rounded-xl border border-line bg-bg px-3 py-2.5 text-[15px] outline-none focus:border-gold disabled:opacity-70';
const label = 'mt-3 block text-[11px] font-bold uppercase tracking-[0.06em] text-muted';
const NUMBERS: Record<string, { key: string; label: string }[]> = {
  AGENCIA: [],
  CAROLINA: [{ key: 'rescued', label: 'Pares rescatados' }, { key: 'pieces', label: 'Piezas publicadas' }],
  MARIO: [{ key: 'blockers', label: 'Bloqueadores cerrados' }],
};
const STATUS = [{ v: 'si', l: 'Sí', c: 'bg-success text-surface' }, { v: 'parcial', l: 'Parcial', c: 'bg-gold text-surface' }, { v: 'no', l: 'No', c: 'bg-danger text-surface' }] as const;
const num = (s: string) => (s.trim() === '' ? null : Number(s));

export function CardForm({ week, card }: { week: string; card: WeeklyCard }) {
  const ro = !card.mine;
  const [f, setF] = useState({ commitment: card.commitment ?? '', done: card.done ?? '', status: card.status as string | null,
    numbers: Object.fromEntries(NUMBERS[card.person_key].map((n) => [n.key, card.numbers?.[n.key] == null ? '' : String(card.numbers[n.key])])) as Record<string, string> });
  const [msg, setMsg] = useState('');
  const [pending, start] = useTransition();
  const save = () => start(async () => {
    const numbers = Object.fromEntries(Object.entries(f.numbers).map(([k, v]) => [k, num(v)]));
    const r = await saveCardAction(week, f.commitment, f.done, numbers, f.status);
    setMsg(r.ok ? 'Guardado.' : r.error);
  });
  return (
    <div>
      <label className={label}>Compromiso de la semana<textarea disabled={ro} rows={2} value={f.commitment} onChange={(e) => setF({ ...f, commitment: e.target.value })} className={input} /></label>
      <label className={label}>Qué hizo de verdad<textarea disabled={ro} rows={2} value={f.done} onChange={(e) => setF({ ...f, done: e.target.value })} className={input} /></label>
      <div className="mt-1 flex flex-wrap items-end gap-3">
        {NUMBERS[card.person_key].map((n) => (
          <label key={n.key} className={`${label} w-40`}>{n.label}
            <input disabled={ro} inputMode="numeric" value={f.numbers[n.key]} onChange={(e) => setF({ ...f, numbers: { ...f.numbers, [n.key]: e.target.value.replace(/[^\d.]/g, '') } })} className={input} />
          </label>
        ))}
        <div>
          <span className={label}>Cumplió</span>
          <div className="mt-1 flex gap-1">
            {STATUS.map((s) => (
              <button key={s.v} type="button" disabled={ro} onClick={() => setF({ ...f, status: f.status === s.v ? null : s.v })}
                className={`rounded-lg px-3 py-2 text-xs font-bold ${f.status === s.v ? s.c : 'border border-line bg-bg text-muted'} disabled:opacity-70`}>{s.l}</button>
            ))}
          </div>
        </div>
      </div>
      {!ro && (
        <div className="mt-4 flex items-center gap-3">
          <button type="button" disabled={pending} onClick={save} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar mi tarjeta'}</button>
          {msg && <span className="text-sm text-ink-2">{msg}</span>}
        </div>
      )}
    </div>
  );
}

const METRICS = [
  { key: 'conv', label: 'Conv. sesión→pagado %', hint: 'meta ≥0.24' },
  { key: 'cop_pct', label: '% pagado COP', hint: 'meta 74' },
  { key: 'prefix_pct', label: '% pagado con prefijo país', hint: 'meta >95' },
  { key: 'roas', label: 'ROAS retargeting', hint: 'meta ≥3' },
  { key: 'first_response_min', label: 'Tiempo 1ª respuesta (min)', hint: 'meta <10' },
  { key: 'dms_per_day', label: 'DMs de venta / día', hint: 'define si contratas apoyo' },
];

export function MetricsForm({ week, metrics, canEdit }: { week: string; metrics: WeeklyBoard['metrics']; canEdit: boolean }) {
  const [v, setV] = useState<Record<string, string>>(Object.fromEntries(METRICS.map((m) => [m.key, metrics?.values?.[m.key] == null ? '' : String(metrics.values[m.key])])));
  const [decision, setDecision] = useState(metrics?.decision ?? '');
  const [msg, setMsg] = useState('');
  const [pending, start] = useTransition();
  const save = () => start(async () => {
    const r = await saveMetricsAction(week, Object.fromEntries(Object.entries(v).map(([k, x]) => [k, num(x)])), decision);
    setMsg(r.ok ? 'Guardado.' : r.error);
  });
  return (
    <div>
      <div className="mt-2 grid gap-3 sm:grid-cols-2">
        {METRICS.map((m) => (
          <label key={m.key} className={label}>{m.label}
            <input disabled={!canEdit} inputMode="decimal" value={v[m.key]} onChange={(e) => setV({ ...v, [m.key]: e.target.value.replace(/[^\d.]/g, '') })} className={input} />
            <span className="mt-1 block text-[11px] font-normal normal-case tracking-normal text-muted">{m.hint}</span>
          </label>
        ))}
      </div>
      <label className={label}>Decisión de la semana
        <textarea disabled={!canEdit} rows={2} value={decision} onChange={(e) => setDecision(e.target.value)} placeholder="Qué se decide con estos números (no un resumen: una decisión)." className={input} />
      </label>
      {canEdit && (
        <div className="mt-4 flex items-center gap-3">
          <button type="button" disabled={pending} onClick={save} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">{pending ? 'Guardando…' : 'Guardar números'}</button>
          {msg && <span className="text-sm text-ink-2">{msg}</span>}
        </div>
      )}
    </div>
  );
}

export function AgencyPhone() {
  const [phone, setPhone] = useState('');
  const [name, setName] = useState('');
  const [msg, setMsg] = useState('');
  const [pending, start] = useTransition();
  const save = () => start(async () => { const r = await setAgencyPhoneAction(phone, name); setMsg(r.ok ? 'Listo: la agencia ya puede entrar con ese WhatsApp (solo verá esta página).' : r.error); });
  return (
    <details className="rounded-2xl border border-dashed border-line p-4 text-sm">
      <summary className="cursor-pointer font-semibold text-ink-2">Acceso de la agencia</summary>
      <p className="mt-2 text-muted">La agencia entra a fuxia360.vercel.app con su WhatsApp y solo ve esta página. No ve ventas, clientas ni nada más.</p>
      <div className="mt-3 flex flex-wrap items-end gap-3">
        <label className="text-ink-2">Nombre<input value={name} onChange={(e) => setName(e.target.value)} placeholder="Agencia" className={input} /></label>
        <label className="text-ink-2">WhatsApp (10 dígitos)<input inputMode="tel" value={phone} onChange={(e) => setPhone(e.target.value)} className={input} /></label>
        <button type="button" disabled={pending || !phone.trim()} onClick={save} className="rounded-full bg-ink px-5 py-2.5 text-sm text-surface disabled:opacity-40">Guardar</button>
      </div>
      {msg && <p className="mt-2 text-ink-2">{msg}</p>}
    </details>
  );
}
