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
  /** Conciliación: authorized exclusions, shown apart; `original` always equals the KPIs above. `detail` only for Carolina / Mario. */
  adjustments?: Adjustments;
};
export type AdjTotals = { revenue: number; paid_orders: number; units: number; aov?: number | null };
export type Adjustments = {
  original: AdjTotals; excluded: AdjTotals & { without_effect: number }; adjusted: AdjTotals; classified_not_excluded: number; source: string;
  detail: { target_id: string; woo_order_id: number; status_class: string; payment_state: string; effective: boolean; revenue_effect: number; units_effect: number;
    why_no_effect: string | null; reason: string; by: string; at: string }[] | null;
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

// Woo payment method ids → names people recognise (War Room and Conciliación).
const PAY: Record<string, string> = {
  'woo-mercado-pago-custom': 'Mercado Pago (tarjeta)', 'woo-mercado-pago-basic': 'Mercado Pago (checkout)', 'woo-mercado-pago-pix': 'Mercado Pago',
  'ppcp-card-button-gateway': 'PayPal · tarjeta', 'ppcp-gateway': 'PayPal', epayco: 'ePayco', f360_prueba: 'Prueba Fuxia 360', 'sin método': 'Sin método (abandonado antes de elegir)',
};
export const payName = (m: string) => PAY[m] ?? m;
