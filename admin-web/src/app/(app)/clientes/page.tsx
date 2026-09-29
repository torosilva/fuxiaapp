import { AvailabilityPill, DataStatusTable } from '@/components/DataStatus';
import { CUSTOMER_FIELDS, IDENTITY_DECISIONS, SEGMENTS } from '@/lib/data-audit';

// Customer 360 (B1/B2) — honest state. The customer model is designed (docs/fuxia360/growth/CUSTOMER_360_MODEL.md)
// but NOT built: it waits for identity decisions that could otherwise merge or duplicate people. No invented data.
export default function Clientes() {
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Clientes</h1>
      <p className="mt-2 max-w-3xl text-ink-2">Aquí vivirá la ficha 360 de cada clienta: sus compras en línea y en tienda, lo que ha comprado, su nivel de loyalty y cuándo volvió a comprar.</p>

      <div className="mt-6 rounded-3xl border border-gold/40 bg-gold-soft/60 p-5" data-testid="clientes-status">
        <p className="text-lg text-ink">Todavía no hay datos suficientes para mostrar clientas.</p>
        <p className="mt-1 text-ink-2">Antes de unir la información de distintos canales hace falta que Mario decida cómo identificar a cada clienta, para no mezclar a dos personas ni duplicar a una. Nada de esta sección usa números inventados.</p>
      </div>

      <h2 className="font-display mt-10 text-3xl text-ink">Decisiones pendientes</h2>
      <ol className="mt-3 space-y-2">
        {IDENTITY_DECISIONS.map((d) => (
          <li key={d.id} className="rounded-2xl border border-line bg-surface px-5 py-4"><span className="mr-2 font-mono text-sm text-gold-strong">{d.id}</span><span className="text-ink">{d.question}</span></li>
        ))}
      </ol>

      <h2 className="font-display mt-10 text-3xl text-ink">Qué información existe de cada clienta</h2>
      <p className="mt-1 text-sm text-muted">Confiable = completa y correcta · Parcial = solo una parte (no representa el total) · No disponible = no hay fuente accesible.</p>
      <div className="mt-4"><DataStatusTable rows={CUSTOMER_FIELDS} questionLabel="Dato" /></div>

      <h2 className="font-display mt-10 text-3xl text-ink">Segmentos</h2>
      <p className="mt-1 text-sm text-muted">Definiciones listas. Se activarán cuando exista historial confiable por clienta.</p>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        {SEGMENTS.map((s) => (
          <div key={s.name} className="rounded-2xl border border-line bg-surface p-4" data-segment={s.name}>
            <div className="flex items-center justify-between gap-2"><p className="font-medium text-ink">{s.name}</p><AvailabilityPill status={s.status} /></div>
            <p className="mt-1 text-sm text-ink-2">{s.rule}</p>
            <p className="mt-1 text-xs text-muted">Falta: {s.needs}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
