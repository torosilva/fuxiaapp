import { redirect } from 'next/navigation';
import { canWrite, getExecDashboard, getMe, type DashPeriod } from '@/lib/f360';
import { ControlCenter } from './ControlCenter';

// Centro de control (Mario 2026-10-05): the executive dashboard. Real data from one aggregate RPC (f360_exec_dashboard):
// MXN headline, other currencies apart, historical summaries marked, no personal data (birthday names only for PII viewers
// and never in the presentation view). owner/operator only, like Ventas and Growth.
const PERIODS: DashPeriod[] = ['hoy', 'semana', 'mes', 'anio'];

export default async function Tablero({ searchParams }: { searchParams: Promise<{ periodo?: string; vista?: string }> }) {
  const sp = await searchParams;
  if (!canWrite((await getMe()).role)) redirect('/');
  const period = (PERIODS as string[]).includes(sp.periodo ?? '') ? (sp.periodo as DashPeriod) : 'mes';
  const presentation = sp.vista === 'presentacion';
  const data = await getExecDashboard(period, presentation);
  return <ControlCenter data={data} />;
}
