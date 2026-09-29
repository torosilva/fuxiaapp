import Link from 'next/link';
import { DataStatusTable } from '@/components/DataStatus';
import { getGrowthPlan } from '@/lib/f360';
import { GROWTH_QUESTIONS } from '@/lib/data-audit';
import { PlanEditor } from './PlanEditor';

const PLAN_YEAR = 2027;
const VIEWS = ['Tiempo', 'Canal', 'Producto / modelo', 'Categoría', 'Ciudad / estado', 'Nueva vs recurrente'];

export default async function Growth({ searchParams }: { searchParams: Promise<{ vista?: string }> }) {
  const { vista } = await searchParams;
  const plan = vista === 'plan';
  const data = plan ? await getGrowthPlan(PLAN_YEAR) : null;
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Growth</h1>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/growth" className={tab(!plan)}>Inteligencia comercial</Link>
        <Link href="/growth?vista=plan" className={tab(plan)}>Plan {PLAN_YEAR}</Link>
      </div>

      {!plan ? (
        <>
          <div className="mt-6 rounded-3xl border border-gold/40 bg-gold-soft/60 p-5" data-testid="growth-status">
            <p className="text-lg text-ink">Todavía no hay datos suficientes para el tablero comercial.</p>
            <p className="mt-1 text-ink-2">La venta completa en línea vive en WooCommerce y todavía no está conectada a Fuxia 360; las ventas físicas solo están si se registraron en la app. Mostrar números parciales como si fueran totales sería engañoso, así que cada pregunta indica qué datos existen y qué falta.</p>
          </div>
          <div className="mt-6 grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
            {VIEWS.map((v) => (
              <div key={v} className="rounded-2xl border border-dashed border-line bg-surface p-4">
                <p className="text-ink">{v}</p><p className="mt-1 text-xs text-muted">Sin datos suficientes</p>
              </div>
            ))}
          </div>
          <h2 className="font-display mt-10 text-3xl text-ink">Qué podemos responder hoy</h2>
          <div className="mt-4"><DataStatusTable rows={GROWTH_QUESTIONS} /></div>
        </>
      ) : (
        <PlanEditor data={data!} />
      )}
    </div>
  );
}
