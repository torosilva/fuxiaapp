import Link from 'next/link';
import { redirect } from 'next/navigation';
import { DataStatusTable } from '@/components/DataStatus';
import { canWrite, getCommerceSummary, getCrmAccess, getGrowthPlan, getMe } from '@/lib/f360';
import { CommerceFacts } from './CommerceFacts';
import { GROWTH_QUESTIONS } from '@/lib/data-audit';
import { PlanEditor } from './PlanEditor';
import { Measurement } from './Measurement';
import { getMeasurementTruth } from '@/lib/measurement';
import { getGrowthCampaigns, getGrowthCockpit } from '@/lib/growth-cockpit';
import { Campanas } from './Campanas';
import { GrowthCockpit } from './GrowthCockpit';
import { Conciliacion } from './Conciliacion';
import { getRecCase, getRecSummary, listRec, type RecFilters } from '@/lib/sales-rec';
import { getExperiments, getGrowthInstagram } from '@/lib/growth-p0';
import { Instagram } from './Instagram';
import { Experimentos } from './Experimentos';
import { growthP0Enabled } from '@/lib/feature';

const PLAN_YEAR = 2027;

export default async function Growth({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  const { vista, desde, hasta, mercado } = sp;
  const me = await getMe();
  if (!canWrite(me.role)) redirect('/');   // D-G1-05: growth / plan / financial data is owner/operator only
  const plan = vista === 'plan';
  const commerce = vista === 'commerce';
  const medicion = vista === 'medicion';   // S-G0 Measurement Truth
  const campanas = vista === 'campanas';   // S-G2 Campañas: gasto de Meta vs ventas pagadas por campaña
  const p0 = growthP0Enabled();   // hidden in production until the P0 pase
  const instagram = p0 && vista === 'instagram';   // P0-A Instagram orgánico
  const experimentos = p0 && vista === 'experimentos';   // P0-B registro de experimentos (06_EXPERIMENTS.md)
  const day = (x?: string) => (x && /^\d{4}-\d{2}-\d{2}$/.test(x) ? x : null);
  const truth = medicion ? await getMeasurementTruth(day(desde), day(hasta)) : null;
  const data = plan ? await getGrowthPlan(PLAN_YEAR) : null;
  const facts = commerce ? await getCommerceSummary() : null;
  // Conciliación de Ventas: only Carolina & Mario (customer_pii_viewers); the database refuses everyone else anyway.
  const viewer = (await getCrmAccess().catch(() => ({ pii_viewer: false }))).pii_viewer;
  const conciliacion = vista === 'conciliacion' && viewer;
  const pick = (k: string, ok: (v: string) => boolean) => (sp[k] && ok(sp[k]!) ? sp[k]! : null);
  const recFilters: RecFilters = {
    desde: day(desde), hasta: day(hasta), mercado: pick('mercado', (v) => ['MX', 'CO', 'ROW'].includes(v)), estado: pick('estado', (v) => /^[a-z-]{2,30}$/.test(v)),
    metodo: pick('metodo', (v) => /^[\w-]{2,60}$/.test(v)), marca: pick('marca', (v) => /^[A-Za-z_]{2,40}$/.test(v)),
    conciliacion: sp.conciliacion === 'todos' ? null : pick('conciliacion', (v) => /^[a-z_]{2,40}$/.test(v)) ?? (sp.conciliacion ? null : 'pendientes'),
    decision: pick('decision', (v) => /^[a-z_]{2,40}$/.test(v)),
  };
  const pedido = /^([0-9a-f-]{36}):(\d{1,12})$/.exec(sp.pedido ?? '');
  const [recSummary, recList, recCase] = conciliacion
    ? await Promise.all([getRecSummary(recFilters), listRec(recFilters), pedido ? getRecCase(pedido[1], Number(pedido[2])).catch(() => null) : Promise.resolve(null)])
    : [null, null, null];
  const today = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Mexico_City' });
  const camp = campanas ? await getGrowthCampaigns(day(desde), day(hasta)) : null;
  const ig = instagram ? await getGrowthInstagram(day(desde), day(hasta)) : null;
  const exps = experimentos ? await getExperiments() : null;
  const war = !plan && !commerce && !medicion && !conciliacion && !campanas && !instagram && !experimentos;   // S-G1 Growth War Room (main view)
  const cockpit = war ? await getGrowthCockpit(day(desde), day(hasta)) : null;
  const market = ['MX', 'CO', 'ROW'].includes(mercado ?? '') ? mercado! : 'TODOS';
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Growth</h1>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/growth" className={tab(war)}>War Room</Link>
        <Link href="/growth?vista=campanas" className={tab(campanas)}>Campañas</Link>
        {p0 && <Link href="/growth?vista=instagram" className={tab(instagram)}>Instagram</Link>}
        {p0 && <Link href="/growth?vista=experimentos" className={tab(experimentos)}>Experimentos</Link>}
        {viewer && <Link href="/growth?vista=conciliacion" className={tab(conciliacion)}>Conciliación</Link>}
        <Link href="/growth?vista=plan" className={tab(plan)}>Plan {PLAN_YEAR}</Link>
        <Link href="/growth?vista=commerce" className={tab(commerce)}>Commerce Facts (técnico)</Link>
        <Link href="/growth?vista=medicion" className={tab(medicion)}>Medición</Link>
      </div>

      {campanas ? <Campanas data={camp!} today={today} /> : instagram ? <Instagram data={ig!} today={today} /> : experimentos ? <Experimentos data={exps!} /> : conciliacion ? <Conciliacion summary={recSummary!} list={recList!} filters={recFilters} detail={recCase} /> : medicion ? <Measurement data={truth!} canUpload={me.role === 'owner'} /> : commerce ? <CommerceFacts data={facts!} /> : !plan ? (
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
