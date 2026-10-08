import Link from 'next/link';
import { redirect } from 'next/navigation';
import { DataStatusTable } from '@/components/DataStatus';
import { canWrite, getCommerceSummary, getGrowthPlan, getMe } from '@/lib/f360';
import { CommerceFacts } from './CommerceFacts';
import { GROWTH_QUESTIONS } from '@/lib/data-audit';
import { PlanEditor } from './PlanEditor';
import { Measurement } from './Measurement';
import { getMeasurementTruth } from '@/lib/measurement';

const PLAN_YEAR = 2027;
const VIEWS = ['Tiempo', 'Canal', 'Producto / modelo', 'Categoría', 'Ciudad / estado', 'Nueva vs recurrente'];

export default async function Growth({ searchParams }: { searchParams: Promise<{ vista?: string; desde?: string; hasta?: string }> }) {
  const { vista, desde, hasta } = await searchParams;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');   // D-G1-05: growth / plan / financial data is owner/operator only
  const plan = vista === 'plan';
  const commerce = vista === 'commerce';
  const medicion = vista === 'medicion';   // S-G0 Measurement Truth
  const day = (x?: string) => (x && /^\d{4}-\d{2}-\d{2}$/.test(x) ? x : null);
  const truth = medicion ? await getMeasurementTruth(day(desde), day(hasta)) : null;
  const data = plan ? await getGrowthPlan(PLAN_YEAR) : null;
  const facts = commerce ? await getCommerceSummary() : null;
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Growth</h1>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/growth" className={tab(!plan && !commerce && !medicion)}>Inteligencia comercial</Link>
        <Link href="/growth?vista=plan" className={tab(plan)}>Plan {PLAN_YEAR}</Link>
        <Link href="/growth?vista=commerce" className={tab(commerce)}>Commerce Facts (técnico)</Link>
        <Link href="/growth?vista=medicion" className={tab(medicion)}>Medición</Link>
      </div>

      {medicion ? <Measurement data={truth!} canUpload={me.role === 'owner'} /> : commerce ? <CommerceFacts data={facts!} /> : !plan ? (
        <>
          <div className="mt-6 rounded-3xl border border-gold/40 bg-gold-soft/60 p-5" data-testid="growth-status">
            <p className="text-lg text-ink">Todavía no hay datos suficientes para el tablero comercial.</p>
            <p className="mt-1 text-ink-2">Los pedidos en línea llegan a Fuxia 360 desde el 8 de octubre de 2026 (sin historial anterior todavía) y las ventas físicas solo están si se registraron en la app; la pestaña Medición dice qué fuente está sana y qué falta. Mostrar números parciales como si fueran totales sería engañoso, así que cada pregunta indica qué datos existen y qué falta.</p>
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
