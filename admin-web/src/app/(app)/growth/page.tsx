import Link from 'next/link';
import { redirect } from 'next/navigation';
import { DataStatusTable } from '@/components/DataStatus';
import { canWrite, getCommerceSummary, getGrowthPlan, getMe } from '@/lib/f360';
import { CommerceFacts } from './CommerceFacts';
import { GROWTH_QUESTIONS } from '@/lib/data-audit';
import { PlanEditor } from './PlanEditor';
import { Measurement } from './Measurement';
import { getMeasurementTruth } from '@/lib/measurement';
import { getGrowthCockpit } from '@/lib/growth-cockpit';
import { GrowthCockpit } from './GrowthCockpit';

const PLAN_YEAR = 2027;

export default async function Growth({ searchParams }: { searchParams: Promise<{ vista?: string; desde?: string; hasta?: string; mercado?: string }> }) {
  const { vista, desde, hasta, mercado } = await searchParams;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');   // D-G1-05: growth / plan / financial data is owner/operator only
  const plan = vista === 'plan';
  const commerce = vista === 'commerce';
  const medicion = vista === 'medicion';   // S-G0 Measurement Truth
  const day = (x?: string) => (x && /^\d{4}-\d{2}-\d{2}$/.test(x) ? x : null);
  const truth = medicion ? await getMeasurementTruth(day(desde), day(hasta)) : null;
  const data = plan ? await getGrowthPlan(PLAN_YEAR) : null;
  const facts = commerce ? await getCommerceSummary() : null;
  const war = !plan && !commerce && !medicion;   // S-G1 Growth War Room (main view)
  const cockpit = war ? await getGrowthCockpit(day(desde), day(hasta)) : null;
  const market = ['MX', 'CO', 'ROW'].includes(mercado ?? '') ? mercado! : 'TODOS';
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Growth</h1>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/growth" className={tab(!plan && !commerce && !medicion)}>War Room</Link>
        <Link href="/growth?vista=plan" className={tab(plan)}>Plan {PLAN_YEAR}</Link>
        <Link href="/growth?vista=commerce" className={tab(commerce)}>Commerce Facts (técnico)</Link>
        <Link href="/growth?vista=medicion" className={tab(medicion)}>Medición</Link>
      </div>

      {medicion ? <Measurement data={truth!} canUpload={me.role === 'owner'} /> : commerce ? <CommerceFacts data={facts!} /> : !plan ? (
        <>
          <GrowthCockpit data={cockpit!} market={market} />
          <h2 className="font-display mt-12 text-3xl text-ink">Qué falta para responder todo</h2>
          <div className="mt-4"><DataStatusTable rows={GROWTH_QUESTIONS} /></div>
        </>
      ) : (
        <PlanEditor data={data!} />
      )}
    </div>
  );
}
