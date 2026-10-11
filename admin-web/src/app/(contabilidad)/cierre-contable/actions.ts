'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { writeCall } from '@/lib/intel';

// Cierre contable (I2) — the contadora's captures and the commitments. The database decides who may do what
// (f360_board.require_finance_capture: preparer or board FINANCIAL + second factor; only her own unapproved captures can be
// voided; approval only by a board member who did not capture it). These actions only pass the form through.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const s = (f: FormData, k: string) => String(f.get(k) ?? '').trim();
const amount = (v: string) => { const n = Number(v.replace(/[,\s$]/g, '')); return v !== '' && Number.isFinite(n) ? n : null; };
function back(f: FormData, r: { ok: boolean; error?: unknown }, okMsg: string, anchor = ''): never {
  revalidatePath('/cierre-contable');
  const mes = s(f, 'period_id');
  const msg = r.ok ? okMsg : String(r.error ?? 'No se pudo.');
  redirect(`/cierre-contable?${UUID.test(mes) ? `mes=${mes}&` : ''}${r.ok ? 'ok' : 'error'}=${encodeURIComponent(msg)}${anchor}`);
}

export async function addEntry(f: FormData) {
  const key = s(f, 'idempotency_key');
  const r = await writeCall('f360_close_prep_entry_add', {
    p_idempotency_key: UUID.test(key) ? key : null, p_period_id: UUID.test(s(f, 'period_id')) ? s(f, 'period_id') : null, p_account_key: s(f, 'account'),
    p_amount: amount(s(f, 'amount')), p_currency: s(f, 'currency'), p_source: s(f, 'source'), p_evidence_ref: s(f, 'evidence') || null,
    p_note: s(f, 'note') || null, p_dimension_key: '',
  });
  back(f, r, 'Monto guardado. Queda por aprobar (Mario o Carolina).', '#capturas');
}

export async function voidEntry(f: FormData) {
  const id = s(f, 'entry_id');
  const r = await writeCall('f360_close_prep_entry_void', { p_entry_id: UUID.test(id) ? id : null, p_reason: s(f, 'reason') });
  back(f, r, 'Captura anulada (queda en el historial).', '#capturas');
}

export async function addCommitment(f: FormData) {
  const corrects = s(f, 'corrects');
  const r = await writeCall('f360_finance_commitment_add', {
    p_kind: s(f, 'kind'), p_counterparty: s(f, 'counterparty'), p_description: s(f, 'description') || null,
    p_due_date: /^\d{4}-\d{2}-\d{2}$/.test(s(f, 'due_date')) ? s(f, 'due_date') : null, p_amount: amount(s(f, 'amount')), p_currency: s(f, 'currency'),
    p_recurrence: s(f, 'recurrence') || 'una_vez', p_source: s(f, 'source'), p_evidence_ref: s(f, 'evidence') || null,
    p_corrects: UUID.test(corrects) ? corrects : null, p_reason: s(f, 'reason') || null,
  });
  back(f, r, UUID.test(corrects) ? 'Corrección guardada: el compromiso original queda en el historial.' : 'Compromiso guardado.', '#compromisos');
}

export async function commitmentEvent(f: FormData) {
  const id = s(f, 'id');
  const action = s(f, 'action');
  const r = await writeCall('f360_finance_commitment_event', { p_id: UUID.test(id) ? id : null, p_action: action, p_reason: s(f, 'reason') || null });
  back(f, r, action === 'approved' ? 'Compromiso aprobado.' : action === 'paid' ? 'Marcado como pagado.' : 'Compromiso cancelado.', '#compromisos');
}
