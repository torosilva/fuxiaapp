'use server';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { boardCall } from '@/lib/board';

// Earn-in actions. The database re-checks everything (membership, CAP_TABLE scope, one pending proposal, cap / founder
// minimum, related party: Mario never approves): these functions only pass the form through and come back with its answer.
const back = (r: { ok: boolean; error?: unknown }, okMsg: string) => {
  revalidatePath('/estrategia/participacion');
  const msg = r.ok ? okMsg : String(r.error ?? 'No se pudo.');
  redirect(`/estrategia/participacion?${r.ok ? 'ok' : 'error'}=${encodeURIComponent(msg)}`);
};
const num = (v: FormDataEntryValue | null) => {
  const s = String(v ?? '').replace(/[,\s$%]/g, '');
  return s === '' ? null : Number(s);
};

export async function proposeTerms(f: FormData) {
  const milestones = [0, 1, 2, 3, 4, 5]
    .map((i) => ({
      year: num(f.get(`m${i}_year`)), revenue_target: num(f.get(`m${i}_target`)), equity_pct: num(f.get(`m${i}_pct`)),
      partial_from: num(f.get(`m${i}_from`)) ?? 0,
      // typed as a percentage (55) → stored as a fraction (0.55)
      gross_margin_min: num(f.get(`m${i}_margin`)) === null ? null : (num(f.get(`m${i}_margin`)) as number) / 100,
    }))
    .filter((m) => m.year !== null && m.revenue_target !== null && m.equity_pct !== null);
  const r = await boardCall('f360_board_earnin_propose', {
    p_idempotency_key: String(f.get('idempotency_key') ?? ''),
    p_terms: {
      entity_label: String(f.get('entity_label') ?? ''), initial_pct: num(f.get('initial_pct')), cap_pct: num(f.get('cap_pct')),
      founder_min_pct: num(f.get('founder_min_pct')), cash_commitment: num(f.get('cash_commitment')), cash_currency: 'MXN',
      revenue_definition: String(f.get('revenue_definition') ?? ''), excluded_markets: f.getAll('excluded').map(String),
      proposal_ref: String(f.get('proposal_ref') ?? '') || null, milestones,
    },
  });
  back(r, 'Propuesta registrada. Queda pendiente de que la apruebe Carolina.');
}

export async function actOnTerms(f: FormData) {
  const action = String(f.get('action') ?? '');
  const r = await boardCall('f360_board_decision_act', { p_id: String(f.get('decision_id') ?? ''), p_action: action, p_note: String(f.get('note') ?? '') || null });
  back(r, action === 'APPROVE' ? 'Términos aceptados para seguimiento (no es contrato firmado).' : action === 'REJECT' ? 'Propuesta rechazada.' : action === 'WITHDRAW' ? 'Propuesta retirada.' : 'Propuesta pospuesta.');
}
