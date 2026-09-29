import { AVAILABILITY_LABEL, type Availability, type AuditRow } from '@/lib/data-audit';

const PILL: Record<Availability, string> = {
  confiable: 'bg-success-soft text-success', parcial: 'bg-gold-soft text-ink-2', no_disponible: 'bg-surface-2 text-muted',
};

export function AvailabilityPill({ status }: { status: Availability }) {
  return <span className={`inline-block rounded-full px-2.5 py-0.5 text-xs font-medium ${PILL[status]}`}>{AVAILABILITY_LABEL[status]}</span>;
}

/** Honest data-quality table: what can be answered today, from which source, and what is missing. */
export function DataStatusTable({ rows, questionLabel = 'Pregunta' }: { rows: AuditRow[]; questionLabel?: string }) {
  return (
    <div className="overflow-hidden rounded-2xl border border-line bg-surface">
      <div className="hidden grid-cols-[minmax(0,2fr)_120px_minmax(0,2fr)_minmax(0,1.5fr)] gap-4 border-b border-line px-5 py-3 text-xs uppercase tracking-[0.12em] text-muted md:grid">
        <span>{questionLabel}</span><span>Datos</span><span>Fuente real</span><span>Qué falta</span>
      </div>
      {rows.map((r) => (
        <div key={r.question} className="grid gap-1 border-b border-line px-5 py-4 last:border-0 md:grid-cols-[minmax(0,2fr)_120px_minmax(0,2fr)_minmax(0,1.5fr)] md:gap-4" data-status={r.status}>
          <span className="text-ink">{r.question}</span>
          <span><AvailabilityPill status={r.status} /></span>
          <span className="text-sm text-ink-2">{r.source}</span>
          <span className="text-sm text-muted">{r.needs}</span>
        </div>
      ))}
    </div>
  );
}
