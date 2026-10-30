'use server';
// Growth → Clientas y Competencia — server actions. Who may write is decided in the database (customer_pii_viewers / owner).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type Result = { ok: true } | { ok: false; error: string };
const deny = (code?: string, msg?: string) => (code === '42501' ? 'Tu cuenta no tiene permiso para esta acción.' : msg ?? 'No se pudo guardar.');

export async function markOutreachAction(market: string, buyer: string, status: string, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_growth_outreach_mark', { p_market: market, p_buyer: buyer, p_status: status, p_note: note.trim() || null });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true };
}

export async function observeCompetitorAction(payload: Record<string, unknown>): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_competitor_observe', { p: payload });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true };
}
