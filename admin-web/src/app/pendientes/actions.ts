'use server';
import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type R = { ok: true } | { ok: false; error: string };
async function call(fn: string, args: Record<string, unknown>): Promise<R> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, args);
  if (error) return { ok: false, error: error.code === '42501' ? 'No tienes permiso para esto.' : error.message };
  revalidatePath('/pendientes');
  return { ok: true };
}

// The database decides whose card it is (by the caller's WhatsApp): a person can only ever save their own.
export async function saveCardAction(week: string, commitment: string, done: string, numbers: Record<string, number | null>, status: string | null) {
  return call('f360_weekly_card_save', { p_week: week, p_commitment: commitment, p_done: done, p_numbers: numbers, p_status: status });
}
export async function saveMetricsAction(week: string, values: Record<string, number | null>, decision: string) {
  return call('f360_weekly_metrics_save', { p_week: week, p_values: values, p_decision: decision });
}
export async function setAgencyPhoneAction(phone: string, name: string) {
  return call('f360_weekly_person_set', { p_person_key: 'AGENCIA', p_phone: phone, p_name: name });
}
