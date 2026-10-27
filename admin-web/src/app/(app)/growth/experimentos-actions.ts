'use server';
// Growth → Experimentos — server actions. All rules (who may approve, frozen fields, verdict vs. thresholds, measurement) live in
// the database (f360_experiment_save / f360_experiment_transition); identity comes from the session.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type Result = { ok: true; id?: string } | { ok: false; error: string };
const deny = (code?: string, msg?: string) => (code === '42501' ? 'Tu cuenta no tiene permiso para esta acción.' : msg ?? 'No se pudo guardar.');

export async function saveExperimentAction(id: string | null, payload: Record<string, unknown>): Promise<Result> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_experiment_save', { p_id: id, p: payload });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true, id: (data as { id: string }).id };
}

export async function transitionExperimentAction(id: string, to: string, learning: string, decision: string, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_experiment_transition', { p_id: id, p_to: to, p_learning: learning.trim() || null,
    p_decision: decision || null, p_reason: reason.trim() || null });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true };
}
