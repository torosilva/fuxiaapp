import { rpc } from '@/lib/f360';

// S-G1 Growth Cockpit (f360_growth_cockpit, operator+). Money = paid online-store orders; nothing is converted between currencies.
export type KpiStatus = 'OK' | 'DATA_INCOMPLETE' | 'NOT_CONFIGURED' | 'STALE';
export type Kpi = { value: number | null; prev?: number | null; currency?: string; status: KpiStatus; source: string; note?: string | null };
export type MarketBlock = {
  market: 'MX' | 'CO' | 'ROW'; currency: 'MXN' | 'COP' | 'USD';
  kpis: Record<'revenue' | 'paid_orders' | 'aov' | 'units' | 'cvr_session' | 'cvr_click' | 'spend' | 'cpc' | 'ctr' | 'cpm' | 'cpa' | 'roas' | 'mer', Kpi>;
  attribution_coverage: { attributed: number; paid: number };
  funnel: { stage: string; value: number | null; status: KpiStatus; source: string }[];
  checkout: { created: number; paid: number; never_paid: number; by_payment: { method: string; created: number; paid: number; never_paid: number }[] };
  by_channel: { channel: string; orders_created: number; paid_orders: number; revenue: number }[];
  by_campaign: { campaign: string; source: string | null; orders_created: number; paid_orders: number; revenue: number; spend: number | null }[];
  by_product: { product: string; paid_units: number; revenue: number }[];
};
export type Finding = { market: string; kind: string; confidence: 'ALTA' | 'MEDIA' | 'BAJA' | 'SIN DATOS'; title: string; evidence: string; source: string;
  detail?: { method: string; created: number; paid: number; never_paid: number }[] };
export type Cockpit = {
  from: string; to: string; prev_from: string; prev_to: string; generated_at: string;
  freshness: { last_success_at: string | null; status: 'OK' | 'STALE' };
  consolidated: { status: KpiStatus; note: string };
  markets: MarketBlock[]; findings: Finding[];
};

export const getGrowthCockpit = (from: string | null, to: string | null) => rpc<Cockpit>('f360_growth_cockpit', { p_from: from, p_to: to });
