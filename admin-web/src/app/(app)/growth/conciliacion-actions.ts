'use server';
// Conciliación de Ventas — server actions. Authorization lives in the database (f360.require_pii_viewer) and, for the Woo
// evidence, in f360-woo-sync (viewer check with the caller's token before any read; GETs only).
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { publisherAvailable } from '@/lib/env-guard';

type Result<T> = { ok: true; data: T } | { ok: false; error: string };
const deny = (code?: string, msg?: string) => (code === '42501' ? 'Solo Carolina y Mario pueden conciliar ventas.' : msg ?? 'No se pudo guardar.');

export type EvidenceDisplay = {
  evidence: { id: number; hash: string; result: string; transaction_ref: string | null; gateway_result: string; signals: string[] };
  display: { customer: { name: string | null; email: string | null }; payment_method_title: string | null;
    gateway_notes: { at: string; kind: string; text: string }[] };
  missing?: boolean;
};

export async function fetchEvidenceAction(targetKey: string, orderId: number): Promise<Result<EvidenceDisplay>> {
  if (!publisherAvailable()) return { ok: false, error: 'La conexión con WooCommerce todavía no está disponible en este ambiente.' };
  const supabase = await createClient();
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { ok: false, error: 'Tu sesión expiró. Vuelve a entrar.' };
  const url = new URL('f360-woo-sync', process.env.F360_PUBLISHER_URL!).toString();
  try {
    const res = await fetch(url, { method: 'POST', headers: { Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'order_evidence', target_key: targetKey, woo_order_id: orderId }), cache: 'no-store', signal: AbortSignal.timeout(60_000) });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) return { ok: false, error: body.error ?? 'No se pudo consultar WooCommerce.' };
    revalidatePath('/growth');
    return { ok: true, data: body as EvidenceDisplay };
  } catch {
    return { ok: false, error: 'WooCommerce no respondió. Intenta de nuevo en un momento.' };
  }
}

export async function decideAction(target: string, orderId: number, decision: string, comment: string, evidenceId: number | null,
  duplicateOf: number | null): Promise<Result<{ rec_state: string; conflict: string | null }>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('f360_rec_decide', { p_target: target, p_order: orderId, p_decision: decision,
    p_comment: comment.trim() || null, p_evidence_id: evidenceId, p_duplicate_of: duplicateOf });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true, data: data as { rec_state: string; conflict: string | null } };
}

export async function correctCurrencyAction(target: string, orderId: number, currency: string | null, reason: string, revert: boolean): Promise<Result<null>> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_rec_correct_currency', { p_target: target, p_order: orderId, p_currency: currency, p_reason: reason.trim(), p_revert: revert });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true, data: null };
}

export async function setAnalyticsAction(target: string, orderId: number, exclude: boolean, reason: string): Promise<Result<null>> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('f360_rec_set_analytics', { p_target: target, p_order: orderId, p_exclude: exclude, p_reason: reason });
  if (error) return { ok: false, error: deny(error.code, error.message) };
  revalidatePath('/growth');
  return { ok: true, data: null };
}
