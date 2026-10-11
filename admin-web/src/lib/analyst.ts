import { createClient } from '@/lib/supabase/server';

// AI Business Analyst (Centro de Inteligencia, I3) — types shared by /inteligencia and the reads of history / consumption.
export type Cifra = { valor: number; unidad?: string; moneda?: string };
export type Fuente = { herramienta: string; fuente: string; periodo: string; moneda?: string; actualizado?: string };
export type Reco = { texto: string; evidencia: string; impacto: string; responsable: string; medicion: string };
export type Answer = {
  resumen: string;
  hechos: { texto: string; cifras: Cifra[]; fuente: Fuente }[];
  calculos: { texto: string; formula: string; resultado?: Cifra; insumos?: Cifra[] }[];
  recomendaciones: Reco[];
  prioridades?: Reco[];
  faltantes: { que: string; quien: string }[];
  formato?: string;
};
export type AnalystResult = {
  ok: true; id: number | null; kind: 'pregunta' | 'prioridades'; answer: Answer; unverified: { hecho: string; valor: number }[];
  tools: { tool: string; args: unknown; disponibilidad: string | null; fuente: string | null }[]; sources: string[];
  usage: { input: number; output: number; cacheRead: number; cacheWrite: number; cost_usd: number; model: string; spent_month_usd: number; budget_usd: number; warning: boolean };
};
export type HistoryItem = { id: number; at: string; kind: string; question: string; status: string; answer: Answer | null; unverified: AnalystResult['unverified']; cost_usd: number; model: string | null };
export type Usage = {
  ok: true; can_change: boolean;
  settings: { enabled: boolean; model: string; monthly_budget_usd: number; per_user_daily: number; max_tool_calls: number; max_output_tokens: number; prices_source: string;
    price_input_mtok: number; price_output_mtok: number };
  month: { preguntas: number; costo_usd: number; promedio_usd: number; tokens_entrada: number; tokens_salida: number; por_estado: Record<string, number>; por_persona: { persona: string; preguntas: number; costo_usd: number }[] };
  changes: { at: string; by: string; reason: string }[];
};

// The ten executive questions approved by Mario (2026-10-11, Centro de Inteligencia §2).
export const PREGUNTAS = [
  '¿Cómo vamos esta semana y este mes en ventas, por país y canal, contra el presupuesto?',
  '¿Cuánto falta para los $300,000 de ecommerce México este mes y qué ritmo diario necesito?',
  '¿Qué país o canal subió o bajó contra el periodo anterior, y fue por número de pedidos o por ticket promedio?',
  '¿Cuál es el margen de contribución por país y canal?',
  '¿Cuánto vendimos por cada peso invertido en Meta, por país y por campaña?',
  '¿Dónde se pierde la venta en línea: visitas, producto, carrito, pago, compra?',
  '¿Cuántos pagos no se completan, con qué pasarela y cuánto dinero representan?',
  '¿Qué modelos tienen baja salida en México, cuánto inventario está detenido y qué se está agotando?',
  '¿Cuánto cerraremos el mes con el ritmo actual y cuál es la brecha contra la meta?',
  '¿Cuánta caja tenemos, qué entró y salió, y qué compromisos vienen?',
];

export async function analystHistory(): Promise<HistoryItem[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc('f360_ai_history');
  return data?.ok ? (data.items as HistoryItem[]) : [];
}
export async function analystUsage(): Promise<Usage | null> {
  const supabase = await createClient();
  const { data } = await supabase.rpc('f360_ai_usage');
  return data?.ok ? (data as Usage) : null;
}
