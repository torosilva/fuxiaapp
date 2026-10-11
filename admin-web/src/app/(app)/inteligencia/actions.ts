'use server';
// AI Business Analyst — server actions. The question goes to the f360-analyst Edge Function with the user's own session;
// every number it uses is read there through the board-gated metrics layer (no SQL, no writes). Limits and audit live in the
// database (f360_ai_quota / f360_ai_log); this file only relays.
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { publisherAvailable } from '@/lib/env-guard';
import type { AnalystResult } from '@/lib/analyst';

type Result<T> = { ok: true; data: T } | { ok: false; error: string };

export async function askAction(question: string, kind: 'pregunta' | 'prioridades'): Promise<Result<AnalystResult>> {
  if (!publisherAvailable()) return { ok: false, error: 'El analista todavía no está disponible en este ambiente.' };
  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  try {
    const res = await fetch(new URL('f360-analyst', process.env.F360_PUBLISHER_URL!).toString(), {
      method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ question, kind }), cache: 'no-store', signal: AbortSignal.timeout(150_000) });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) return { ok: false, error: body.error ?? 'El analista no respondió.' };
    revalidatePath('/inteligencia');
    return { ok: true, data: body as AnalystResult };
  } catch {
    return { ok: false, error: 'El analista tardó demasiado. Intenta con una pregunta más concreta.' };
  }
}

export async function setLimitsAction(patch: Record<string, number | boolean>, reason: string): Promise<Result<null>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_ai_settings_set', { p_patch: patch, p_reason: reason });
  if (error) return { ok: false, error: 'No se pudo guardar.' };
  if (!data?.ok) return { ok: false, error: data?.error ?? 'No se pudo guardar.' };
  revalidatePath('/inteligencia');
  return { ok: true, data: null };
}
