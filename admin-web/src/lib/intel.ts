import { cache } from 'react';
import { createClient } from '@/lib/supabase/server';
import type { Role } from '@/lib/f360';

// Centro de Inteligencia (I2): the screens only RENDER what these RPCs return. Every number, comparison, projection and
// availability seal is computed in the database (f360_intel_* / f360_board_* / f360_close_prep_*), which also decides who may
// call them (board FINANCIAL + second factor, or the finance preparer). A denial or an error comes back as {ok:false,error}
// — never a redirect to /salir (that would reveal the module) — and pages answer with the error or a 404.

export type Denied = { ok: false; error: string };
export type Disponibilidad = 'DISPONIBLE' | 'PARCIAL' | 'FALTA';
export type Faltante = { que: string; por_que: string; quien: string };
export type Meta = {
  fuente: string; periodo: { desde: string; hasta: string } | null; moneda: string | null; actualizado_al: string | null; generado_al?: string;
  disponibilidad: Disponibilidad; calidad: string; faltantes: Faltante[]; notas: string[];
};
export type Block<T> = { data: T; meta: Meta };

export type Tasa = { moneda: string; mes: string; tasa: number; estado: 'approved' | 'provisional' | string; fuente?: string };
export type Consolidado = { mxn: number | null; tasas: Tasa[]; sin_tasa: { moneda: string; mes: string }[] };
export type Anterior = { venta_neta: number; pedidos_pagados: number; ticket_promedio: number | null };
export type SalesRow = { mercado: string; canal: string; moneda: string; pedidos_pagados: number; pares: number; venta_neta: number; ticket_promedio: number | null;
  anterior: Anterior | null; explicacion_cambio: { cambio_venta: number; por_pedidos: number; por_ticket: number; formula: string } | null };
export type Sales = { por_mercado_canal: SalesRow[]; consolidado_mxn: Consolidado | null; periodo_anterior?: { desde: string; hasta: string };
  excluidas_por_conciliacion: { mercado: string; moneda: string; pedidos: number; venta_neta: number }[];
  moneda_por_conciliar: { pedido: number | string; moneda: string; estado: string }[] };
export type BudgetLine = { mercado: string; canal: string; moneda: string; presupuesto: number | null; real: number | null; cumplimiento_pct: number | null; brecha: number | null; version?: string };
export type Goal300 = { meta: number; moneda: string; mercado: string; canal: string; real_al_dia: number; avance_pct: number | null; faltante: number;
  dias_transcurridos: number; dias_restantes: number; dias_del_mes?: number; ritmo_necesario_diario: number | null; ritmo_actual_diario: number | null;
  proyeccion_por_ritmo: number | null; mejor_mes_ultimos_12: { mes: string; venta_neta: number } | null; historial_12_meses: { mes: string; venta_neta: number }[];
  pedidos_pagados?: number; meta_nombre?: string; meta_definida_por?: string; meta_motivo?: string; formulas: Record<string, string> };
export type MarketingRow = { mercado: string; inversion: { monto: number | null; moneda: string | null; clics: number | null; impresiones: number | null } | null;
  inversion_mxn: Consolidado | null; venta_neta: { monto: number; moneda: string } | null; venta_neta_mxn: Consolidado | null; pedidos_pagados: number;
  clientas_nuevas: number; pedidos_sin_identidad: number; mer: number | null; cpa_mxn: number | null; cac_mxn: number | null;
  roas_atribuido: { valor: number | null; disponibilidad: Disponibilidad; por_que: string } };
export type Marketing = { por_mercado: MarketingRow[]; campanas_top: { mercado: string; campana: string; inversion: number; moneda: string }[]; google_ads: string; formulas: Record<string, string> };
export type InvModel = { modelo: string; categoria?: string; pares: number; vendidos_periodo?: number; dias_cobertura?: number | null; valor_precio_venta?: number };
export type Inventory = { pares_total: number; por_ubicacion: { ubicacion: string; tipo: string; pares: number }[]; por_modelo: InvModel[]; baja_salida: InvModel[];
  riesgo_agotarse: InvModel[]; ventana_dias: number; historial_ventas_desde: string | null; cobertura_costo_pct: number | null; formulas: Record<string, string> };
export type Cash = { mes: string; estado_del_mes: string | null; cierre_aprobado: { cuenta: string; componente: string; monto: number; moneda: string; fuente: string; aprobado_por: string }[];
  capturas_por_aprobar: number; compromisos_90_dias: { moneda: string; monto: number; compromisos: number; proximo_vencimiento: string; aprobados: number }[] };
