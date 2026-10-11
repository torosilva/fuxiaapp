import type { Disponibilidad, Faltante, Meta } from '@/lib/intel';
import { dayLabel, when } from '@/lib/intel';

// Shared pieces of the Centro de Inteligencia screens. They only SHOW what the database said: availability seal, what is
// missing and who it depends on, source, period, currency and "actualizado". No figure is computed here.
const SEAL: Record<Disponibilidad, { label: string; cls: string }> = {
  DISPONIBLE: { label: 'Completo', cls: 'bg-success-soft text-success' },
  PARCIAL: { label: 'Parcial', cls: 'bg-amber-100 text-amber-900' },
  FALTA: { label: 'Falta fuente', cls: 'bg-danger-soft text-danger' },
};
const RANK: Record<Disponibilidad, number> = { DISPONIBLE: 0, PARCIAL: 1, FALTA: 2 };
export const worst = (metas: Meta[]): Disponibilidad => metas.reduce<Disponibilidad>((w, m) => (RANK[m.disponibilidad] > RANK[w] ? m.disponibilidad : w), 'DISPONIBLE');

export function Seal({ d, testId }: { d: Disponibilidad; testId?: string }) {
  const s = SEAL[d] ?? SEAL.FALTA;
  return <span data-testid={testId} data-seal={d} className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold ${s.cls}`}>{s.label}</span>;
}

export function MissingList({ items }: { items: Faltante[] }) {
  if (!items.length) return null;
  return (
    <ul className="flex flex-col gap-1.5 text-sm">
      {items.map((f, i) => (
        <li key={i} className="rounded-xl bg-danger-soft/60 px-3 py-2 text-ink-2"><b className="text-ink">Falta: {f.que}</b> — {f.por_que} — <span className="text-ink">{f.quien}</span></li>
      ))}
    </ul>
  );
}

// A block whose source is missing: NO figure, only what is missing, why and who provides it.
export function Missing({ meta, testId }: { meta: Meta; testId?: string }) {
  return (
    <div data-testid={testId ?? 'falta'} className="flex flex-col gap-2">
      {meta.faltantes.length ? <MissingList items={meta.faltantes} /> : <p className="rounded-xl bg-danger-soft/60 px-3 py-2 text-sm text-ink-2">Falta la fuente de este dato.</p>}
    </div>
  );
}

const periodo = (m: Meta) => (m.periodo ? (m.periodo.desde === m.periodo.hasta ? dayLabel(m.periodo.desde) : `${dayLabel(m.periodo.desde)} – ${dayLabel(m.periodo.hasta)}`) : '—');

// "ⓘ" — expands faltantes + fuente + periodo + moneda + actualizado (+ notas). The short line is always visible.
export function SourceInfo({ meta, extra }: { meta: Meta; extra?: React.ReactNode }) {
  return (
    <details className="group mt-auto border-t border-line pt-2 text-xs text-muted">
      <summary className="flex cursor-pointer list-none flex-wrap items-center gap-x-2 gap-y-0.5 [&::-webkit-details-marker]:hidden">
        <span aria-label="Ver detalle" className="grid size-5 place-items-center rounded-full border border-line text-[11px] text-ink-2 group-open:bg-ink group-open:text-surface">i</span>
        <span className="min-w-0 break-words">{meta.fuente} · actualizado {when(meta.actualizado_al)}</span>
      </summary>
      <dl className="mt-2 grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-ink-2">
        <dt className="text-muted">Fuente</dt><dd className="break-words">{meta.fuente}</dd>
        <dt className="text-muted">Periodo</dt><dd>{periodo(meta)}</dd>
        <dt className="text-muted">Moneda</dt><dd className="break-words">{meta.moneda ?? '—'}</dd>
        <dt className="text-muted">Actualizado</dt><dd>{when(meta.actualizado_al)}</dd>
        <dt className="text-muted">Calidad</dt><dd>{meta.calidad}</dd>
      </dl>
      {meta.faltantes.length > 0 && <div className="mt-2"><MissingList items={meta.faltantes} /></div>}
      {meta.notas.length > 0 && <ul className="mt-2 list-disc pl-4 text-ink-2">{meta.notas.map((n, i) => <li key={i}>{n}</li>)}</ul>}
      {extra}
    </details>
  );
}

// Parcial seal + the missing list, shown next to a figure that IS displayed.
export function PartialNote({ meta }: { meta: Meta }) {
  if (meta.disponibilidad !== 'PARCIAL' || !meta.faltantes.length) return null;
  return <p className="text-xs text-amber-900">Parcial: falta {meta.faltantes.map((f) => f.que.toLowerCase()).join('; ')}.</p>;
}
