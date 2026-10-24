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
  currency_corrections?: { count: number; detail: { woo_order_id: number; woo_currency: string; woo_market: string; amount: number; status_class: string }[] | null };
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

// S-G2 · Campañas (f360_growth_campaigns, operator+). Meta spend (MXN) per campaign vs paid orders whose last click was that campaign
// (utm_id). COP / USD are converted only with an approved monthly rate; otherwise revenue_mxn / return are null and verdict = falta_tc.
export type CampaignVerdict = 'recupera' | 'no_recupera' | 'sin_ventas' | 'falta_tc' | 'sin_gasto';
export type CampaignRow = {
  campaign_id: string; name: string; market: string | null; spend: number | null; impressions: number | null; clicks: number | null;
  first_day: string | null; last_day: string | null; paid_orders: number; revenue_by_currency: Record<string, number>;
  revenue_mxn: number | null; cpa: number | null; return: number | null; verdict: CampaignVerdict;
  // what META says it sold (pixel + Meta's attribution; null = not imported for these days). Reference only, never sales.
  meta_purchases: number | null; meta_purchase_value: number | null; meta_add_to_cart: number | null;
};
export type GrowthCampaigns = {
  from: string; to: string; generated_at: string;
  campaigns: CampaignRow[];
  channels: { channel: string; paid_orders: number; revenue_by_currency: Record<string, number>; revenue_mxn: number | null }[];
  totals: { spend: number | null; spend_currency_ok: boolean; paid_orders: number; revenue_by_currency: Record<string, number>; revenue_mxn: number | null;
    ad_orders: number; ad_revenue_mxn: number | null; no_fx_currencies: string[]; spend_last_day: string | null;
    meta_purchases: number | null; meta_purchase_value: number | null; meta_missing_days: number };
  sources: Record<'sales' | 'origin' | 'spend' | 'fx', string> & { meta_says?: string };
};
export const getGrowthCampaigns = (from: string | null, to: string | null) => rpc<GrowthCampaigns>('f360_growth_campaigns', { p_from: from, p_to: to });