export type Projection = { mes: string; dias_transcurridos: number; dias_del_mes: number; pronostico_formal: unknown;
  lineas: { mercado: string; canal: string; moneda: string; real_al_dia: number; proyeccion_por_ritmo: number | null; meta: number | null; presupuesto: number | null;
    brecha_vs_meta: number | null; brecha_vs_presupuesto: number | null }[] };

export type Card =
  | { id: 1; titulo: string; semana: Block<Sales>; mes: Block<Sales>; presupuesto_semana: Block<{ lineas: BudgetLine[] }>; presupuesto_mes: Block<{ lineas: BudgetLine[] }> }
  | { id: 2; titulo: string; valor: Block<Goal300> }
  | { id: 3; titulo: string; valor: Block<Sales> }
  | { id: 4; titulo: string; valor: Block<{ cobertura_costo_pct: number | null; nota?: string }> }
  | { id: 5; titulo: string; valor: Block<Marketing> }
  | { id: 6; titulo: string; valor: Block<Inventory> }
  | { id: 7; titulo: string; valor: Block<Cash> }
  | { id: 8; titulo: string; valor: Block<Projection> };
export type Fuente = { fuente: string; estado: Disponibilidad | string; quien?: string; falta?: string; desde?: string | null; propuestas_pendientes?: number };
export type Cockpit = { ok: true; semana: { desde: string; hasta: string }; mes: { desde: string; hasta: string }; tarjetas: Card[]; fuentes: Block<{ fuentes: Fuente[] }> };

export type FxMonth = { id: string; moneda: string; mes: string; tasa: number; estado: 'proposed' | 'approved' | string; fuente: string; notas: string | null;
  propuesta_por: string | null; aprobada_por: string | null; aprobada: string | null };
export type FxStatus = { can_approve: boolean; approvers: string[]; latest: { moneda: string; fecha: string; tasa: number; fuente: string; leida: string }[];
  last_run: { ok: boolean; at: string; error: string | null } | null; months: FxMonth[]; manual: { moneda: string; fecha: string; tasa: number; fuente: string; por: string }[] };

export type BudgetVersion = { id: string; name: string; status: 'DRAFT' | 'APPROVED' | 'SUPERSEDED'; reason: string | null; supersedes: string | null; created_by: string;
  created_at: string; approved_at: string | null; approved_by: string | null; validated_by: string | null; validated_at: string | null; validation_note: string | null;
  content_hash: string | null; lines: { month: string; market: string; channel: string; currency: string; amount: number; note: string | null }[] };
export type Budgets = { ok: true; can_approve: boolean; versions: BudgetVersion[] };
export type GoalRow = { id: string; key: string; label: string; market: string | null; channel: string | null; currency: string; amount: number; from: string;
  reason: string; by: string; at: string; supersedes: string | null };
export type Goals = { ok: true; can_set: boolean; goals: GoalRow[] };

export type PrepEntry = { id: string; account: string; dimension: string; amount: number; currency: string; source: string; evidence: string | null; note: string | null;
  status: 'active' | 'voided'; captured_by: string; captured_at: string; mine: boolean; approved_by: string | null; approved_at: string | null; void_reason: string | null };
export type Commitment = { id: string; kind: string; counterparty: string; description: string | null; due_date: string; amount: number; currency: string;
  recurrence: 'una_vez' | 'mensual'; source: string; evidence: string | null; corrects: string | null; state: 'pendiente' | 'pagado' | string;
  captured_by: string; captured_at: string; approved_by: string | null; approved_at: string | null };
export type ClosePrep = { ok: true; me: string; accounts: { key: string; label: string; component: string; kind: 'FLOW' | 'BALANCE'; allow_negative: boolean }[];
  periods: { id: string; month: string; status: string; entries: PrepEntry[] }[]; commitments: Commitment[] };

async function call<T>(fn: string, args: Record<string, unknown> = {}): Promise<T | Denied> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: error.code === '42501' ? 'No disponible.' : 'No se pudo leer. Intenta de nuevo.' };
  return data as T | Denied;
}

