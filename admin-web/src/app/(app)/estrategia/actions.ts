'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { boardCall } from '@/lib/board';

// Monthly close actions. The server re-checks EVERYTHING (membership, scope, month state, capture ≠ approval, amounts):
// these functions only pass the form through and come back to the month with the database's answer.
const back = (periodId: string, r: { ok: boolean; error?: unknown }, okMsg: string) => {
  revalidatePath(`/estrategia/cierre/${periodId}`);
  revalidatePath('/estrategia');
  const msg = r.ok ? okMsg : String(r.error ?? 'No se pudo.');
  redirect(`/estrategia/cierre/${periodId}?${r.ok ? 'ok' : 'error'}=${encodeURIComponent(msg)}`);
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const periodOf = (f: FormData) => { const p = String(f.get('period_id') ?? ''); if (!uuid.test(p)) redirect('/estrategia'); return p; };

export async function captureEntry(f: FormData) {
  const periodId = periodOf(f);
  const amount = Number(String(f.get('amount') ?? '').replace(/[,\s$]/g, ''));
  const r = await boardCall('f360_board_close_entry_add', {
    p_idempotency_key: String(f.get('idempotency_key') ?? ''), p_period_id: periodId, p_account_key: String(f.get('account') ?? ''),
    p_amount: Number.isFinite(amount) ? amount : null, p_currency: String(f.get('currency') ?? ''), p_source: String(f.get('source') ?? ''),
    p_evidence_ref: String(f.get('evidence') ?? '') || null, p_note: String(f.get('note') ?? '') || null, p_dimension_key: String(f.get('dimension') ?? ''),
  });
  back(periodId, r, 'Captura guardada.');
}

export async function voidEntry(f: FormData) {
  const periodId = periodOf(f);
  const r = await boardCall('f360_board_close_entry_void', { p_entry_id: String(f.get('entry_id') ?? ''), p_reason: String(f.get('reason') ?? '') });
  back(periodId, r, 'Captura anulada.');
}

export async function approveEntries(f: FormData) {
  const periodId = periodOf(f);
  const r = await boardCall('f360_board_close_entries_approve', { p_period_id: periodId });
  back(periodId, r, r.ok ? `Aprobadas: ${String(r.approved ?? 0)}.${r.note ? ` ${String(r.note)}` : ''}` : '');
}

export async function transitionPeriod(f: FormData) {
  const periodId = periodOf(f);
  const r = await boardCall('f360_board_period_transition', {
    p_period_id: periodId, p_to_status: String(f.get('to') ?? ''), p_reason: String(f.get('reason') ?? '') || null,
    p_exception_note: String(f.get('exception') ?? '') || null,
  });
  back(periodId, r, 'Estado del mes actualizado.');
}
