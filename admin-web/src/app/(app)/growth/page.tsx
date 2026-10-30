import Link from 'next/link';
import { redirect } from 'next/navigation';
import { canWrite, getCommerceSummary, getCrmAccess, getGrowthPlan, getMe } from '@/lib/f360';
import { CommerceFacts } from './CommerceFacts';
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
import { getCompetencia, getHoy, getRecuperar } from '@/lib/growth-hoy';
import { Hoy } from './Hoy';
import { Clientas } from './Clientas';
import { Competencia } from './Competencia';

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
  const competencia = vista === 'competencia';   // Growth Competencia (2026-10-30)
  const clientas = vista === 'clientas' && viewer;   // Clientas a recuperar: Carolina & Mario only (the database refuses everyone else)
  const war = vista === 'war';   // S-G1 Growth War Room (now under "Más")
  const hoy = !war && !plan && !commerce && !medicion && !conciliacion && !campanas && !instagram && !experimentos && !competencia && !clientas;   // Growth → Hoy (main view)
  const mkt: 'MX' | 'CO' = mercado === 'CO' ? 'CO' : 'MX';
  const hoyData = hoy ? await getHoy() : null;
  const rec = clientas ? await getRecuperar(mkt) : hoy && viewer ? await getRecuperar('MX').catch(() => null) : null;
  const pendingBuyers = rec && hoy ? rec.buyers.filter((b) => !b.outreach).length : null;
  const comp = competencia ? await getCompetencia() : null;
  const cockpit = war ? await getGrowthCockpit(day(desde), day(hasta)) : null;
  const market = ['MX', 'CO', 'ROW'].includes(mercado ?? '') ? mercado! : 'TODOS';
  const tab = (active: boolean) => `rounded-full px-5 py-2.5 text-[15px] ${active ? 'bg-ink text-surface' : 'border border-line bg-surface text-ink-2'}`;
  const more = (active: boolean) => `text-sm ${active ? 'font-semibold text-ink' : 'text-ink-2 underline'}`;
  return (
    <div>
      <h1 className="font-display text-5xl text-ink">Growth</h1>
      <div className="mt-5 flex flex-wrap gap-2">
        <Link href="/growth" className={tab(hoy)}>Hoy</Link>
        {viewer && <Link href="/growth?vista=clientas" className={tab(clientas)}>Clientas a recuperar</Link>}
        <Link href="/growth?vista=campanas" className={tab(campanas)}>Campañas</Link>
        {p0 && <Link href="/growth?vista=instagram" className={tab(instagram)}>Instagram</Link>}
        <Link href="/growth?vista=competencia" className={tab(competencia)}>Competencia</Link>
        {p0 && <Link href="/growth?vista=experimentos" className={tab(experimentos)}>Experimentos</Link>}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1">
        <span className="text-xs text-muted">Más:</span>
        <Link href="/growth?vista=war" className={more(war)}>War Room</Link>
        {viewer && <Link href="/growth?vista=conciliacion" className={more(conciliacion)}>Conciliación</Link>}
        <Link href="/growth?vista=plan" className={more(plan)}>Plan {PLAN_YEAR}</Link>
        <Link href="/growth?vista=medicion" className={more(medicion)}>Medición</Link>
        <Link href="/growth?vista=commerce" className={more(commerce)}>Commerce Facts (técnico)</Link>
      </div>

      {hoy ? <Hoy data={hoyData!} pendingBuyers={pendingBuyers} /> : clientas ? <Clientas data={rec!} /> : competencia ? <Competencia data={comp!} /> : campanas ? <Campanas data={camp!} today={today} /> : instagram ? <Instagram data={ig!} today={today} /> : experimentos ? <Experimentos data={exps!} /> : conciliacion ? <Conciliacion summary={recSummary!} list={recList!} filters={recFilters} detail={recCase} /> : medicion ? <Measurement data={truth!} canUpload={me.role === 'owner'} /> : commerce ? <CommerceFacts data={facts!} /> : !plan ? (
        <GrowthCockpit data={cockpit!} market={market} />
      ) : (
        <PlanEditor data={data!} />
      )}
    </div>
  );
}
