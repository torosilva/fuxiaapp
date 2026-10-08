// S-G0 Measurement Truth — read surface (owner / operator; the database enforces require_role('operator')). No PII.
import { rpc } from '@/lib/f360';

export type HealthStatus = 'HEALTHY' | 'DEGRADED' | 'STALE' | 'NOT_CONFIGURED' | 'ERROR';
export type SourceHealth = { key: string; label: string; kind: string; status: HealthStatus; reasons: string[]; last_success_at: string | null;
  last_attempt_at: string | null; detail: Record<string, unknown> };
export type Kpi = { status: 'OK' | 'DATA_INCOMPLETE'; value: number | null; missing?: string[]; revenue_mxn?: number; spend_mxn?: number; basis?: string };
export type PaidGroup = { sales_channel: string; capture_source: string; currency: string; paid_orders: number; units: number; gross_merchandise_value: number;
  discounts: number; product_net: number; tax_iva: number; shipping_charged: number; refunds: number; net_product_revenue: number; total_collected: number };
export type ReconTarget = { target: string; status: HealthStatus; reasons: string[]; last_success_at: string | null;
  last_run: { id: number; kind: string; started_at: string; finished_at: string | null; ok: boolean | null; stats: Record<string, number | string | number[]> | null } | null };
export type MeasurementTruth = {
  kind: 'ACTUAL'; from: string | null; to: string | null; generated_at: string; includes_test_data: boolean;
  health: SourceHealth[];
  q1_paid_orders: { total: number; groups: PaidGroup[]; not_paid: Record<string, number> };
  q2_q3_reconciliation: { targets: ReconTarget[] };
  q4_capture_health: { key: string; status: HealthStatus; reasons: string[] }[];
  q5_timing: Record<string, { sales: number; paid: number }>;
  q6_channels: Record<string, { paid: number; not_counted: number }>;
  q7_currencies: Record<string, number>;
  q8_net_product_revenue: { by_currency: { currency: string; net_product_revenue: number; total_collected: number; paid_orders: number }[];
    consolidated_mxn: Kpi & { kind?: string; fx_missing?: { currency: string; month: string }[] }; basis: string };
  q9_spend: { status: HealthStatus; by_currency: { platform: string; currency: string; spend: number; days: number }[] };
  q10_efficiency: { period: { from: string | null; to: string | null }; mer: Kpi; roas: Kpi; cac: Kpi };
};

export const getMeasurementTruth = (from?: string | null, to?: string | null) =>
  rpc<MeasurementTruth>('f360_measurement_truth', { p_from: from || null, p_to: to || null });
