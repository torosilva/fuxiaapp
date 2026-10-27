// Growth P0 · experiments: types and labels shared by server and client components (no server imports here).
export type Party = 'mario' | 'carolina' | 'goyo' | 'agencia' | 'ia' | 'otro';
export type ExpStatus = 'DRAFT' | 'APPROVED' | 'RUNNING' | 'WINNER' | 'LOSER' | 'INCONCLUSIVE' | 'STOPPED' | 'ARCHIVED';
export type Threshold = { op: '>=' | '<='; value: number; min_sample: number };
export type Measure = { status: string; from?: string; to?: string; days?: number; kpi?: string; kpi_value?: number | null; kpi_currency?: string | null; sample?: number;
  success_met?: boolean; kill_met?: boolean; market_paid_orders?: number; baseline_paid_orders?: number; baseline_period?: [string, string];
  attributed_paid_orders?: number | null; spend_mxn?: number | null; spend_status?: string; evidence?: 'atribucion_observada' | 'antes_despues_mercado'; evidence_note?: string; source?: string };
export type Experiment = {
  id: string; code: string; name: string; hypothesis: string; market: 'MX' | 'CO' | 'ROW' | 'ALL'; channel: string | null; audience: string | null;
  primary_variable: string; proposed_by: Party; responsible: Party; responsible_note: string | null; start_date: string | null; end_date: string | null;
  budget: number | null; budget_currency: string | null; primary_kpi: 'paid_orders' | 'net_revenue' | 'cost_per_paid_order';
  success_threshold: Threshold | null; kill_threshold: Threshold | null; campaign_ids: string[]; utm_campaign: string | null;
  status: ExpStatus; verdict: ExpStatus | null; result: Measure | null; learning: string | null; decision: string | null; stop_reason: string | null;
  created_by_name: string; approved_by_name: string | null; created_at: string; approved_at: string | null; ended_at: string | null;
  live: Measure | null; history: { at: string; from: string | null; to: string | null; field: string | null; old: unknown; new: unknown; by: string; reason: string | null }[];
};
export type TrackRecord = { party: Party; proposed: number; responsible: number; winner: number; loser: number; inconclusive: number; stopped: number; open: number; budget_mxn: number | null };
export type ExperimentsList = { generated_at: string; can_approve: boolean; track_record: TrackRecord[]; experiments: Experiment[] };
export const PARTY: Record<Party, string> = { mario: 'Mario', carolina: 'Carolina', goyo: 'Goyo', agencia: 'Agencia', ia: 'IA (Claude)', otro: 'Otro' };
export const KPI: Record<Experiment['primary_kpi'], string> = { paid_orders: 'Ventas pagadas', net_revenue: 'Venta pagada ($)', cost_per_paid_order: 'Costo por venta pagada' };
export const STATUS: Record<ExpStatus, { label: string; cls: string }> = {
  DRAFT: { label: 'Borrador', cls: 'bg-surface-2 text-ink-2' }, APPROVED: { label: 'Aprobado', cls: 'bg-gold-soft text-gold-strong' },
  RUNNING: { label: 'Corriendo', cls: 'bg-gold-soft text-gold-strong' }, WINNER: { label: 'Ganó', cls: 'bg-success-soft text-success' },
  LOSER: { label: 'Perdió', cls: 'bg-danger-soft text-danger' }, INCONCLUSIVE: { label: 'Sin conclusión', cls: 'bg-surface-2 text-ink-2' },
  STOPPED: { label: 'Detenido', cls: 'bg-surface-2 text-muted' }, ARCHIVED: { label: 'Archivado', cls: 'bg-surface-2 text-muted' },
};
