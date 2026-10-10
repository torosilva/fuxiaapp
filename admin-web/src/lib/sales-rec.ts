import { rpc } from '@/lib/f360';
export * from '@/lib/sales-rec-labels';

// Conciliación de Ventas (Growth 360). Only Carolina & Mario (customer_pii_viewers); the database checks every call.
// Five separate states: Woo status · financial evidence · human decision · reconciliation state · analytics scope.
export type RecFlag = { code: string; kind: 'financiera' | 'no_concretado' | 'revision' | 'reembolso' | 'info'; why: string; candidates?: number[]; paid_order?: number };
export type RecRow = {
  target_id: string; target_key: string; woo_order_id: number; created_at: string; market: 'MX' | 'CO' | 'ROW'; currency: string;
  order_total: number; refund_total: number; woo_status: string; payment_method: string | null; paid_at: string | null; ever_paid: boolean; units: number;
  status_class: string; financial_state: string; flags: RecFlag[]; rec_state: string; conflict: string | null; excluded: boolean;
  evidence: { id: number; gateway_result: string; transaction_ref: string | null; queried_at: string } | null;
  decision: { id: number; decision: string; comment: string | null; by: string; at: string; duplicate_of: number | null } | null;
  /** Commercial currency correction (WooCommerce keeps the source currency; no FX conversion). */
  currency_correction: { id: number; woo_currency: string; woo_market: string; currency: string; market: string; reason: string; by: string; at: string } | null;
};
export type RecEvidence = { id: number; source: string; source_ref: string; woo_status: string; date_paid: string | null; transaction_ref: string | null;
  payment_method: string | null; order_total: number | null; currency: string | null; refund_total: number; gateway_result: string; signals: string[];
  result: string; hash: string; by: string; at: string };
export type RecCase = RecRow & {
  facts: { created_via: string; business_origin: string; items_subtotal: number; discount_total: number; shipping_total: number; total_tax: number;
    woo_modified_at: string; completed_at: string | null; billing_country: string | null; last_captured_via: string; last_changed_at: string; source: string } | null;
  lines: { product: string; sku: string | null; quantity: number; total: number }[];
  origin: { channel: string; utm_source: string | null; utm_campaign: string | null; device: string | null } | null;
  duplicates: RecRow[]; evidence_history: RecEvidence[];
  decision_history: { id: number; decision: string; comment: string | null; duplicate_of: number | null; evidence_id: number | null; woo_status_seen: string;
    financial_seen: string; supersedes: number | null; by: string; at: string }[];
  exclusion_history: { id: number; action: 'exclude' | 'include'; reason: string; by: string; at: string }[];
};
export type RecMarket = { market: string; currency: string; orders: number; pending: number; financial_open: number; not_completed: number;
  duplicate_candidates: number; reviewed: number; conflicts: number; investigating: number; changed: number; no_issue: number; excluded: number };
export type RecSummary = { by_market: RecMarket[]; methods: string[]; statuses: string[]; generated_at: string };
export type RecFilters = { desde: string | null; hasta: string | null; mercado: string | null; estado: string | null; metodo: string | null;
  marca: string | null; conciliacion: string | null; decision: string | null };

export const getRecSummary = (f: RecFilters) => rpc<RecSummary>('f360_rec_summary', { p_from: f.desde, p_to: f.hasta, p_market: f.mercado });
export const listRec = (f: RecFilters) => rpc<{ total: number; rows: RecRow[] }>('f360_rec_list', {
  p_from: f.desde, p_to: f.hasta, p_market: f.mercado, p_woo_status: f.estado, p_method: f.metodo, p_flag: f.marca, p_state: f.conciliacion,
  p_decision: f.decision, p_limit: 200, p_offset: 0 });
export const getRecCase = (target: string, order: number) => rpc<RecCase>('f360_rec_case', { p_target: target, p_order: order });

