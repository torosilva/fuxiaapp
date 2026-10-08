import { createClient } from '@/lib/supabase/server';

// Strategy & Board (SB0). Every call goes to a public.f360_board_* RPC that checks the caller in the database
// (allowlist by auth id + owner role) and logs the access. A denied call answers {ok:false} with no data — this module
// never redirects to /salir on a denial (that would reveal it); pages answer notFound() instead.

export type BoardDenied = { ok: false; error: string };
export type BoardMember = { auth_user_id: string; display_name: string; person_key: string | null };
export type BoardMe = {
  ok: true;
  me: BoardMember & { scopes: string[] };
  members: BoardMember[];
  settings: { require_aal2: boolean; close_requires_second_member: boolean; decision_requires_other_member: boolean; fiscal_year: string; timezone: string };
};
export type PeriodMonth = { id: string; month: number; start: string; end: string; status: 'OPEN' | 'UNDER_REVIEW' | 'CLOSED' | 'REOPENED'; close_version: number; exception_note: string | null; entries: number; pending_approval: number };
export type PeriodRollup = { kind: 'QUARTER' | 'YEAR'; no: number; start: string; end: string; months_closed: number; months_total: number; status: 'OPEN' | 'CLOSED' };
export type BoardPeriods = { ok: true; fiscal_year: number; rule: string; months: PeriodMonth[]; rollups: PeriodRollup[] };
export type Readiness = { component: string; status: 'AVAILABLE' | 'PARTIAL' | 'DATA_INCOMPLETE'; source: string; reason: string | null };
export type CloseEntry = { id: string; account_key: string; dimension_key: string; amount: number; currency: string; source: string; evidence_ref: string | null; note: string | null;
  status: 'active' | 'voided'; captured_by: string; captured_by_me: boolean; captured_at: string; approved_by: string | null; approved_at: string | null; void_reason: string | null };
export type BoardClose = {
  ok: true;
  period: { id: string; year: number; month: number; start: string; end: string; status: PeriodMonth['status']; close_version: number; submitted_by: string; submitted_by_me: boolean | null; exception_note: string | null };
  accounts: { key: string; label: string; component: string; balance_kind: string; allow_negative: boolean }[];
  currencies: string[];
  entries: CloseEntry[];
  readiness: Readiness[];
  events: { at: string; from: string | null; to: string; version: number; by: string; reason: string | null }[];
  snapshots: { version: number; taken_at: string; by: string; hash: string }[];
};
export type AccessRow = { id: number; at: string; who: string; member: boolean; rpc: string; scope: string; outcome: 'allowed' | 'denied' | 'write'; reason: string | null; object_ref: string | null };
export type BoardAccessLog = { ok: true; days: number; summary: { allowed: number; denied: number; writes: number; denied_non_members: number }; rows: AccessRow[] };
export type Metric = { metric_key: string; label: string; definition: string; unit: string; source_kind: string; source_ref: string; depends_on: string[]; availability: 'AVAILABLE' | 'PARTIAL' | 'MISSING'; availability_reason: string };
export type BoardPlans = { ok: true; label: string; plans: { id: string; name: string; horizon: string; status: string; origin: string; target_label: string; note: string | null; revisions: number;
  years: { year: number; theme: string | null; currency: string; revenue_target: number | null; source: string; imported_value: number | null; source_history: { what: string; before: number | null; after: number | null; by: string; at: string }[] | null }[] }[] };

// Equity earn-in tracker (f360_board_earnin). INDICATIVE only: proposed terms, never a cap table, contract or valuation.
export type BoardDecision = { id: string; number: string; title: string; decision: string; status: string; conflict_kind: string; related_party: boolean;
  interested: string[]; recused: string[]; i_am_recused: boolean; approval_basis: string | null; approved_by: string[]; approved_at: string | null;
  proposed_by: string; proposed_by_me: boolean; created_at: string };
export type EarninMilestone = { year: number; revenue_target: number; currency: string; equity_pct: number; partial_from: number; gross_margin_min: number | null };
export type EarninTerms = { id: string; version: number; entity_label: string; initial_pct: number; cap_pct: number; founder_min_pct: number;
  cash_commitment: number | null; cash_currency: string; revenue_definition: string; excluded_markets: string[]; proposal_ref: string | null;
  created_by: string; created_at: string; milestones: EarninMilestone[]; decision: BoardDecision; tracking_status: string };
export type EarninYear = EarninMilestone & { period_state: 'FUTURE' | 'IN_PROGRESS' | 'ENDED'; months_closed: number; management_target: number | null;
  forecast: number | null; actual: number; actual_basis: 'CONSOLIDATED_MXN' | 'MXN_ONLY';
  revenue: { by_currency: Record<string, number>; mxn_only: number; consolidated_mxn: number | null; fx_missing: string[]; status: string };
  attainment: number | null; indicative_equity_actual: number | null; indicative_equity_forecast: number | null;
  margin_gate: 'PENDING_DEFINITION' | 'DATA_INCOMPLETE' | 'MEASURABLE_NOT_EVALUATED' };
export type BoardEarnin = { ok: true; label: string; terms: EarninTerms | null; pending: EarninTerms | null; years: EarninYear[];
  totals: { initial_pct: number; cap_pct: number; founder_min_pct: number; milestones_pct: number; indicative_earned_pct: number; indicative_total_pct: number } | null;
  statuses: { initial_equity: string; legal: string; cash: string; technology: string; margin_metric: string };
  related_party: { member: string; i_am_interested: boolean; rule: string };
  history: { version: number; created_at: string; created_by: string; initial_pct: number; cap_pct: number; decision_number: string; decision_status: string }[];
  this_year: number };

async function boardRpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T | BoardDenied> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: 'No disponible.' };
  return data as T | BoardDenied;
}

// Navigation hint only (boolean about the caller, not logged). Never a security decision.
export async function boardNavVisible(): Promise<boolean> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_board_nav_visible');
  return !error && data === true;
}

// The caller's own Board state (20261016000100): 'ok' | 'mfa_required' (member, second factor missing in this session) | 'none'.
// Only used to decide between the MFA screen and a 404; every Board RPC still checks aal2 in the database.
export async function boardAccessState(): Promise<'ok' | 'mfa_required' | 'none'> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_board_access_state');
  return !error && (data === 'ok' || data === 'mfa_required') ? data : 'none';
}

export const getBoardMe = () => boardRpc<BoardMe>('f360_board_me');
export const getBoardPeriods = (year?: number) => boardRpc<BoardPeriods>('f360_board_periods', { p_year: year ?? null });
export const getBoardClose = (periodId: string) => boardRpc<BoardClose>('f360_board_close_get', { p_period_id: periodId });
export const getBoardAccessLog = (days = 30) => boardRpc<BoardAccessLog>('f360_board_access_log', { p_days: days });
export const getBoardMetrics = () => boardRpc<{ ok: true; metrics: Metric[] }>('f360_board_metric_catalog');
export const getBoardPlans = () => boardRpc<BoardPlans>('f360_board_plans');
export const getBoardEarnin = () => boardRpc<BoardEarnin>('f360_board_earnin');
export const boardCall = (fn: string, args: Record<string, unknown>) => boardRpc<{ ok: true } & Record<string, unknown>>(fn, args);

export const MONTHS = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
export const STATUS_LABEL: Record<string, string> = { OPEN: 'Abierto', UNDER_REVIEW: 'En revisión', CLOSED: 'Cerrado', REOPENED: 'Reabierto' };