export const getCockpit = (weekStart?: string) => call<Cockpit>('f360_intel_cockpit', weekStart ? { p_week_start: weekStart } : {});
export const getBudgets = (year: number) => call<Budgets>('f360_board_budgets', { p_fiscal_year: year });
export const getGoals = () => call<Goals>('f360_board_goals');
// f360_fx_status has no {ok}: it raises 42501 for anyone below operator → wrap it.
export async function getFxStatus(): Promise<({ ok: true } & FxStatus) | Denied> {
  const r = await call<FxStatus>('f360_fx_status');
  return 'ok' in r && r.ok === false ? r : { ok: true, ...(r as FxStatus) };
}
// One read per request (the layout and the page share it). Logged by the database as a FINANCIAL access.
export const getClosePrep = cache(() => call<ClosePrep>('f360_close_prep_context'));
export const writeCall = (fn: string, args: Record<string, unknown>) => call<{ ok: true } & Record<string, unknown>>(fn, args);

// ── Contadora (finance preparer) — NAVIGATION ONLY, never security ───────────────────────────────────────────────────────
// The database is the only gate (f360_board.require_finance_capture). There is no RPC that says "this caller is a preparer"
// before the second factor, so for a 'viewer' the app decides like this:
//   · session already aal2 → ask f360_close_prep_context: allowed = she is the contadora ('ok'); denied = a plain viewer ('none').
//   · session aal1 → 'mfa_required': every viewer is taken to the second-factor screen of Cierre contable first; after it,
//     a viewer who is not a preparer is denied by the database and goes back to the normal viewer screens.
// Owners/operators/sellers are never affected. (Backend gap reported in I2_COCKPIT_DELIVERY.md: f360_finance_access_state().)
export type FinanceAccess = 'ok' | 'mfa_required' | 'none';
export const financeAccess = cache(async (role: Role): Promise<FinanceAccess> => {
  if (role !== 'viewer') return 'none';
  const supabase = await createClient();
  const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
  if (data?.currentLevel !== 'aal2') return 'mfa_required';
  const ctx = await getClosePrep();
  return ctx.ok ? 'ok' : 'none';
});

// ── Presentation (no business math: formatting only) ─────────────────────────────────────────────────────────────────────
const SYMBOL: Record<string, string> = { MXN: '$', COP: '$', USD: 'US$' };
export function money(n: number | null | undefined, currency?: string | null, decimals = 0): string {
  if (n === null || n === undefined) return '—';
  const s = new Intl.NumberFormat('es-MX', { minimumFractionDigits: decimals, maximumFractionDigits: decimals }).format(Math.abs(n));
  return `${n < 0 ? '−' : ''}${currency ? SYMBOL[currency] ?? '' : ''}${s}${currency ? ` ${currency}` : ''}`;
}
// A change: always with its sign ("+$4,200 MXN", "−$1,400 MXN").
export const signed = (n: number | null | undefined, currency?: string | null) => (n === null || n === undefined ? '—' : `${n > 0 ? '+' : ''}${money(n, currency)}`);
export const num = (n: number | null | undefined, decimals = 0) =>
  n === null || n === undefined ? '—' : new Intl.NumberFormat('es-MX', { minimumFractionDigits: decimals, maximumFractionDigits: decimals }).format(n);
export const MONTHS_ES = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
export const monthLabel = (iso: string) => { const [y, m] = iso.slice(0, 10).split('-').map(Number); return `${MONTHS_ES[m - 1]} ${y}`; };
export const dayLabel = (iso: string) => { const [y, m, d] = iso.slice(0, 10).split('-').map(Number); return `${d} ${MONTHS_ES[m - 1].slice(0, 3)} ${y}`; };
export const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString('es-MX', { timeZone: 'America/Mexico_City', dateStyle: 'medium', timeStyle: 'short' }) : '—');
export const MARKET: Record<string, string> = { MX: 'México', CO: 'Colombia', ROW: 'Resto del mundo' };
export const CHANNEL: Record<string, string> = { online: 'en línea', store: 'tienda', remote: 'a distancia' };
// "1 USD = 17.21 MXN"; COP is tiny → "1 COP = 0.00540 MXN (≈ 185 COP por peso)". The inverse is only a reading aid of the same rate.
export function rateSentence(currency: string, rate: number): string {
  if (currency === 'COP' || rate < 0.1) return `1 ${currency} = ${num(rate, 5)} MXN (≈ ${num(1 / rate, 0)} ${currency} por peso)`;
  return `1 ${currency} = ${num(rate, 2)} MXN`;
}
